enum DashboardHTML {
    static let content = #"""
    <!DOCTYPE html>
    <html lang="ja">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>NOU Dashboard</title>
    <style>
    :root{--bg:#0d1117;--card:#161b22;--border:#30363d;--text:#e6edf3;--muted:#8b949e;--green:#3fb950;--red:#f85149;--blue:#58a6ff;--yellow:#d29922;--purple:#bc8cff}
    *{box-sizing:border-box;margin:0;padding:0}
    body{background:var(--bg);color:var(--text);font-family:-apple-system,sans-serif;padding:24px;max-width:960px;margin:0 auto}
    h1{font-size:24px;font-weight:700;margin-bottom:4px;display:flex;align-items:center;gap:10px}
    .subtitle{color:var(--muted);font-size:13px;margin-bottom:24px}
    h2{font-size:12px;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.08em;margin-bottom:12px}
    .section{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:16px;margin-bottom:16px}
    .grid2{display:grid;grid-template-columns:1fr 1fr;gap:16px}
    .model-row{display:flex;align-items:center;justify-content:space-between;padding:8px 0;border-bottom:1px solid var(--border)}
    .model-row:last-child{border-bottom:none}
    .dot{width:8px;height:8px;border-radius:50%;display:inline-block;margin-right:8px;flex-shrink:0}
    .dot.on{background:var(--green)}
    .dot.off{background:var(--red)}
    .dot.pulse{animation:pulse 2s infinite}
    @keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
    .model-name{font-weight:600;font-size:14px}
    .model-meta{font-size:11px;color:var(--muted);margin-top:2px}
    .badge{font-size:11px;padding:2px 8px;border-radius:12px;font-weight:500}
    .badge-green{background:#1a4228;color:var(--green)}
    .badge-red{background:#3d1a1a;color:var(--red)}
    .badge-blue{background:#1a2a3d;color:var(--blue)}
    .code{background:#0d1117;border:1px solid var(--border);border-radius:6px;padding:12px;font-family:monospace;font-size:12px;white-space:pre-wrap;word-break:break-all;position:relative;margin-bottom:8px;line-height:1.6}
    .copy-btn{position:absolute;top:8px;right:8px;background:var(--border);border:none;color:var(--text);border-radius:4px;padding:4px 10px;font-size:11px;cursor:pointer}
    .copy-btn:hover{background:var(--blue);color:#fff}
    .stat-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:4px}
    .stat-box{background:#0d1117;border:1px solid var(--border);border-radius:6px;padding:12px;text-align:center}
    .stat-val{font-size:22px;font-weight:700;color:var(--blue)}
    .stat-label{font-size:11px;color:var(--muted);margin-top:4px}
    .status-footer{font-size:11px;color:var(--muted);margin-top:12px}
    .tok-bar{height:4px;background:var(--border);border-radius:2px;overflow:hidden;margin-top:6px}
    .tok-fill{height:100%;background:var(--blue);transition:width .5s;border-radius:2px}
    .idle-badge{font-size:11px;padding:2px 8px;border-radius:12px;display:inline-block}
    .idle-active{background:#1a3a1a;color:#3fb950}
    .idle-earning{background:#3a2a00;color:#d29922}
    .idle-off{background:#1a1a2a;color:#8b949e}
    </style>
    </head>
    <body>
    <h1>🧠 NOU</h1>
    <p class="subtitle">Local AI Inference — Apple Silicon</p>

    <!-- 統計 -->
    <div class="section">
      <h2>リアルタイム統計</h2>
      <div class="stat-grid">
        <div class="stat-box">
          <div class="stat-val" id="stat-tps">—</div>
          <div class="stat-label">tok / sec</div>
          <div class="tok-bar"><div class="tok-fill" id="tps-bar" style="width:0%"></div></div>
        </div>
        <div class="stat-box">
          <div class="stat-val" id="stat-reqs">0</div>
          <div class="stat-label">total requests</div>
        </div>
        <div class="stat-box">
          <div class="stat-val" id="stat-depin">0</div>
          <div class="stat-label">DePIN requests</div>
        </div>
        <div class="stat-box">
          <div class="stat-val" id="stat-uptime">—</div>
          <div class="stat-label">uptime</div>
        </div>
      </div>
      <div class="status-footer">
        <span id="idle-status"></span>
        <span style="margin-left:12px" id="last-update"></span>
      </div>
    </div>

    <!-- モデル状態 -->
    <div class="section">
      <h2>モデル状態</h2>
      <div id="models-list"><div style="color:var(--muted);padding:8px">読み込み中...</div></div>
    </div>

    <!-- ベンチマーク -->
    <div class="section">
      <h2>ランタイムベンチマーク</h2>
      <div style="display:flex;align-items:center;gap:12px;margin-bottom:12px">
        <button id="bench-btn" onclick="runBenchmark()" style="background:var(--blue);border:none;color:#fff;border-radius:6px;padding:8px 16px;font-size:13px;cursor:pointer;font-weight:600">
          \u25B6 ベンチマーク実行
        </button>
        <span id="bench-status" style="font-size:12px;color:var(--muted)"></span>
      </div>
      <div id="bench-results" style="display:none">
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
          <div class="stat-box" id="bench-mlx">
            <div style="font-size:11px;color:var(--purple);font-weight:600;margin-bottom:4px">MLX</div>
            <div class="stat-val" id="bench-mlx-tps">\u2014</div>
            <div class="stat-label">tok/s gen</div>
          </div>
          <div class="stat-box" id="bench-lcpp">
            <div style="font-size:11px;color:var(--blue);font-weight:600;margin-bottom:4px">llama.cpp</div>
            <div class="stat-val" id="bench-lcpp-tps">\u2014</div>
            <div class="stat-label">tok/s gen</div>
          </div>
        </div>
        <div id="bench-winner" style="text-align:center;margin-top:12px;font-size:13px;font-weight:600"></div>
      </div>
    </div>

    <!-- 接続情報 -->
    <div class="grid2">
      <div class="section">
        <h2>Claude Code (ローカル)</h2>
        <div class="code" id="claude-code-snippet">読み込み中...
          <button class="copy-btn" onclick="copyEl('claude-code-snippet')">コピー</button>
        </div>
      </div>
      <div class="section">
        <h2>Aider / OpenAI 互換</h2>
        <div class="code" id="aider-snippet">読み込み中...
          <button class="copy-btn" onclick="copyEl('aider-snippet')">コピー</button>
        </div>
      </div>
    </div>

    <!-- Smart Routing -->
    <div class="section">
      <h2>Smart Routing (auto)</h2>
      <p style="font-size:12px;color:var(--muted);margin-bottom:8px">
        model名に <code style="color:var(--blue)">auto</code>, <code style="color:var(--blue)">nou</code>, <code style="color:var(--blue)">smart</code> を指定すると、プロンプトの複雑さに応じて自動的に最適なモデルにルーティングされます。
      </p>
      <div class="code" id="smart-snippet">OPENAI_API_BASE=http://${IP}:4001/v1 OPENAI_API_KEY=sk-dummy aider --model openai/auto<button class="copy-btn" onclick="copyEl('smart-snippet')">コピー</button></div>
      <p style="font-size:11px;color:var(--muted)">simple -> fast slot / medium,complex -> main slot</p>
    </div>

    <!-- Zero-config Proxy -->
    <div class="section">
      <h2>ゼロコンフィグ プロキシ</h2>
      <p style="font-size:12px;color:var(--muted);margin-bottom:8px">
        macOS設定 &rarr; Wi-Fi &rarr; 詳細 &rarr; プロキシ &rarr; 自動プロキシ構成にチェック &rarr; URL:
      </p>
      <div class="code" id="pac-url">http://localhost:4001/proxy.pac<button class="copy-btn" onclick="copyEl('pac-url')">コピー</button></div>
      <p style="font-size:11px;color:var(--muted)">
        設定後、OpenAI/Anthropic/Gemini APIへのリクエストが自動的にNOU経由になります。
      </p>
    </div>

    <!-- 推奨モデル -->
    <div class="section">
      <h2>推奨モデル (mlx-community)</h2>
      <div id="recommended-models">
        <div class="model-row">
          <div><div class="model-name">Qwen3.5-122B-A10B-4bit</div><div class="model-meta">mlx-community/Qwen3.5-122B-A10B-4bit · MoE 122B (active 10B)</div></div>
          <span class="badge badge-blue">~60GB</span>
        </div>
        <div class="model-row">
          <div><div class="model-name">Qwen3.5-35B-A3B-4bit</div><div class="model-meta">mlx-community/Qwen3.5-35B-A3B-4bit · MoE 35B (active 3B)</div></div>
          <span class="badge badge-blue">~8GB</span>
        </div>
        <div class="model-row">
          <div><div class="model-name">Qwen3.5-9B-4bit</div><div class="model-meta">mlx-community/Qwen3.5-9B-4bit</div></div>
          <span class="badge badge-blue">~5GB</span>
        </div>
        <div class="model-row">
          <div><div class="model-name">Qwen3-VL-8B-4bit</div><div class="model-meta">mlx-community/Qwen3-VL-8B-Instruct-4bit · Vision</div></div>
          <span class="badge badge-blue">~5GB</span>
        </div>
      </div>
    </div>

    <!-- Network Nodes -->
    <div class="section">
      <h2>ネットワークノード</h2>
      <div id="network-nodes"><div style="color:var(--muted);padding:8px;font-size:12px">Searching...</div></div>
    </div>

    <!-- P2P Model Library -->
    <div class="section">
      <h2>Model Library (P2P)</h2>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px">
        <div>
          <h2 style="margin-bottom:8px">Local Models</h2>
          <div id="local-models"><div style="color:var(--muted);padding:8px;font-size:12px">Scanning...</div></div>
        </div>
        <div>
          <h2 style="margin-bottom:8px">Network Models</h2>
          <div id="network-models"><div style="color:var(--muted);padding:8px;font-size:12px">Searching nodes...</div></div>
        </div>
      </div>
    </div>

    <script>
    const BASE = window.location.origin;
    const IP = window.location.hostname;
    let maxTps = 10;

    function fmtUptime(s) {
      if (s < 60) return s + 's';
      if (s < 3600) return Math.floor(s/60) + 'm';
      return Math.floor(s/3600) + 'h ' + Math.floor((s%3600)/60) + 'm';
    }

    async function refresh() {
      try {
        const [health, models, stats] = await Promise.all([
          fetch(BASE+'/health').then(r=>r.json()).catch(()=>({})),
          fetch(BASE+'/api/models').then(r=>r.json()).catch(()=>[]),
          fetch(BASE+'/api/stats').then(r=>r.json()).catch(()=>({}))
        ]);

        // 統計更新
        const tps = parseFloat(stats.tok_per_sec||'0');
        document.getElementById('stat-tps').textContent = tps.toFixed(1);
        document.getElementById('stat-reqs').textContent = stats.total_requests||0;
        document.getElementById('stat-depin').textContent = stats.depin_requests||0;
        document.getElementById('stat-uptime').textContent = fmtUptime(stats.uptime_seconds||0);
        if (tps > maxTps) maxTps = tps;
        document.getElementById('tps-bar').style.width = Math.min(100, (tps/maxTps)*100) + '%';

        // モデル状態
        const list = document.getElementById('models-list');
        const modelDefs = [
          {key:'main',  name:'LLM 122B', sub:'Qwen3.5-122B-A10B-4bit · :5000', ram:'~60GB'},
          {key:'fast',  name:'LLM 35B',  sub:'Qwen3.5-35B-A3B-4bit  · :5001',  ram:'~8GB'},
          {key:'vision',name:'Vision',   sub:'Qwen3-VL-8B-4bit       · :5002',  ram:'~5GB'},
          {key:'proxy', name:'Proxy',    sub:'NOU proxy            · :4001',  ram:''},
        ];
        const modelsHealth = health.models || {};
        const proxyOk = modelsHealth.proxy !== false;
        const allRows = [...(models||[]), {name:'proxy',label:'Proxy',running:proxyOk,runtime:'\u2014',port:4001,model:'NOU proxy'}];
        list.innerHTML = allRows.map(m => {
          const alive = m.running === true;
          const rt = m.runtime || '\u2014';
          const rtBadge = rt === 'llamacpp' ? '<span class="badge" style="background:#1a2a3d;color:var(--blue);margin-right:4px">llama.cpp</span>'
                        : rt === 'mlx' ? '<span class="badge" style="background:#2a1a3d;color:var(--purple);margin-right:4px">MLX</span>'
                        : '';
          const toggleBtn = (m.name === 'main' || m.name === 'fast') && rt !== '\u2014'
            ? `<button onclick="toggleRuntime('${m.name}','${rt}')" style="background:var(--border);border:none;color:var(--text);border-radius:4px;padding:2px 8px;font-size:10px;cursor:pointer;margin-left:4px">\u21C4</button>`
            : '';
          return `<div class="model-row">
            <div style="display:flex;align-items:center">
              <span class="dot ${alive?'on pulse':'off'}"></span>
              <div>
                <div class="model-name">${m.label || m.name}</div>
                <div class="model-meta" style="font-family:monospace">:${m.port} \u00B7 ${m.model || ''}</div>
              </div>
            </div>
            <div style="display:flex;align-items:center;gap:4px">
              ${rtBadge}${toggleBtn}
              <span class="badge ${alive?'badge-green':'badge-red'}">${alive?'running':'stopped'}</span>
            </div>
          </div>`;
        }).join('');

        // 接続スニペット
        document.getElementById('claude-code-snippet').innerHTML =
          `export ANTHROPIC_BASE_URL=http://${IP}:4001\nexport ANTHROPIC_API_KEY=sk-ant-dummy\nclaude --dangerously-skip-permissions` +
          `\n<button class="copy-btn" onclick="copyEl('claude-code-snippet')">コピー</button>`;
        document.getElementById('aider-snippet').innerHTML =
          `OPENAI_API_BASE=http://${IP}:4001/v1 \\\nOPENAI_API_KEY=sk-dummy \\\naider --model openai/qwen3.5-122b` +
          `\n<button class="copy-btn" onclick="copyEl('aider-snippet')">コピー</button>`;

        // アイドル状態（ioreg 経由ではなく stats から推測 — 将来拡張）
        const depinEl = document.getElementById('idle-status');
        if (stats.depin_requests > 0) {
          depinEl.innerHTML = '<span class="idle-badge idle-earning">💰 DePIN稼働中</span>';
        } else if (proxyOk) {
          depinEl.innerHTML = '<span class="idle-badge idle-active">🟢 ローカル稼働中</span>';
        } else {
          depinEl.innerHTML = '<span class="idle-badge idle-off">💤 停止中</span>';
        }

        document.getElementById('last-update').textContent = '更新: ' + new Date().toLocaleTimeString();
      } catch(e) {
        console.error(e);
      }
    }

    function copyEl(id) {
      const el = document.getElementById(id);
      const text = el.innerText.replace(/コピー$/, '').trim();
      navigator.clipboard.writeText(text).then(() => {
        const btn = el.querySelector('.copy-btn');
        btn.textContent = '✓'; setTimeout(() => btn.textContent = 'コピー', 1500);
      });
    }

    async function runBenchmark() {
      const btn = document.getElementById('bench-btn');
      const status = document.getElementById('bench-status');
      const results = document.getElementById('bench-results');
      btn.disabled = true;
      btn.textContent = '\u23F3 \u5B9F\u884C\u4E2D...';
      status.textContent = 'MLX\u3068llama.cpp\u3092\u6BD4\u8F03\u4E2D (\u7D0430\u79D2)...';
      try {
        const r = await fetch(BASE+'/api/benchmark',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({slot:'main'})});
        const d = await r.json();
        results.style.display = 'block';
        document.getElementById('bench-mlx-tps').textContent = d.mlx.ok ? d.mlx.gen_tps.toFixed(1) : '\u2014';
        document.getElementById('bench-lcpp-tps').textContent = d.llamacpp.ok ? d.llamacpp.gen_tps.toFixed(1) : '\u2014';
        document.getElementById('bench-mlx-tps').style.color = d.winner==='mlx' ? 'var(--green)' : 'var(--muted)';
        document.getElementById('bench-lcpp-tps').style.color = d.winner==='llamacpp' ? 'var(--green)' : 'var(--muted)';
        const winLabel = d.winner === 'llamacpp' ? 'llama.cpp' : 'MLX';
        document.getElementById('bench-winner').innerHTML = '\u2705 ' + winLabel + ' \u3092\u30C7\u30D5\u30A9\u30EB\u30C8\u306B\u8A2D\u5B9A\u3057\u307E\u3057\u305F';
        status.textContent = '';
        refresh();
      } catch(e) {
        status.textContent = '\u30A8\u30E9\u30FC: ' + e.message;
      }
      btn.disabled = false;
      btn.textContent = '\u25B6 \u30D9\u30F3\u30C1\u30DE\u30FC\u30AF\u5B9F\u884C';
    }
    async function toggleRuntime(slot, current) {
      const next = current === 'mlx' ? 'llamacpp' : 'mlx';
      if(!confirm('Switch ' + slot + ' runtime to ' + next + '?')) return;
      await fetch(BASE+'/api/runtime',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({slot,runtime:next})});
      refresh();
    }
    function fmtSize(bytes) {
      if (bytes >= 1073741824) return (bytes/1073741824).toFixed(1) + ' GB';
      if (bytes >= 1048576) return (bytes/1048576).toFixed(0) + ' MB';
      return (bytes/1024).toFixed(0) + ' KB';
    }

    async function refreshModelLibrary() {
      try {
        // Local models
        const local = await fetch(BASE+'/api/models/available').then(r=>r.json()).catch(()=>[]);
        const localEl = document.getElementById('local-models');
        if (local.length === 0) {
          localEl.innerHTML = '<div style="color:var(--muted);padding:8px;font-size:12px">No local models found</div>';
        } else {
          localEl.innerHTML = local.map(m => `<div class="model-row">
            <div><div class="model-name" style="font-size:13px">${m.name}</div>
            <div class="model-meta">${m.type}</div></div>
            <span class="badge badge-blue">${fmtSize(m.size)}</span>
          </div>`).join('');
        }

        // Network models: query discovered nodes via /health first, then /api/models/available
        const networkEl = document.getElementById('network-models');
        // Try known LAN peers (from the nodes list we can discover)
        const nodesResp = await fetch(BASE+'/api/models').then(r=>r.json()).catch(()=>[]);
        // For now, show a hint about P2P
        let networkHtml = '';
        const localNames = new Set(local.map(m=>m.name));
        // Check if we have any peer info (this would come from the browser in a full impl)
        networkHtml = local.length > 0
          ? '<div style="color:var(--muted);padding:8px;font-size:12px">Your models are available to other NOU nodes on this network via the menubar "Get Models from Network" option.</div>'
          : '<div style="color:var(--muted);padding:8px;font-size:12px">No peers discovered yet. Add nodes via the menubar.</div>';
        networkEl.innerHTML = networkHtml;
      } catch(e) {
        console.error('Model library error:', e);
      }
    }

    async function refreshNodes() {
      try {
        const nodes = await fetch(BASE+'/api/nodes').then(r=>r.json()).catch(()=>[]);
        const el = document.getElementById('network-nodes');
        if (nodes.length === 0) {
          el.innerHTML = '<div style="color:var(--muted);padding:8px;font-size:12px">No remote nodes discovered</div>';
          return;
        }
        el.innerHTML = nodes.map(n => {
          const dot = n.healthy ? '<span class="dot on pulse"></span>' : '<span class="dot off"></span>';
          const models = (n.models||[]).map(s => {
            const rd = s.running ? '●' : '○';
            const rt = s.runtime === 'llamacpp' ? '⚡' : '🍎';
            return `<span style="margin-left:8px;font-size:11px;color:var(--muted)">${rd} ${s.name}: ${s.label} ${rt}</span>`;
          }).join('');
          const pairIcon = n.paired ? '🔐' : '🔓';
          const rpcTag = n.rpcAvailable ? ' <span class="badge badge-blue" style="font-size:9px">RPC</span>' : '';
          return `<div class="model-row">
            <div style="display:flex;align-items:center">
              ${dot}
              <div>
                <div class="model-name">${n.tierIcon} ${n.name} ${pairIcon}${rpcTag}</div>
                <div class="model-meta">${n.memoryGB}GB · ${n.tier}${models}</div>
              </div>
            </div>
            <div style="display:flex;align-items:center;gap:4px">
              <a href="${n.url}" target="_blank" class="badge badge-blue" style="text-decoration:none;cursor:pointer">Dashboard</a>
              <span class="badge ${n.healthy?'badge-green':'badge-red'}">${n.healthy?'online':'offline'}</span>
            </div>
          </div>`;
        }).join('');
      } catch(e) { console.error('Nodes error:', e); }
    }

    refresh();
    setInterval(refresh, 5000);
    refreshNodes();
    setInterval(refreshNodes, 10000);
    refreshModelLibrary();
    setInterval(refreshModelLibrary, 30000);
    </script>
    </body>
    </html>
    """#
}
