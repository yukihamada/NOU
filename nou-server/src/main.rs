use axum::{
    body::Body,
    extract::{Request, State},
    http::{HeaderMap, HeaderName, HeaderValue, StatusCode},
    response::{Html, IntoResponse, Response},
    routing::{any, get},
    Router,
};
use bytes::Bytes;
use clap::Parser;
use futures_util::StreamExt;
use colored::*;
use reqwest::Client;
use serde_json::{json, Value};
use std::{net::SocketAddr, sync::Arc, time::Duration};
use tokio::net::TcpListener;
use tokio_util::io::ReaderStream;

// ─── CLI ───────────────────────────────────────────────────────

#[derive(Parser)]
#[command(name = "nou-server", about = "NOU local AI server — cross-platform")]
struct Cli {
    /// Port to listen on
    #[arg(long, default_value = "4001")]
    port: u16,
    /// Ollama base URL
    #[arg(long, default_value = "http://127.0.0.1:11434")]
    ollama: String,
    /// Default model to use
    #[arg(long, default_value = "gemma3:4b")]
    model: String,
}

// ─── State ─────────────────────────────────────────────────────

#[derive(Clone)]
struct AppState {
    client: Client,
    ollama_base: String,
    default_model: String,
}

// ─── Dashboard HTML ─────────────────────────────────────────────

