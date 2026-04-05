use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        Path, State,
    },
    http::{HeaderMap, HeaderName, HeaderValue, Method, StatusCode},
    response::{IntoResponse, Response},
    routing::{any, get, post},
    Json, Router,
};
use base64::{engine::general_purpose::STANDARD as B64, Engine};
use dashmap::DashMap;
use futures::{stream, SinkExt, StreamExt};
use rand::Rng;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    convert::Infallible,
    str::FromStr,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use tokio::sync::mpsc;
use tower_http::cors::{Any, CorsLayer};
use tower_http::limit::RequestBodyLimitLayer;
use tracing::{info, warn};
use uuid::Uuid;

// ─────────────────────────── Types ───────────────────────────

/// Message sent from relay to a connected NOU node
#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "type", rename_all = "snake_case")]
enum RelayToNode {
    Welcome { public_url: String, node_id: String },
    Ping,
    /// Forward an incoming HTTP request to the node
    Req {
        req_id: String,
        method: String,
        path: String,
        headers: HashMap<String, String>,
        body_b64: String,
    },
}

/// Message sent from a NOU node to the relay
#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "type", rename_all = "snake_case")]
enum NodeToRelay {
    Hello { node_id: String, secret: String, label: Option<String> },
    Pong,
    /// HTTP response header (sent first)
    ResHeader {
        req_id: String,
        status: u16,
        headers: HashMap<String, String>,
    },
    /// Streaming body chunk
    ResChunk { req_id: String, data_b64: String },
    /// End of response
    ResDone { req_id: String },
    /// Error
    ResErr { req_id: String, message: String },
}

/// Per-request channel: relay waits on this for response chunks
enum ResponseItem {
    Header { status: u16, headers: HashMap<String, String> },
    Chunk(Vec<u8>),
    Done,
    Err(String),
}

/// Active node connection: a channel to send forwarded requests
#[derive(Clone)]
struct NodeConn {
    tx: mpsc::Sender<RelayToNode>,
    label: Option<String>,
    connected_at: Instant,
}

// ─────────────────────────── State ───────────────────────────

#[derive(Clone)]
struct AppState {
    /// nodeID → active WebSocket sender
    nodes: Arc<DashMap<String, NodeConn>>,
    /// nodeID → hashed secret (hex) — in-memory cache, backed by SQLite
    secrets: Arc<DashMap<String, String>>,
    /// reqID → channel waiting for response parts
    pending: Arc<DashMap<String, mpsc::Sender<ResponseItem>>>,
    /// SQLite connection for persisting secrets across restarts
    db: Arc<Mutex<Connection>>,
    /// Public base URL (from env NOU_RELAY_URL)
    base_url: String,
}

impl AppState {
    fn new() -> Self {
        let base_url = std::env::var("NOU_RELAY_URL")
            .unwrap_or_else(|_| "https://nou-relay.fly.dev".to_string());

        let db_path = std::env::var("DB_PATH")
            .unwrap_or_else(|_| "/data/secrets.db".to_string());

        let conn = Connection::open(&db_path).unwrap_or_else(|e| {
            warn!("Could not open DB at {db_path}: {e}. Falling back to in-memory.");
            Connection::open_in_memory().expect("in-memory DB")
        });
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS secrets (
                node_id TEXT PRIMARY KEY,
                hashed_secret TEXT NOT NULL
             );"
        ).expect("DB init");