const DASHBOARD: &str = r#"<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>NOU — ローカルAIサーバー</title>
<style>
:root{--bg:#0a0a0a;--card:#111;--border:rgba(255,255,255,.08);--text:#e6edf3;--muted:#8b949e;--green:#3fb950;--blue:#58a6ff;--yellow:#e3b341;--grad:linear-gradient(135deg,#58a6ff,#3fb950)}
*{margin:0;padding:0;box-sizing:border-box}
body{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;min-height:100vh;padding:32px 24px}
.header{display:flex;align-items:center;gap:16px;margin-bottom:40px}
.logo{font-size:28px;font-weight:900;background:var(--grad);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.badge{font-size:11px;padding:3px 10px;border-radius:20px;background:rgba(88,166,255,.15);border:1px solid rgba(88,166,255,.3);color:var(--blue)}
.status-row{display:flex;gap:16px;flex-wrap:wrap;margin-bottom:32px}
.stat-card{flex:1;min-width:160px;background:var(--card);border:1px solid var(--border);border-radius:12px;padding:20px}
.stat-label{font-size:12px;color:var(--muted);margin-bottom:8px}
.stat-value{font-size:20px;font-weight:700}
.green{color:var(--green)} .blue{color:var(--blue)} .yellow{color:var(--yellow)}
.section{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:24px;margin-bottom:20px}
.section-title{font-size:14px;font-weight:600;margin-bottom:16px;color:var(--muted);text-transform:uppercase;letter-spacing:.5px}
.model-row{display:flex;align-items:center;justify-content:space-between;padding:10px 0;border-bottom:1px solid var(--border)}
.model-row:last-child{border-bottom:none}
.model-name{font-weight:600}
.model-meta{font-size:12px;color:var(--muted)}
.dot{width:8px;height:8px;border-radius:50%;background:var(--green);display:inline-block;margin-right:6px}
.dot.off{background:#555}
.code-block{background:#010409;border:1px solid var(--border);border-radius:8px;padding:14px 16px;font-family:'SF Mono',Consolas,monospace;font-size:12px;color:#e6edf3;overflow-x:auto;position:relative}
.copy-btn{position:absolute;top:8px;right:8px;background:rgba(255,255,255,.1);border:none;color:var(--muted);padding:4px 10px;border-radius:6px;cursor:pointer;font-size:11px}
.copy-btn:hover{background:rgba(255,255,255,.2)}
.gr{color:var(--muted)} .hl{color:#79c0ff} .pu{color:#d2a8ff} .wh{color:#e6edf3}
.footer{text-align:center;color:var(--muted);font-size:12px;margin-top:40px}
a{color:var(--blue);text-decoration:none}
.pill{display:inline-block;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:600}
.pill-green{background:rgba(63,185,80,.15);color:var(--green);border:1px solid rgba(63,185,80,.3)}
.pill-gray{background:rgba(139,148,158,.1);color:var(--muted);border:1px solid rgba(139,148,158,.2)}
</style>
</head>
<body>
<div class="header">
  <div class="logo">NOU</div>
  <div class="badge" id="version-badge">v0.1.0 Linux/Windows</div>
</div>

<div class="status-row">
  <div class="stat-card">
    <div class="stat-label">サーバー状態</div>
    <div class="stat-value green" id="server-status">● 稼働中</div>
  </div>
  <div class="stat-card">
    <div class="stat-label">Ollama</div>
    <div class="stat-value" id="ollama-status">確認中...</div>
  </div>
  <div class="stat-card">
    <div class="stat-label">エンドポイント</div>
    <div class="stat-value blue" id="endpoint">:4001</div>
  </div>
</div>

<div class="section">
  <div class="section-title">利用可能なモデル</div>
  <div id="models-list"><div style="color:var(--muted);font-size:13px">読み込み中...</div></div>
</div>

<div class="section">
  <div class="section-title">Claude Code / Cursor に接続</div>
  <div class="code-block">
    <span class="gr"># .env または環境変数に追加</span><br>
    <span class="wh">ANTHROPIC_BASE_URL</span>=<span class="hl">http://localhost:4001</span><br>
    <span class="wh">ANTHROPIC_API_KEY</span>=<span class="pu">sk-dummy</span>
    <button class="copy-btn" onclick="copyText('ANTHROPIC_BASE_URL=http://localhost:4001\nANTHROPIC_API_KEY=sk-dummy')">コピー</button>
  </div>
  <div class="code-block" style="margin-top:12px">
    <span class="gr"># aider</span><br>
    <span class="wh">OPENAI_API_BASE</span>=<span class="hl">http://localhost:4001/v1</span> \<br>
    <span class="wh">OPENAI_API_KEY</span>=<span class="pu">sk-dummy</span> \<br>
    aider <span class="gr">--model</span> openai/gemma3:4b
    <button class="copy-btn" onclick="copyText('OPENAI_API_BASE=http://localhost:4001/v1 \\\nOPENAI_API_KEY=sk-dummy \\\naider --model openai/gemma3:4b')">コピー</button>
  </div>
</div>

<div class="section">
  <div class="section-title">モデルのインストール (Ollama)</div>
  <div class="code-block">
    <span class="gr"># おすすめ: Gemma 4</span><br>
    ollama pull gemma3:4b<br><br>
    <span class="gr"># コーディング特化</span><br>
    ollama pull qwen2.5-coder:7b<br><br>
    <span class="gr"># 高精度 (32GB+ RAM)</span><br>
    ollama pull qwen2.5:32b
    <button class="copy-btn" onclick="copyText('ollama pull gemma3:4b')">コピー</button>
  </div>
</div>

<div class="footer">
  NOU Server v0.1.0 · <a href="https://github.com/enablerdao/NOU">GitHub</a> · MIT License
</div>

<script>
function copyText(t){navigator.clipboard.writeText(t)}

async function refresh(){
  try{
    const r = await fetch('/api/status');
    const d = await r.json();
    document.getElementById('ollama-status').textContent = d.ollama_ok ? '● 接続済み' : '✕ 未接続';
    document.getElementById('ollama-status').className = 'stat-value ' + (d.ollama_ok?'green':'yellow');
    document.getElementById('endpoint').textContent = ':' + d.port;

    const ml = document.getElementById('models-list');
    if(d.models && d.models.length > 0){
      ml.innerHTML = d.models.map(m=>`
        <div class="model-row">
          <div><div class="model-name"><span class="dot"></span>${m.name}</div></div>
          <div class="pill pill-green">稼働中</div>
        </div>`).join('');
    } else {
      ml.innerHTML = '<div style="color:var(--yellow);font-size:13px">⚠ モデルが見つかりません。<code>ollama pull gemma3:4b</code> を実行してください。</div>';
    }
  } catch(e){
    document.getElementById('ollama-status').textContent = '✕ エラー';
  }
}

refresh();
setInterval(refresh, 5000);
</script>
</body>
</html>"#;

// ─── Handlers ───────────────────────────────────────────────────

async fn dashboard() -> Html<&'static str> {
    Html(DASHBOARD)
}

async fn health() -> impl IntoResponse {
    axum::Json(json!({"status": "ok", "service": "nou-server"}))
}

async fn api_status(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let port = std::env::var("PORT").unwrap_or_else(|_| "4001".to_string());

    // Check ollama
    let ollama_ok = state
        .client
        .get(format!("{}/api/version", state.ollama_base))
        .timeout(Duration::from_secs(2))
        .send()
        .await
        .is_ok();

    let models_parsed: Vec<Value> = if ollama_ok {
        match state
            .client
            .get(format!("{}/api/tags", state.ollama_base))
            .timeout(Duration::from_secs(3))
            .send()
            .await
        {
            Ok(r) => r
                .json::<Value>()
                .await
                .ok()
                .and_then(|v| v.get("models").and_then(|m| m.as_array()).cloned())
                .unwrap_or_default()
                .into_iter()
                .map(|m| {
                    json!({
                        "name": m.get("name").and_then(|n| n.as_str()).unwrap_or("unknown"),
                    })
                })
                .collect(),
            Err(_) => vec![],
        }
    } else {
        vec![]
    };

    axum::Json(json!({
        "ok": true,
        "port": port,
        "ollama_ok": ollama_ok,
        "models": models_parsed,
    }))
}

async fn list_models(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    match state
        .client
        .get(format!("{}/v1/models", state.ollama_base))
        .timeout(Duration::from_secs(3))
        .send()
        .await
    {
        Ok(resp) => {
            let status = StatusCode::from_u16(resp.status().as_u16())
                .unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
            let body = resp.bytes().await.unwrap_or_default();
            (status, body).into_response()
        }
        Err(_) => (
            StatusCode::SERVICE_UNAVAILABLE,
            axum::Json(json!({"error": "ollama not available. Run: ollama serve"})),
        )
            .into_response(),
    }
}

async fn proxy_handler(
    State(state): State<Arc<AppState>>,
    req: Request,
) -> Response {
    let path = req.uri().path_and_query().map(|p| p.as_str()).unwrap_or("/");
    let target_url = format!("{}{}", state.ollama_base, path);

    let method =
        reqwest::Method::from_bytes(req.method().as_str().as_bytes()).unwrap_or(reqwest::Method::GET);

    // Read body
    let (parts, body) = req.into_parts();
    let body_bytes = match axum::body::to_bytes(body, 10 * 1024 * 1024).await {
        Ok(b) => b,
        Err(_) => {
            return (StatusCode::BAD_REQUEST, "body read error").into_response();
        }
    };

    // Forward headers
    let mut headers = reqwest::header::HeaderMap::new();
    for (k, v) in &parts.headers {
        if k == "host" || k == "transfer-encoding" {
            continue;
        }
        if let (Ok(name), Ok(val)) = (
            reqwest::header::HeaderName::from_bytes(k.as_str().as_bytes()),
            reqwest::header::HeaderValue::from_bytes(v.as_bytes()),
        ) {
            headers.insert(name, val);
        }
    }

    let req_builder = state
        .client
        .request(method, &target_url)
        .headers(headers)
        .body(body_bytes)
        .timeout(Duration::from_secs(300));

    match req_builder.send().await {
        Ok(resp) => {
            let status =
                StatusCode::from_u16(resp.status().as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
            let mut resp_headers = HeaderMap::new();
            for (k, v) in resp.headers() {
                if let (Ok(name), Ok(val)) = (
                    HeaderName::from_bytes(k.as_str().as_bytes()),
                    HeaderValue::from_bytes(v.as_bytes()),
                ) {
                    resp_headers.insert(name, val);
                }
            }
            let stream = ReaderStream::new(tokio_util::io::StreamReader::new(
                resp.bytes_stream()
                    .map(|r: Result<Bytes, _>| r.map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))),
            ));
            let body = Body::from_stream(stream);
            let mut response = Response::new(body);
            *response.status_mut() = status;
            *response.headers_mut() = resp_headers;
            response
        }
        Err(e) => {
            let msg = if e.is_timeout() {
                "request timeout"
            } else {
                "ollama not available. Is ollama running? Try: ollama serve"
            };
            (
                StatusCode::SERVICE_UNAVAILABLE,
                axum::Json(json!({"error": {"message": msg, "type": "server_error"}})),
            )
                .into_response()
        }
    }
}

// ─── Startup banner ─────────────────────────────────────────────

fn print_banner(port: u16, ollama_base: &str, model: &str) {
    println!();
    println!("{}", "  ███╗   ██╗ ██████╗ ██╗   ██╗".bright_white());
    println!("{}", "  ████╗  ██║██╔═══██╗██║   ██║".bright_white());
    println!("{}", "  ██╔██╗ ██║██║   ██║██║   ██║".bright_white());
    println!("{}", "  ██║╚██╗██║██║   ██║██║   ██║".bright_white());
    println!("{}", "  ██║ ╚████║╚██████╔╝╚██████╔╝".bright_white());
    println!("{}", "  ╚═╝  ╚═══╝ ╚═════╝  ╚═════╝ ".dimmed());
    println!();
    println!(
        "  {} {}",
        "Local AI Server".bold(),
        "v0.1.0 (Linux/Windows α)".dimmed()
    );
    println!();
    println!("  {} http://localhost:{}", "Dashboard:".green().bold(), port);
    println!(
        "  {} http://localhost:{}/v1",
        "API Base: ".blue().bold(),
        port
    );
    println!("  {} {}", "Ollama:   ".yellow().bold(), ollama_base);
    println!("  {} {}", "Model:    ".cyan().bold(), model);
    println!();
    println!(
        "  {}",
        "── Connect Claude Code ──────────────────────".dimmed()
    );
    println!(
        "  ANTHROPIC_BASE_URL={}",
        format!("http://localhost:{}", port).green()
    );
    println!("  ANTHROPIC_API_KEY=sk-dummy");
    println!();
    println!(
        "  {}",
        "── Install a model (if needed) ──────────────".dimmed()
    );
    println!("  ollama pull {}", model.yellow());
    println!();
}

// ─── Main ───────────────────────────────────────────────────────

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    tracing_subscriber::fmt()
        .with_env_filter(std::env::var("RUST_LOG").unwrap_or_else(|_| "warn".to_string()))
        .init();

    print_banner(cli.port, &cli.ollama, &cli.model);

    let client = Client::builder()
        .timeout(Duration::from_secs(300))
        .build()
        .expect("HTTP client");

    let state = Arc::new(AppState {
        client,
        ollama_base: cli.ollama.clone(),
        default_model: cli.model.clone(),
    });

    // CORS
    let cors = tower_http::cors::CorsLayer::new()
        .allow_origin(tower_http::cors::Any)
        .allow_methods(tower_http::cors::Any)
        .allow_headers(tower_http::cors::Any);

    let app = Router::new()
        .route("/", get(dashboard))
        .route("/health", get(health))
        .route("/api/status", get(api_status))
        .route("/v1/models", get(list_models))
        .route("/v1/*path", any(proxy_handler))
        .layer(cors)
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], cli.port));
    let listener = TcpListener::bind(addr).await.expect("bind port");

    // Check ollama in background
    let ollama_base = cli.ollama.clone();
    tokio::spawn(async move {
        let c = Client::new();
        match c
            .get(format!("{}/api/version", ollama_base))
            .timeout(Duration::from_secs(3))
            .send()
            .await
        {
            Ok(_) => println!("  {} Ollama connected", "✓".green()),
            Err(_) => {
                println!("  {} Ollama not found. Install with:", "⚠".yellow());
                println!();
                println!("    {} https://ollama.com/download", "→".dimmed());
                println!("    ollama serve");
                println!("    ollama pull gemma3:4b");
                println!();
            }
        }
    });

    println!(
        "  {} Listening on port {}\n",
        "→".green(),
        cli.port.to_string().bold()
    );

    axum::serve(listener, app).await.unwrap();
}