        // Load persisted secrets into the in-memory DashMap
        let secrets: Arc<DashMap<String, String>> = Arc::new(DashMap::new());
        {
            let mut stmt = conn.prepare("SELECT node_id, hashed_secret FROM secrets").unwrap();
            let rows = stmt.query_map([], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
            }).unwrap();
            let mut count = 0usize;
            for row in rows.flatten() {
                secrets.insert(row.0, row.1);
                count += 1;
            }
            info!("Loaded {count} node secrets from DB");
        }

        Self {
            nodes: Arc::new(DashMap::new()),
            secrets,
            pending: Arc::new(DashMap::new()),
            db: Arc::new(Mutex::new(conn)),
            base_url,
        }
    }

    fn node_url(&self, node_id: &str) -> String {
        format!("{}/n/{}", self.base_url, node_id)
    }

    fn generate_secret() -> String {
        let bytes: Vec<u8> = (0..32).map(|_| rand::thread_rng().gen()).collect();
        hex::encode(bytes)
    }

    fn hash_secret(s: &str) -> String {
        use sha2::{Digest, Sha256};
        let mut h = Sha256::new();
        h.update(s.as_bytes());
        hex::encode(h.finalize())
    }
}

// ─────────────────────────── WebSocket handler ───────────────────────────

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> Response {
    ws.on_upgrade(|socket| handle_socket(socket, state))
}

async fn handle_socket(socket: WebSocket, state: AppState) {
    let (mut sink, mut stream) = socket.split();

    // Wait for Hello message (first message within 10s)
    let hello = tokio::time::timeout(Duration::from_secs(10), stream.next()).await;
    let Ok(Some(Ok(msg))) = hello else {
        warn!("Node didn't send Hello in time");
        return;
    };

    let text = match msg {
        Message::Text(t) => t,
        _ => { warn!("Expected text Hello"); return; }
    };

    let hello_msg: NodeToRelay = match serde_json::from_str(&text) {
        Ok(m) => m,
        Err(e) => { warn!("Bad Hello JSON: {e}"); return; }
    };

    let (node_id, secret, label) = match hello_msg {
        NodeToRelay::Hello { node_id, secret, label } => (node_id, secret, label),
        _ => { warn!("Expected Hello"); return; }
    };

    // Verify secret — must have been pre-registered via POST /api/register
    let hashed = AppState::hash_secret(&secret);
    match state.secrets.get(&node_id) {
        Some(stored) if *stored == hashed => {} // OK
        Some(_) => {
            let _ = sink.send(Message::Text(r#"{"error":"invalid secret"}"#.into())).await;
            warn!("Node {node_id}: wrong secret");
            return;
        }
        None => {
            // node_id not registered — reject; must call /api/register first
            let _ = sink.send(Message::Text(r#"{"error":"unknown node_id, call /api/register first"}"#.into())).await;
            warn!("Node {node_id}: not registered");
            return;
        }
    }

    // Create channel for incoming forwarded requests
    let (req_tx, mut req_rx) = mpsc::channel::<RelayToNode>(32);
    state.nodes.insert(node_id.clone(), NodeConn {
        tx: req_tx,
        label: label.clone(),
        connected_at: Instant::now(),
    });

    info!("Node connected: {node_id} ({:?})", label);

    // Send Welcome
    let welcome = RelayToNode::Welcome {
        public_url: state.node_url(&node_id),
        node_id: node_id.clone(),
    };
    if sink.send(Message::Text(serde_json::to_string(&welcome).unwrap())).await.is_err() {
        state.nodes.remove(&node_id);
        return;
    }

    // Spawn writer task: forwards incoming requests to the node
    let mut sink = sink;
    let write_task = tokio::spawn(async move {
        while let Some(msg) = req_rx.recv().await {
            let text = serde_json::to_string(&msg).unwrap();
            if sink.send(Message::Text(text)).await.is_err() {
                break;
            }
        }
    });

    // Reader loop: receives responses from the node
    let state_clone = state.clone();
    let node_id_clone = node_id.clone();
    while let Some(Ok(msg)) = stream.next().await {
        match msg {
            Message::Text(text) => {
                match serde_json::from_str::<NodeToRelay>(&text) {
                    Ok(NodeToRelay::Pong) => {} // heartbeat OK
                    Ok(NodeToRelay::ResHeader { req_id, status, headers }) => {
                        if let Some(tx) = state_clone.pending.get(&req_id) {
                            let _ = tx.send(ResponseItem::Header { status, headers }).await;
                        }
                    }
                    Ok(NodeToRelay::ResChunk { req_id, data_b64 }) => {
                        if let Some(tx) = state_clone.pending.get(&req_id) {
                            if let Ok(bytes) = B64.decode(&data_b64) {
                                let _ = tx.send(ResponseItem::Chunk(bytes)).await;
                            }
                        }
                    }
                    Ok(NodeToRelay::ResDone { req_id }) => {
                        if let Some(tx) = state_clone.pending.get(&req_id) {
                            let _ = tx.send(ResponseItem::Done).await;
                        }
                        state_clone.pending.remove(&req_id);
                    }
                    Ok(NodeToRelay::ResErr { req_id, message }) => {
                        if let Some(tx) = state_clone.pending.get(&req_id) {
                            let _ = tx.send(ResponseItem::Err(message)).await;
                        }
                        state_clone.pending.remove(&req_id);
                    }
                    _ => {}
                }
            }
            Message::Close(_) => break,
            Message::Ping(p) => {
                // axum handles pong automatically
                let _ = p;
            }
            _ => {}
        }
    }

    // Cleanup: drain all pending requests for this node with an error
    // (avoids permanent memory leaks when node disconnects mid-request)
    let disconnected_reqs: Vec<String> = state.pending.iter()
        .map(|e| e.key().clone())
        .collect();
    for req_id in disconnected_reqs {
        if let Some((_, tx)) = state.pending.remove(&req_id) {
            let _ = tx.send(ResponseItem::Err("node disconnected".to_string())).await;
        }
    }
    state.nodes.remove(&node_id_clone);
    write_task.abort();
    info!("Node disconnected: {node_id_clone}");
}

// ─────────────────────────── Proxy endpoint ───────────────────────────

/// GET|POST /n/{node_id}/* → forward to the NOU node
async fn proxy_handler(
    Path((node_id, tail)): Path<(String, String)>,
    method: Method,
    req_headers: HeaderMap,
    State(state): State<AppState>,
    body: axum::body::Bytes,
) -> Response {
    let conn = match state.nodes.get(&node_id) {
        Some(c) => c.clone(),
        None => {
            return (
                StatusCode::BAD_GATEWAY,
                Json(serde_json::json!({"error": "node not connected", "node_id": node_id})),
            ).into_response();
        }
    };

    let req_id = Uuid::new_v4().to_string();
    let (resp_tx, mut resp_rx) = mpsc::channel::<ResponseItem>(256);
    state.pending.insert(req_id.clone(), resp_tx);

    // Convert headers
    let mut headers_map: HashMap<String, String> = HashMap::new();
    for (k, v) in &req_headers {
        if let Ok(val) = v.to_str() {
            // Forward auth and content-type; skip host/connection
            let name = k.as_str().to_lowercase();
            if name == "authorization" || name == "content-type" || name == "x-nou-" {
                headers_map.insert(name, val.to_string());
            }
        }
    }

    let path = format!("/{}", tail);
    let msg = RelayToNode::Req {
        req_id: req_id.clone(),
        method: method.to_string(),
        path,
        headers: headers_map,
        body_b64: B64.encode(&body),
    };

    // Send request to node
    if conn.tx.send(msg).await.is_err() {
        state.pending.remove(&req_id);
        return (
            StatusCode::BAD_GATEWAY,
            Json(serde_json::json!({"error": "node channel closed"})),
        ).into_response();
    }

    // Wait for response header (max 30s)
    let header_timeout = tokio::time::timeout(Duration::from_secs(30), resp_rx.recv()).await;
    let (status_code, resp_headers) = match header_timeout {
        Ok(Some(ResponseItem::Header { status, headers })) => (status, headers),
        Ok(Some(ResponseItem::Err(e))) => {
            state.pending.remove(&req_id);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": e})),
            ).into_response();
        }
        _ => {
            state.pending.remove(&req_id);
            return (
                StatusCode::GATEWAY_TIMEOUT,
                Json(serde_json::json!({"error": "node timeout"})),
            ).into_response();
        }
    };

    // Stream body back
    let _is_streaming = resp_headers.get("content-type")
        .map(|v| v.contains("text/event-stream"))
        .unwrap_or(false);

    let body_stream = stream::unfold(resp_rx, |mut rx| async move {
        match rx.recv().await {
            Some(ResponseItem::Chunk(bytes)) => Some((Ok::<_, Infallible>(axum::body::Bytes::from(bytes)), rx)),
            Some(ResponseItem::Done) | None => None,
            Some(ResponseItem::Err(_)) => None,
            Some(ResponseItem::Header { .. }) => None, // shouldn't happen
        }
    });

    let mut builder = axum::response::Response::builder()
        .status(StatusCode::from_u16(status_code).unwrap_or(StatusCode::OK));

    for (k, v) in &resp_headers {
        if let (Ok(name), Ok(val)) = (
            HeaderName::from_str(k),
            HeaderValue::from_str(v),
        ) {
            builder = builder.header(name, val);
        }
    }
    // CORS
    builder = builder.header("access-control-allow-origin", "*");

    builder
        .body(axum::body::Body::from_stream(body_stream))
        .unwrap_or_else(|_| StatusCode::INTERNAL_SERVER_ERROR.into_response())
}

// ─────────────────────────── Node registration API ───────────────────────────

#[derive(Serialize)]
struct RegisterResp {
    node_id: String,
    secret: String,
    ws_url: String,
    public_url: String,
}

/// POST /api/register — register a new node (UUID is always server-assigned; client hint ignored)
/// Re-registration: if node_id already exists, returns 409 Conflict.
/// To get a fresh secret, the node must use the node_id it received initially.
async fn register(
    State(state): State<AppState>,
) -> Response {
    // Always generate a new UUID server-side — never trust client-supplied node_id
    let node_id = Uuid::new_v4().to_string();
    let secret = AppState::generate_secret();
    let hashed = AppState::hash_secret(&secret);

    // Persist to SQLite (blocking, but registration is rare)
    {
        let db = state.db.lock().unwrap();
        if let Err(e) = db.execute(
            "INSERT OR REPLACE INTO secrets (node_id, hashed_secret) VALUES (?1, ?2)",
            rusqlite::params![node_id, hashed],
        ) {
            warn!("Failed to persist secret for {node_id}: {e}");
        }
    }

    state.secrets.insert(node_id.clone(), hashed);
    info!("Registered new node: {node_id}");
    let ws_url = format!("{}/ws", state.base_url.replace("https://", "wss://"));
    Json(RegisterResp {
        public_url: state.node_url(&node_id),
        ws_url,
        node_id,
        secret,
    }).into_response()
}

// ─────────────────────────── Status ───────────────────────────

async fn status(State(state): State<AppState>) -> Json<serde_json::Value> {
    let nodes: Vec<serde_json::Value> = state.nodes.iter().map(|e| {
        serde_json::json!({
            "node_id": e.key(),
            "label": e.value().label,
            "url": state.node_url(e.key()),
            "uptime_secs": e.value().connected_at.elapsed().as_secs(),
        })
    }).collect();
    Json(serde_json::json!({
        "status": "ok",
        "nodes": nodes,
        "node_count": nodes.len(),
    }))
}

// ─────────────────────────── Main ───────────────────────────

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(std::env::var("RUST_LOG").unwrap_or_else(|_| "info".to_string()))
        .init();

    let state = AppState::new();

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/ws", get(ws_handler))
        .route("/api/register", post(register))
        .route("/api/status", get(status))
        .route("/n/:node_id/*tail", any(proxy_handler))
        .route("/health", get(|| async { "ok" }))
        .layer(RequestBodyLimitLayer::new(50 * 1024 * 1024)) // 50MB max
        .layer(cors)
        .with_state(state);

    let port = std::env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let addr = format!("0.0.0.0:{port}");
    info!("NOU Relay listening on {addr}");

    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
