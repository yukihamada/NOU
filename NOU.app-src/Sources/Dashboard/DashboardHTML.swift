enum DashboardHTML {
    static let content = #"""
    <!DOCTYPE html>
    <html lang="ja">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>NOU Dashboard</title>
    <style>
    :root{--bg:#0d1117;--card:#161b22;--border:#30363d;--text:#e6edf3;--muted:#8b949e;--green:#3fb950;--red:#f85149;--blue:#58a6ff;--yellow:#d29922;--purple:#bc8cff;--orange:#f0883e}
    *{box-sizing:border-box;margin:0;padding:0}
    body{background:var(--bg);color:var(--text);font-family:-apple-system,sans-serif;padding:24px;max-width:1040px;margin:0 auto}
    h1{font-size:22px;font-weight:700;margin-bottom:4px;display:flex;align-items:center;gap:10px}
    .subtitle{color:var(--muted);font-size:12px;margin-bottom:20px}
    h2{font-size:11px;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.08em;margin-bottom:12px}
    .section{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:16px;margin-bottom:14px}
    .grid2{display:grid;grid-template-columns:1fr 1fr;gap:14px}
    .grid3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:14px}
    .model-row{display:flex;align-items:center;justify-content:space-between;padding:8px 0;border-bottom:1px solid var(--border)}
    .model-row:last-child{border-bottom:none}
    .dot{width:7px;height:7px;border-radius:50%;display:inline-block;margin-right:8px;flex-shrink:0}
    .dot.on{background:var(--green)}.dot.off{background:var(--red)}
    .dot.pulse{animation:pulse 2s infinite}
    @keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
    .model-name{font-weight:600;font-size:13px}
    .model-meta{font-size:11px;color:var(--muted);margin-top:2px;font-family:monospace}
    .badge{font-size:10px;padding:2px 7px;border-radius:10px;font-weight:500;white-space:nowrap}
    .badge-green{background:#1a4228;color:var(--green)}
    .badge-red{background:#3d1a1a;color:var(--red)}
    .badge-blue{background:#1a2a3d;color:var(--blue)}
    .badge-purple{background:#2a1a3d;color:var(--purple)}
    .badge-orange{background:#3d2a1a;color:var(--orange)}
    .code{background:#0d1117;border:1px solid var(--border);border-radius:6px;padding:10px;font-family:monospace;font-size:11px;white-space:pre-wrap;word-break:break-all;position:relative;margin-bottom:8px;line-height:1.6}
    .copy-btn{position:absolute;top:6px;right:6px;background:var(--border);border:none;color:var(--text);border-radius:4px;padding:3px 8px;font-size:10px;cursor:pointer}
    .copy-btn:hover{background:var(--blue);color:#fff}
    .stat-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:4px}
    .stat-box{background:#0d1117;border:1px solid var(--border);border-radius:6px;padding:10px;text-align:center}
    .stat-val{font-size:20px;font-weight:700;color:var(--blue)}
    .stat-label{font-size:10px;color:var(--muted);margin-top:3px}
    .status-footer{font-size:11px;color:var(--muted);margin-top:10px;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:6px}
    .bar-wrap{height:4px;background:var(--border);border-radius:2px;overflow:hidden;margin-top:5px}
    .bar-fill{height:100%;border-radius:2px;transition:width .5s}
    .bar-blue{background:var(--blue)}.bar-green{background:var(--green)}.bar-orange{background:var(--orange)}.bar-red{background:var(--red)}
    .idle-badge{font-size:10px;padding:2px 7px;border-radius:10px;display:inline-block}
    .idle-active{background:#1a3a1a;color:#3fb950}.idle-earning{background:#3a2a00;color:#d29922}.idle-off{background:#1a1a2a;color:#8b949e}
    .btn{border:none;border-radius:5px;padding:6px 14px;font-size:12px;cursor:pointer;font-weight:600;transition:opacity .15s}
    .btn:hover{opacity:.8}.btn:disabled{opacity:.4;cursor:not-allowed}
    .btn-blue{background:var(--blue);color:#fff}.btn-green{background:var(--green);color:#000}
    .btn-muted{background:var(--border);color:var(--text)}
    input[type=text]{background:#0d1117;border:1px solid var(--border);border-radius:5px;padding:5px 10px;color:var(--text);font-size:12px;outline:none}
    input[type=text]:focus{border-color:var(--blue)}
    .mem-bar-wrap{margin-top:6px}
    .mem-label{font-size:10px;color:var(--muted);display:flex;justify-content:space-between;margin-bottom:3px}
    .node-card{border:1px solid var(--border);border-radius:6px;padding:12px;margin-bottom:8px;background:#0d1117}
    .node-card:last-child{margin-bottom:0}
    .node-header{display:flex;align-items:center;justify-content:space-between;margin-bottom:8px}
    .node-name{font-weight:700;font-size:13px;display:flex;align-items:center;gap:6px}
    .node-models{display:flex;flex-wrap:wrap;gap:5px;margin-top:4px}
    .bb-row{display:flex;justify-content:space-between;align-items:flex-start;padding:8px 0;border-bottom:1px solid var(--border);gap:12px}
    .bb-row:last-child{border-bottom:none}
    .bb-key{font-family:monospace;font-size:12px;color:var(--blue);font-weight:600;min-width:120px}
    .bb-val{font-size:12px;flex:1;word-break:break-word;color:var(--text)}
    .bb-meta{font-size:10px;color:var(--muted);white-space:nowrap}
    .tabs{display:flex;gap:2px;border-bottom:1px solid var(--border);margin-bottom:14px}
    .tab{padding:6px 14px;border-radius:4px 4px 0 0;font-size:12px;cursor:pointer;color:var(--muted);background:none;border:none;font-weight:500}
    .tab.active{color:var(--text);background:var(--card);border:1px solid var(--border);border-bottom-color:var(--card)}
    .hidden{display:none}
    </style>
    </head>
    <body>
    <h1>🧠 NOU</h1>
    <p class="subtitle">Local AI Inference — Apple Silicon · <span id="node-name">...</span></p>

    <!-- === 初回セットアップバナー === -->
    <div id="setup-banner" style="display:none;background:linear-gradient(135deg,#0d1f35,#0d1a2a);border:1px solid #1e3a5f;border-radius:12px;padding:20px 24px;margin-bottom:16px">
      <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:12px">
        <div>
          <div style="font-size:16px;font-weight:700;margin-bottom:4px">🚀 NOUへようこそ！</div>
          <div style="font-size:12px;color:#8ab4d8">最初にAIモデルをダウンロードして使い始めましょう。</div>
        </div>
        <a href="/start" style="font-size:12px;color:#58a6ff;border:1px solid #1e3a5f;border-radius:6px;padding:6px 14px;text-decoration:none">セットアップガイド →</a>
      </div>
      <div id="setup-steps" style="margin-top:16px;display:flex;gap:12px;flex-wrap:wrap">
        <!-- Steps injected by JS -->
      </div>
      <div id="setup-recommendation" style="margin-top:14px;background:#0a1a2a;border-radius:8px;padding:14px"></div>
    </div>

    <!-- === リアルタイム統計 === -->
    <div class="section">
      <h2>リアルタイム統計</h2>
      <div class="stat-grid">
        <div class="stat-box">
          <div class="stat-val" id="stat-tps">—</div>
          <div class="stat-label">tok / sec</div>
          <div class="bar-wrap"><div class="bar-fill bar-blue" id="tps-bar" style="width:0%"></div></div>
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
        <span id="last-update" style="color:var(--muted);font-size:10px"></span>
      </div>
    </div>

    <!-- === メモリ / CPU / GPU === -->
    <div class="section">
      <h2>メモリ・リソース</h2>
      <div class="grid3">
        <div>
          <div class="mem-label"><span>RAM</span><span id="ram-label">—</span></div>
          <div class="bar-wrap"><div class="bar-fill bar-blue" id="ram-bar" style="width:0%"></div></div>
        </div>
        <div>
          <div class="mem-label"><span>GPU (推定)</span><span id="gpu-label">—</span></div>
          <div class="bar-wrap"><div class="bar-fill bar-purple" id="gpu-bar" style="width:0%"></div></div>
        </div>
        <div>
          <div class="mem-label"><span>CPU</span><span id="cpu-label">—</span></div>
          <div class="bar-wrap"><div class="bar-fill bar-orange" id="cpu-bar" style="width:0%"></div></div>
        </div>
      </div>
      <div style="font-size:10px;color:var(--muted);margin-top:8px">Apple Silicon: ユニファイドメモリ。GPUはシステムRAMを共有。</div>
    </div>

    <!-- === モデル状態 === -->
    <div class="section">
      <h2>モデル状態</h2>
      <div id="models-list"><div style="color:var(--muted);padding:8px;font-size:12px">読み込み中...</div></div>
    </div>

    <!-- === ネットワークノード (mesh-llm相当) === -->
    <div class="section">
      <h2>メッシュネットワーク</h2>
      <div id="network-nodes"><div style="color:var(--muted);padding:8px;font-size:12px">Searching...</div></div>
      <div style="margin-top:12px;display:flex;gap:8px;flex-wrap:wrap;align-items:center">
        <input type="text" id="wan-url-input" placeholder="http://192.168.x.x:4001  または tunnel URL" style="width:280px">
        <button class="btn btn-muted" onclick="addWANNode()">+ ノードを追加</button>
        <span id="add-node-status" style="font-size:11px;color:var(--muted)"></span>
      </div>
      <div style="font-size:10px;color:var(--muted);margin-top:6px">LAN外のノードはCloudflare Tunnel URLも指定可。ペアリング後は自動でRPCワーカーに追加されます。</div>
    </div>

    <!-- === 分散推論 (llama.cpp RPC) === -->
    <div class="section">
      <h2>⚡ 分散推論</h2>

      <!-- コンセプト説明 -->
      <div style="background:#0d1117;border:1px solid var(--border);border-radius:8px;padding:16px;margin-bottom:16px">
        <div style="font-size:13px;font-weight:600;margin-bottom:8px;color:var(--text)">これは何？</div>
        <p style="font-size:12px;color:var(--muted);margin:0 0 12px 0;line-height:1.7">
          1台のMacに収まらない巨大なAIモデルを、<b style="color:var(--text)">複数のMacのGPUメモリを合わせて</b>動かす仕組みです。<br>
          モデルの「層 (レイヤー)」を各Macに分担させ、ネットワーク経由で連携します。
        </p>
        <!-- 仕組み図 -->
        <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;font-size:11px">
          <div style="background:#1a2a3d;border:1px solid #2a4060;border-radius:6px;padding:8px 12px;text-align:center">
            <div style="font-size:16px">💻</div>
            <div style="color:var(--blue);font-weight:600">このMac</div>
            <div style="color:var(--muted)">コーディネーター</div>
            <div style="color:var(--muted)">層 1〜40</div>
          </div>
          <div style="color:var(--muted);font-size:18px">⟷</div>
          <div style="background:#1a2a1a;border:1px solid #2a4030;border-radius:6px;padding:8px 12px;text-align:center">
            <div style="font-size:16px">🖥️</div>
            <div style="color:var(--green);font-weight:600">ワーカーMac</div>
            <div style="color:var(--muted)">GPUを提供</div>
            <div style="color:var(--muted)">層 41〜80</div>
          </div>
          <div style="color:var(--muted);font-size:14px;margin-left:4px">→</div>
          <div style="background:#1a1a2a;border:1px solid #2a2a40;border-radius:6px;padding:8px 12px;text-align:center">
            <div style="font-size:16px">🤖</div>
            <div style="color:var(--purple,#a78bfa);font-weight:600">70Bモデル</div>
            <div style="color:var(--muted)">合計VRAM: 80GB</div>
            <div style="color:var(--muted)">→ 動作！</div>
          </div>
        </div>
        <div style="margin-top:12px;padding:8px 10px;background:#111;border-radius:4px;border-left:3px solid var(--blue)">
          <div style="font-size:11px;color:var(--muted)">
            <b style="color:var(--text)">具体例:</b> MacBook Air (16GB) + M5 Max (128GB) = 合計144GB → Llama3 70B (42GB) が余裕で動く
          </div>
        </div>
      </div>

      <!-- 現在の状態 -->
      <div id="rpc-status" style="margin-bottom:14px"><div style="color:var(--muted);font-size:12px">読み込み中...</div></div>

      <!-- セットアップステップ -->
      <div style="border:1px solid var(--border);border-radius:6px;overflow:hidden;margin-bottom:12px">
        <div style="background:#0d1117;padding:10px 14px;border-bottom:1px solid var(--border)">
          <span style="font-size:11px;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.06em">接続手順</span>
        </div>

        <div style="padding:14px">
          <!-- Step 1 -->
          <div style="display:flex;gap:12px;margin-bottom:14px;align-items:flex-start">
            <div style="background:#1a2a3d;color:var(--blue);border-radius:50%;width:22px;height:22px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;flex-shrink:0;margin-top:1px">1</div>
            <div style="flex:1">
              <div style="font-size:12px;font-weight:600;margin-bottom:2px">ワーカーMac に llama.cpp をインストール</div>
              <div style="font-size:11px;color:var(--muted);margin-bottom:6px">GPUを提供したい側のMacで一度だけ実行:</div>
              <div class="code" id="install-rpc-cmd">brew install llama.cpp<button class="copy-btn" onclick="copyEl('install-rpc-cmd')">コピー</button></div>
            </div>
          </div>

          <!-- Step 2 -->
          <div style="display:flex;gap:12px;margin-bottom:14px;align-items:flex-start">
            <div style="background:#1a2a3d;color:var(--blue);border-radius:50%;width:22px;height:22px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;flex-shrink:0;margin-top:1px">2</div>
            <div style="flex:1">
              <div style="font-size:12px;font-weight:600;margin-bottom:2px">ワーカーMac で RPC サーバーを起動</div>
              <div style="font-size:11px;color:var(--muted);margin-bottom:6px">「GPU を貸し出す」サーバープロセスを起動します:</div>
              <div class="code" id="start-rpc-cmd">llama-rpc-server --host 0.0.0.0 --port 50052<button class="copy-btn" onclick="copyEl('start-rpc-cmd')">コピー</button></div>
              <div style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap">
                <button class="btn btn-blue" onclick="rpcAction('start')" style="font-size:11px;padding:4px 10px">▶ このMacで起動</button>
                <button class="btn btn-muted" onclick="rpcAction('stop')" style="font-size:11px;padding:4px 10px">■ 停止</button>
              </div>
            </div>
          </div>

          <!-- Step 3 -->
          <div style="display:flex;gap:12px;margin-bottom:14px;align-items:flex-start">
            <div style="background:#1a2a3d;color:var(--blue);border-radius:50%;width:22px;height:22px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;flex-shrink:0;margin-top:1px">3</div>
            <div style="flex:1">
              <div style="font-size:12px;font-weight:600;margin-bottom:2px">ワーカーを登録</div>
              <div style="font-size:11px;color:var(--muted);margin-bottom:6px">メッシュで自動発見されたノードに <span class="badge badge-blue">RPC</span> バッジが出ます。または手動でIPを入力:</div>
              <div style="display:flex;gap:6px;flex-wrap:wrap">
                <input type="text" id="rpc-worker-host" placeholder="192.168.0.x" style="width:140px">
                <input type="text" id="rpc-worker-port" placeholder="50052" style="width:70px">
                <button class="btn btn-blue" onclick="addRPCWorkerManual()" style="font-size:11px;padding:4px 10px">追加</button>
                <button class="btn btn-muted" onclick="rpcRefresh()" style="font-size:11px;padding:4px 10px">↺ 確認</button>
              </div>
            </div>
          </div>

          <!-- Step 4 -->
          <div style="display:flex;gap:12px;align-items:flex-start">
            <div style="background:#1a3a1a;color:var(--green);border-radius:50%;width:22px;height:22px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;flex-shrink:0;margin-top:1px">4</div>
            <div style="flex:1">
              <div style="font-size:12px;font-weight:600;margin-bottom:2px">分散モードをオン → モデルを起動</div>
              <div style="font-size:11px;color:var(--muted);margin-bottom:6px">有効にするとモデル起動時に自動でワーカーのGPUにレイヤーを割り当てます:</div>
              <button class="btn btn-muted" id="rpc-enable-btn" onclick="rpcToggleEnable()" style="font-size:11px;padding:4px 10px">分散モード: 確認中...</button>
            </div>
          </div>
        </div>
      </div>

      <!-- 投機的デコード -->
      <div style="background:#0d1117;border:1px solid var(--border);border-radius:8px;padding:14px">
        <div style="display:flex;align-items:flex-start;gap:10px;margin-bottom:10px">
          <span style="font-size:20px">🚀</span>
          <div>
            <div style="font-size:13px;font-weight:600;margin-bottom:2px">投機的デコード (自動)</div>
            <div style="font-size:11px;color:var(--muted);line-height:1.6">
              小さなモデルが次のトークンを先読みし、大型モデルが並列で検証。
              小型モデルが存在する場合に自動で有効化されます。
            </div>
          </div>
        </div>
        <div id="speculative-auto-status" style="font-size:12px;color:var(--muted);padding:6px 10px;background:#111;border-radius:4px">
          状態: 確認中...
        </div>
      </div>
    </div>

    <!-- === DePIN === -->
    <div class="section">
      <h2>🌍 DePIN · GPU公開と報酬</h2>

      <!-- 大きなステータスカード -->
      <div id="depin-status-card" style="border-radius:10px;padding:20px;margin-bottom:16px;border:2px solid var(--border);background:#0d1117;transition:all .3s">
        <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:12px">
          <div>
            <div id="depin-status-title" style="font-size:16px;font-weight:700;margin-bottom:4px">⚫ DePIN — オフ</div>
            <div id="depin-status-sub" style="font-size:12px;color:var(--muted)">Cloudflare Tunnel を起動するとグローバル公開できます</div>
          </div>
          <div id="depin-tunnel-url" style="font-size:12px;color:var(--muted)"></div>
        </div>
      </div>

      <!-- 報酬統計 (即時表示) -->
      <div class="grid3" style="margin-bottom:16px">
        <div class="stat-box">
          <div class="stat-val" id="depin-stat-reqs" style="color:var(--blue)">…</div>
          <div class="stat-label">外部リクエスト数</div>
        </div>
        <div class="stat-box">
          <div class="stat-val" id="depin-stat-cu" style="color:var(--yellow)">…</div>
          <div class="stat-label">コンピュートユニット</div>
        </div>
        <div class="stat-box">
          <div class="stat-val" id="depin-stat-nou" style="color:var(--green)">…</div>
          <div class="stat-label" id="depin-reward-label">獲得報酬</div>
        </div>
      </div>

      <!-- モード選択 -->
      <div style="background:#0d1117;border:1px solid var(--border);border-radius:8px;padding:14px;margin-bottom:16px">
        <div style="font-size:11px;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.06em;margin-bottom:10px">報酬モード</div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:10px">
          <div id="mode-japan" onclick="setRewardMode('japan')" style="cursor:pointer;padding:10px 12px;border-radius:6px;border:2px solid var(--border);transition:all .15s">
            <div style="font-size:13px;font-weight:700;margin-bottom:2px">🇯🇵 NCH モード</div>
            <div style="font-size:10px;color:var(--muted);line-height:1.5">日本向け · バーター記録<br>現金化なし · 法的明確</div>
          </div>
          <div id="mode-global" onclick="setRewardMode('global')" style="cursor:pointer;padding:10px 12px;border-radius:6px;border:2px solid var(--border);transition:all .15s">
            <div style="font-size:13px;font-weight:700;margin-bottom:2px">🌍 NOU Token</div>
            <div style="font-size:10px;color:var(--muted);line-height:1.5">海外向け · Solana<br>DEX上場予定</div>
          </div>
        </div>
        <div id="wallet-section" style="display:none">
          <div style="font-size:11px;color:var(--muted);margin-bottom:6px">Solanaウォレット (Phantom / Backpack):</div>
          <div style="display:flex;gap:6px;flex-wrap:wrap">
            <input type="text" id="depin-wallet-input" placeholder="アドレスを貼り付け (例: 7xKX...)" style="flex:1;min-width:180px">
            <button class="btn btn-blue" onclick="depinSetWallet()" style="font-size:11px;padding:4px 10px">登録</button>
          </div>
          <div id="depin-wallet-current" style="margin-top:6px;font-size:11px;color:var(--muted)">未登録</div>
        </div>
        <div id="nch-info" style="display:none;font-size:11px;color:var(--muted);padding:6px 8px;background:#111;border-radius:4px;margin-top:8px">
          NCH (NOU Compute Hours) = 外部リクエスト処理量を記録するバータークレジット。将来 NOU サービス内でのGPU時間と交換できます。
        </div>
      </div>

      <!-- リレー接続 -->
      <div style="border:1px solid var(--border);border-radius:8px;overflow:hidden">
        <div style="background:#0d1117;padding:10px 14px;border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between">
          <span style="font-size:11px;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.06em">NOU リレー (独自インフラ)</span>
          <span style="font-size:10px;color:var(--green)">URL固定 · Cloudflare不要</span>
        </div>
        <div style="padding:14px">
          <div style="font-size:12px;color:var(--muted);margin-bottom:12px;line-height:1.7">
            NOUの独自リレーサーバーへWebSocketで接続します。URL固定・再起動してもURLは変わりません。
            あなたのAIのトラフィックはNOU以外を経由しません。
          </div>
          <div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:10px;align-items:center">
            <button class="btn btn-green" id="relay-connect-btn" onclick="relayConnect()" style="font-size:12px">
              🔗 リレーに接続
            </button>
            <button class="btn btn-muted" id="relay-disconnect-btn" onclick="relayDisconnect()" style="font-size:12px;display:none">
              ✕ 切断
            </button>
            <label style="display:flex;align-items:center;gap:6px;cursor:pointer;margin-left:4px" title="アプリ起動時に自動でリレーに接続します">
              <input type="checkbox" id="auto-relay-checkbox" onchange="setAutoRelay(this.checked)" style="cursor:pointer">
              <span style="font-size:11px;color:var(--muted)">起動時に自動接続</span>
            </label>
          </div>
          <div id="relay-url-display" style="display:none;padding:8px 10px;background:#111;border-radius:6px;border-left:3px solid var(--green)">
            <div style="font-size:10px;color:var(--muted);margin-bottom:3px">あなたの公開エンドポイント</div>
            <div id="relay-url-text" style="font-size:12px;font-weight:600;color:var(--blue);word-break:break-all"></div>
            <div style="font-size:10px;color:var(--muted);margin-top:4px">このURLをペアリング済みの相手と共有してください</div>
          </div>
        </div>
      </div>
    </div>

    <!-- === Blackboard (エージェント知識共有) === -->
    <div class="section" id="blackboard-section" style="display:none">
      <h2>📋 Blackboard — エージェント知識共有</h2>
      <p style="font-size:11px;color:var(--muted);margin-bottom:10px">
        ネットワーク上の全ノード・エージェントが読み書きできる共有メモ帳。<br>
        タスク状況・調査結果・ファイルパスを共有し、マルチエージェント協調に活用。
      </p>
      <div style="display:flex;gap:6px;margin-bottom:10px;flex-wrap:wrap">
        <input type="text" id="bb-new-key" placeholder="キー (例: task/status, agent/context)" style="width:210px">
        <input type="text" id="bb-new-val" placeholder="値" style="flex:1;min-width:160px">
        <button class="btn btn-blue" onclick="bbSet()">保存</button>
        <button class="btn btn-muted" onclick="bbSync()">↺ ノード同期</button>
      </div>
      <div id="bb-list"><div style="color:var(--muted);font-size:12px">読み込み中...</div></div>
    </div>

    <!-- === 設定・ベータ機能 === -->
    <div class="section" id="settings-section">
      <h2>⚙️ 設定・ベータ機能</h2>
      <div style="display:flex;gap:12px;flex-direction:column">
        <div style="display:flex;justify-content:space-between;align-items:center;padding:10px;background:#0d1117;border-radius:6px">
          <div>
            <div style="font-size:13px;font-weight:600">📋 Blackboard — エージェント知識共有</div>
            <div style="font-size:11px;color:var(--muted);margin-top:2px">複数のAIエージェントが読み書きできる共有メモ帳。マルチエージェント開発者向けベータ機能。</div>
          </div>
          <button class="btn btn-muted" id="bb-toggle-btn" onclick="toggleBlackboard()" style="font-size:11px;padding:4px 12px;white-space:nowrap;margin-left:12px">有効化</button>
        </div>
      </div>
    </div>

    <!-- === 接続情報 === -->
    <div class="grid2">
      <div class="section">
        <h2>Claude Code</h2>
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

    <!-- === Smart Routing === -->
    <div class="section">
      <h2>Smart Routing (auto)</h2>
      <p style="font-size:11px;color:var(--muted);margin-bottom:8px">
        <code style="color:var(--blue)">auto</code> / <code style="color:var(--blue)">nou</code> / <code style="color:var(--blue)">smart</code> を指定すると、複雑さに応じて最適なモデルに自動ルーティング。
      </p>
      <div class="code" id="smart-snippet">OPENAI_API_BASE=http://${IP}:4001/v1 OPENAI_API_KEY=sk-dummy aider --model openai/auto<button class="copy-btn" onclick="copyEl('smart-snippet')">コピー</button></div>
      <p style="font-size:10px;color:var(--muted)">simple → fast slot / medium,complex → main slot</p>
    </div>

    <!-- === ベンチマーク === -->
    <div class="section">
      <h2>ランタイムベンチマーク</h2>
      <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px">
        <button id="bench-btn" class="btn btn-blue" onclick="runBenchmark()">▶ ベンチマーク実行</button>
        <span id="bench-status" style="font-size:11px;color:var(--muted)"></span>
      </div>
      <div id="bench-results" class="hidden">
        <div class="grid2">
          <div class="stat-box" id="bench-mlx">
            <div style="font-size:10px;color:var(--purple);font-weight:600;margin-bottom:3px">MLX</div>
            <div class="stat-val" id="bench-mlx-tps">—</div>
            <div class="stat-label">tok/s gen</div>
          </div>
          <div class="stat-box" id="bench-lcpp">
            <div style="font-size:10px;color:var(--blue);font-weight:600;margin-bottom:3px">llama.cpp</div>
            <div class="stat-val" id="bench-lcpp-tps">—</div>
            <div class="stat-label">tok/s gen</div>
          </div>
        </div>
        <div id="bench-winner" style="text-align:center;margin-top:10px;font-size:12px;font-weight:600"></div>
      </div>
    </div>

    <!-- === PAC プロキシ === -->
    <div class="section">
      <h2>ゼロコンフィグ プロキシ</h2>
      <p style="font-size:11px;color:var(--muted);margin-bottom:8px">
        macOS設定 → Wi-Fi → 詳細 → プロキシ → 自動プロキシ構成 → URL:
      </p>
      <div class="code" id="pac-url">http://localhost:4001/proxy.pac<button class="copy-btn" onclick="copyEl('pac-url')">コピー</button></div>
    </div>

    <!-- === P2P Model Library === -->
    <div class="section">
      <h2>Model Library (P2P)</h2>
      <div class="grid2">
        <div>
          <h2 style="margin-bottom:8px">ローカルモデル</h2>
          <div id="local-models"><div style="color:var(--muted);font-size:12px">スキャン中...</div></div>
        </div>
        <div>
          <h2 style="margin-bottom:8px">ネットワークモデル</h2>
          <div id="network-models"><div style="color:var(--muted);font-size:12px">検索中...</div></div>
        </div>
      </div>
    </div>

    <script>
    const BASE = window.location.origin;
    const IP = window.location.hostname;
    let maxTps = 10;
    let rpcDistEnabled = false;

    // ======= Utilities =======
    function fmtUptime(s) {
      if (s < 60) return s + 's';
      if (s < 3600) return Math.floor(s/60) + 'm';
      return Math.floor(s/3600) + 'h ' + Math.floor((s%3600)/60) + 'm';
    }
    function fmtSize(bytes) {
      if (bytes >= 1073741824) return (bytes/1073741824).toFixed(1) + ' GB';
      if (bytes >= 1048576) return (bytes/1048576).toFixed(0) + ' MB';
      return (bytes/1024).toFixed(0) + ' KB';
    }
    function fmtDate(ts) {
      return new Date(ts * 1000).toLocaleTimeString();
    }
    function copyEl(id) {
      const el = document.getElementById(id);
      const text = el.innerText.replace(/コピー$/, '').trim();
      navigator.clipboard.writeText(text).then(() => {
        const btn = el.querySelector('.copy-btn');
        btn.textContent = '✓'; setTimeout(() => btn.textContent = 'コピー', 1500);
      });
    }

    // ======= Main stats refresh (5s) =======
    async function refresh() {
      try {
        const [health, models, stats, metrics] = await Promise.all([
          fetch(BASE+'/health').then(r=>r.json()).catch(()=>({})),
          fetch(BASE+'/api/models').then(r=>r.json()).catch(()=>[]),
          fetch(BASE+'/api/stats').then(r=>r.json()).catch(()=>({})),
          fetch(BASE+'/api/metrics').then(r=>r.json()).catch(()=>null),
        ]);

        // Node name
        if (health.hostname) document.getElementById('node-name').textContent = health.hostname;

        // セットアップバナー
        updateSetupBanner(health);

        // 統計
        const tps = parseFloat(stats.tok_per_sec||'0');
        document.getElementById('stat-tps').textContent = tps.toFixed(1);
        document.getElementById('stat-reqs').textContent = stats.total_requests||0;
        document.getElementById('stat-depin').textContent = stats.depin_requests||0;
        document.getElementById('stat-uptime').textContent = fmtUptime(stats.uptime_seconds||0);
        if (tps > maxTps) maxTps = tps;
        document.getElementById('tps-bar').style.width = Math.min(100, (tps/maxTps)*100) + '%';

        // メモリ/GPU/CPU
        if (metrics) {
          const ramPct = metrics.ram_used_pct || 0;
          const gpuPct = metrics.ram_total_gb > 0 ? Math.min(100, (metrics.gpu_est_gb / metrics.ram_total_gb) * 100) : 0;
          const cpuPct = Math.min(100, metrics.cpu_pct || 0);
          document.getElementById('ram-bar').style.width = ramPct + '%';
          document.getElementById('gpu-bar').style.width = gpuPct + '%';
          document.getElementById('cpu-bar').style.width = cpuPct + '%';
          document.getElementById('ram-label').textContent = (metrics.ram_used_gb||0).toFixed(1) + ' / ' + (metrics.ram_total_gb||0).toFixed(0) + ' GB';
          document.getElementById('gpu-label').textContent = '~' + (metrics.gpu_est_gb||0).toFixed(0) + ' GB';
          document.getElementById('cpu-label').textContent = cpuPct.toFixed(0) + '%';
          // Color bars by usage
          document.getElementById('ram-bar').className = 'bar-fill ' + (ramPct>85?'bar-red':ramPct>65?'bar-orange':'bar-blue');
        }

        // モデル状態
        const list = document.getElementById('models-list');
        const modelsHealth = health.models || {};
        const proxyOk = modelsHealth.proxy !== false;
        const allRows = [...(models||[]), {name:'proxy',label:'Proxy',running:proxyOk,runtime:'—',port:4001,model:'NOU proxy'}];
        const anyRunning = allRows.some(m => m.running === true);
        if (!anyRunning) {
          list.innerHTML = `
            <div style="padding:20px;text-align:center">
              <div style="font-size:32px;margin-bottom:12px">📦</div>
              <div style="font-size:14px;font-weight:600;margin-bottom:8px">モデルが起動していません</div>
              <div style="font-size:12px;color:var(--muted);margin-bottom:16px;line-height:1.7">
                メニューバー → ▶ 起動 でモデルを起動できます。<br>
                初回はモデルのダウンロードが必要です（数GB〜60GB）。
              </div>
              <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;text-align:left;margin-bottom:16px">
                <div style="background:#0d1117;border:1px solid var(--border);border-radius:8px;padding:12px">
                  <div style="font-size:11px;font-weight:600;color:var(--muted);margin-bottom:4px">🌱 16GB (M1〜M5)</div>
                  <div style="font-size:12px;font-weight:600">Qwen3-7B / Gemma3-4B</div>
                  <div style="font-size:11px;color:var(--muted)">4〜5GB · 高速・日常会話</div>
                </div>
                <div style="background:#0d1117;border:1px solid #1e3a1e;border-radius:8px;padding:12px">
                  <div style="font-size:11px;font-weight:600;color:var(--muted);margin-bottom:4px">🌿 32〜64GB (M3 Pro〜M5 Max)</div>
                  <div style="font-size:12px;font-weight:600">Qwen3-32B / DeepSeek-R1-14B</div>
                  <div style="font-size:11px;color:var(--muted)">18GB · バランス・コーディング</div>
                </div>
                <div style="background:#0d1117;border:1px solid #1e1e3a;border-radius:8px;padding:12px">
                  <div style="font-size:11px;font-weight:600;color:var(--muted);margin-bottom:4px">🌲 128GB+ (M3/M4/M5 Ultra)</div>
                  <div style="font-size:12px;font-weight:600">Qwen3-235B / Llama4-Scout</div>
                  <div style="font-size:11px;color:var(--muted)">80GB+ · 最高性能・GPT-4o級</div>
                </div>
              </div>
              <button class="btn btn-blue" onclick="fetch(BASE+'/api/runtime',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'start'})}).then(()=>setTimeout(refresh,2000))" style="font-size:12px">▶ 起動する</button>
            </div>
          `;
        } else {
        list.innerHTML = allRows.map(m => {
          const alive = m.running === true;
          const rt = m.runtime || '—';
          const rtBadge = rt === 'llamacpp' ? '<span class="badge badge-blue" style="margin-right:4px">llama.cpp</span>'
                        : rt === 'mlx' ? '<span class="badge badge-purple" style="margin-right:4px">MLX</span>'
                        : '';
          const toggleBtn = (m.name === 'main' || m.name === 'fast') && rt !== '—'
            ? `<button onclick="toggleRuntime('${m.name}','${rt}')" class="btn btn-muted" style="padding:2px 7px;font-size:10px;margin-left:4px">⇄</button>`
            : '';
          return `<div class="model-row">
            <div style="display:flex;align-items:center">
              <span class="dot ${alive?'on pulse':'off'}"></span>
              <div>
                <div class="model-name">${m.label || m.name}</div>
                <div class="model-meta">:${m.port} · ${m.model || ''}</div>
              </div>
            </div>
            <div style="display:flex;align-items:center;gap:4px">
              ${rtBadge}${toggleBtn}
              <span class="badge ${alive?'badge-green':'badge-red'}">${alive?'running':'stopped'}</span>
            </div>
          </div>`;
        }).join('');
        }

        // 接続スニペット
        document.getElementById('claude-code-snippet').innerHTML =
          `export ANTHROPIC_BASE_URL=http://${IP}:4001\nexport ANTHROPIC_API_KEY=sk-ant-dummy\nclaude --dangerously-skip-permissions` +
          `\n<button class="copy-btn" onclick="copyEl('claude-code-snippet')">コピー</button>`;
        document.getElementById('aider-snippet').innerHTML =
          `OPENAI_API_BASE=http://${IP}:4001/v1 \\\nOPENAI_API_KEY=sk-dummy \\\naider --model openai/qwen3.5-122b` +
          `\n<button class="copy-btn" onclick="copyEl('aider-snippet')">コピー</button>`;

        // アイドル状態
        const depinEl = document.getElementById('idle-status');
        if (stats.depin_requests > 0) {
          depinEl.innerHTML = '<span class="idle-badge idle-earning">💰 DePIN稼働中</span>';
        } else if (proxyOk) {
          depinEl.innerHTML = '<span class="idle-badge idle-active">🟢 ローカル稼働中</span>';
        } else {
          depinEl.innerHTML = '<span class="idle-badge idle-off">💤 停止中</span>';
        }
        document.getElementById('last-update').textContent = '更新: ' + new Date().toLocaleTimeString();

        // DePINリクエスト数をヘッダー統計に反映
        const depinReqs = stats.depin_requests || 0;
        const depinReqEl = document.getElementById('depin-stat-reqs');
        if (depinReqEl) depinReqEl.textContent = depinReqs.toLocaleString();
      } catch(e) { console.error(e); }
    }

    // ======= DePIN stats (即時 + 10s) =======
    async function refreshDepin() {
      try {
        const [rewards, relay] = await Promise.all([
          fetch(BASE+'/api/rewards').then(r=>r.json()).catch(()=>({})),
          fetch(BASE+'/api/relay/status').then(r=>r.json()).catch(()=>({})),
        ]);
        const isJapan = rewards.is_japan_mode !== false;
        const cuEl = document.getElementById('depin-stat-cu');
        const nouEl = document.getElementById('depin-stat-nou');
        const labelEl = document.getElementById('depin-reward-label');
        const walletEl = document.getElementById('depin-wallet-current');
        if (cuEl) cuEl.textContent = (rewards.compute_units || 0).toLocaleString();
        if (nouEl) {
          if (isJapan) {
            nouEl.textContent = (rewards.nch || 0).toFixed(4) + ' NCH';
            if (labelEl) labelEl.textContent = 'Compute Hours (NCH)';
          } else {
            nouEl.textContent = (rewards.nou_tokens_estimate || 0).toFixed(3) + ' NOU';
            if (labelEl) labelEl.textContent = 'NOU トークン (推定)';
          }
        }
        if (walletEl) {
          const w = rewards.wallet_address || '';
          walletEl.textContent = w ? '登録済み: ' + w.slice(0,6) + '...' + w.slice(-4) : '未登録';
          walletEl.style.color = w ? 'var(--green)' : 'var(--muted)';
        }
        updateRewardModeUI(isJapan ? 'japan' : 'global');

        // リレー状態カード更新
        const card = document.getElementById('depin-status-card');
        const title = document.getElementById('depin-status-title');
        const sub = document.getElementById('depin-status-sub');
        const urlEl = document.getElementById('depin-tunnel-url');
        const connectBtn = document.getElementById('relay-connect-btn');
        const disconnectBtn = document.getElementById('relay-disconnect-btn');
        const urlDisplay = document.getElementById('relay-url-display');
        const urlText = document.getElementById('relay-url-text');

        if (relay.connected) {
          if (card) { card.style.borderColor = 'var(--green)'; card.style.background = '#0d1f0d'; }
          if (title) title.textContent = '🟢 DePIN — 公開中';
          if (sub) sub.textContent = '独自リレー経由でグローバル公開中。URL固定で再起動しても変わりません。';
          if (urlEl) urlEl.innerHTML = relay.public_url
            ? `<a href="${relay.public_url}" target="_blank" style="color:var(--blue);font-weight:600">${relay.public_url}</a> <span class="badge badge-green">接続中</span>`
            : '';
          if (connectBtn) connectBtn.style.display = 'none';
          if (disconnectBtn) disconnectBtn.style.display = '';
          if (urlDisplay) urlDisplay.style.display = 'block';
          if (urlText && relay.public_url) urlText.textContent = relay.public_url;
        } else {
          if (card) { card.style.borderColor = 'var(--border)'; card.style.background = '#0d1117'; }
          if (title) title.textContent = '⚫ DePIN — オフ';
          if (sub) sub.textContent = '「リレーに接続」を押すとグローバル公開できます';
          if (urlEl) urlEl.innerHTML = '';
          if (connectBtn) connectBtn.style.display = '';
          if (disconnectBtn) disconnectBtn.style.display = 'none';
          if (urlDisplay) urlDisplay.style.display = 'none';
        }
      } catch(e) { console.error('refreshDepin:', e); }
    }

    async function relayConnect() {
      const btn = document.getElementById('relay-connect-btn');
      if (btn) { btn.disabled = true; btn.textContent = '接続中...'; }
      try {
        await fetch(BASE+'/api/relay/connect', {method:'POST'});
        await new Promise(r => setTimeout(r, 2000));
        await refreshDepin();
      } finally {
        if (btn) { btn.disabled = false; btn.textContent = '🔗 リレーに接続'; }
      }
    }

    async function relayDisconnect() {
      await fetch(BASE+'/api/relay/disconnect', {method:'POST'});
      await refreshDepin();
    }

    async function setAutoRelay(enabled) {
      try {
        await fetch(BASE+'/api/relay/auto-connect', {
          method: 'POST',
          headers: {'Content-Type':'application/json'},
          body: JSON.stringify({enabled})
        });
      } catch(e) { console.error(e); }
    }

    // ======= 初回セットアップバナー =======
    function modelForRam(gb) {
      if (gb >= 64) return {name:'Qwen3-32B', id:'mlx-community/Qwen3-32B-4bit', note:'高精度・最大モデル'};
      if (gb >= 32) return {name:'Qwen3-14B', id:'mlx-community/Qwen3-14B-4bit', note:'精度と速度のバランス'};
      if (gb >= 16) return {name:'Qwen3-8B',  id:'mlx-community/Qwen3-8B-4bit',  note:'16GB Macに最適 ✨'};
      return             {name:'Qwen3-4B',  id:'mlx-community/Qwen3-4B-4bit',  note:'8GB Mac向け、高速'};
    }

    function updateSetupBanner(health) {
      const banner = document.getElementById('setup-banner');
      if (!banner) return;
      const models = health.models || {};
      const hasModel = models.main || models.fast;
      banner.style.display = hasModel ? 'none' : 'block';
      if (hasModel) return;

      const ram = health.memory_gb || 8;
      const rec = modelForRam(ram);

      const stepsEl = document.getElementById('setup-steps');
      if (stepsEl) {
        const steps = [
          {n:1, done:false, label:'モデルをダウンロード'},
          {n:2, done:false, label:'起動を確認'},
          {n:3, done:false, label:'Claude Codeで使う'},
        ];
        stepsEl.innerHTML = steps.map(s => `
          <div style="display:flex;align-items:center;gap:6px;background:#0a1520;border:1px solid ${s.done?'#2ea043':'#1e3a5f'};border-radius:8px;padding:8px 14px">
            <span style="font-size:13px">${s.done?'✅':'⬜'}</span>
            <span style="font-size:12px;color:${s.done?'var(--green)':'#8ab4d8'}">${s.n}. ${s.label}</span>
          </div>`).join('');
      }

      const recEl = document.getElementById('setup-recommendation');
      if (recEl) recEl.innerHTML = `
        <div style="font-size:11px;color:#8ab4d8;margin-bottom:8px">あなたのMac (${ram}GB RAM) に推奨のモデル:</div>
        <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:10px">
          <div>
            <span style="font-size:15px;font-weight:700;color:#58a6ff">${rec.name}</span>
            <span style="font-size:11px;color:var(--muted);margin-left:8px">${rec.note}</span>
          </div>
          <div style="display:flex;gap:8px;flex-wrap:wrap">
            <button class="btn btn-blue" onclick="copyText('pip install mlx-lm && python -m mlx_lm.convert --hf-path ${rec.id} --mlx-path ~/models/mlx/${rec.name.toLowerCase()}')" style="font-size:11px">
              📋 コマンドをコピー
            </button>
            <a href="https://nou.link/start" target="_blank" style="font-size:11px;padding:4px 12px;border:1px solid #1e3a5f;border-radius:6px;color:#58a6ff;text-decoration:none">
              セットアップガイド →
            </a>
          </div>
        </div>`;
    }

    function copyText(text) {
      navigator.clipboard.writeText(text).then(() => {
        const btns = document.querySelectorAll('.btn-blue');
        btns.forEach(b => { if (b.textContent.includes('コピー')) { b.textContent = '✓ コピー済み'; setTimeout(()=>b.textContent='📋 コマンドをコピー', 2000); }});
      });
    }

    // Initialize auto-relay checkbox from backend
    async function initAutoRelay() {
      try {
        const status = await fetch(BASE+'/api/relay/status').then(r=>r.json()).catch(()=>({}));
        const cb = document.getElementById('auto-relay-checkbox');
        if (cb) cb.checked = status.auto_connect || false;
      } catch(e) {}
    }

    // ======= Network Nodes (10s) =======
    async function refreshNodes() {
      try {
        const nodes = await fetch(BASE+'/api/nodes').then(r=>r.json()).catch(()=>[]);
        const el = document.getElementById('network-nodes');
        if (nodes.length === 0) {
          el.innerHTML = '<div style="color:var(--muted);font-size:12px">リモートノードが見つかりません。Bonjour経由で自動発見またはURLを手動追加してください。</div>';
          return;
        }
        el.innerHTML = nodes.map(n => {
          const dot = n.healthy ? '<span class="dot on pulse"></span>' : '<span class="dot off"></span>';
          const pairIcon = n.paired ? '🔐' : '🔓';
          const rpcBadge = n.rpcAvailable ? '<span class="badge badge-blue">RPC 稼働中</span>' : '';

          const nodeSlots = (n.models||[]).map(s => {
            const rd = s.running ? `<span class="badge badge-green">${s.name}</span>` : `<span class="badge badge-red">${s.name} 停止中</span>`;
            const rt = s.runtime === 'llamacpp' ? '<span class="badge badge-blue">llama.cpp</span>' : '<span class="badge badge-purple">MLX</span>';
            return rd + rt;
          }).join('');

          // 1-click RPC action button
          let rpcAction = '';
          if (n.healthy && n.paired) {
            if (n.rpcAvailable) {
              rpcAction = `<button class="btn btn-blue" onclick="addNodeAsRPCWorker('${n.url}')" style="font-size:10px;padding:3px 8px">🖥️ ワーカーに追加</button>`;
            } else {
              rpcAction = `<button class="btn btn-muted" onclick="startRPCOnNode('${n.url}','${n.name}')" style="font-size:10px;padding:3px 8px">▶ RPC を起動</button>`;
            }
          } else if (n.healthy && !n.paired) {
            rpcAction = `<button class="btn btn-muted" onclick="pairNode('${n.url}')" style="font-size:10px;padding:3px 8px">🔓 ペアリング</button>`;
          }

          return `<div class="node-card">
            <div class="node-header">
              <div class="node-name">${dot}${n.tierIcon} ${n.name} ${pairIcon} ${rpcBadge}</div>
              <div style="display:flex;gap:4px;align-items:center;flex-wrap:wrap">
                <span class="badge" style="background:var(--border);color:var(--text)">${n.memoryGB}GB</span>
                <a href="${n.url}" target="_blank" class="badge badge-blue" style="text-decoration:none">Dashboard →</a>
                <span class="badge ${n.healthy?'badge-green':'badge-red'}">${n.healthy?'オンライン':'オフライン'}</span>
              </div>
            </div>
            <div class="node-models" style="margin-bottom:${rpcAction?'8':'0'}px">${nodeSlots || '<span style="color:var(--muted);font-size:11px">モデル情報なし</span>'}</div>
            ${rpcAction ? `<div style="display:flex;gap:6px;flex-wrap:wrap">${rpcAction}</div>` : ''}
          </div>`;
        }).join('');
      } catch(e) { console.error('Nodes error:', e); }
    }

    // 1-click: Add a discovered NOU node as RPC worker
    async function addNodeAsRPCWorker(nodeURL) {
      try {
        const host = new URL(nodeURL).hostname;
        const res = await fetch(BASE+'/api/rpc/workers', {
          method:'POST', headers:{'Content-Type':'application/json'},
          body: JSON.stringify({host, port: 50052})
        });
        if (res.ok) {
          alert(`✓ ${host} をRPCワーカーに追加しました。\n分散推論セクションで「分散モードをオン」にしてモデルを再起動してください。`);
          setTimeout(refreshRPC, 500);
        }
      } catch(e) { alert('追加失敗: ' + e.message); }
    }

    // 1-click: Start RPC server on a remote NOU node (requires pairing)
    async function startRPCOnNode(nodeURL, nodeName) {
      if (!confirm(`${nodeName} でRPCサーバーを起動しますか？\n（そのMacで llama-rpc-server が起動します）`)) return;
      try {
        const res = await fetch(nodeURL + '/api/rpc/start', {method:'POST'});
        if (res.ok) {
          alert(`✓ ${nodeName} でRPC起動を指示しました。数秒後に自動でワーカー追加されます。`);
          setTimeout(refreshNodes, 3000);
        } else {
          alert('起動失敗。そのノードでllama.cppがインストールされているか確認してください。');
        }
      } catch(e) { alert('通信失敗: ' + e.message); }
    }

    // Pair node
    async function pairNode(nodeURL) {
      const urlInput = document.getElementById('wan-url-input');
      if (urlInput) { urlInput.value = nodeURL; urlInput.scrollIntoView({behavior:'smooth'}); }
      alert('ノードURLを入力欄に設定しました。「+ ノードを追加」→ ペアリングを完了してください。');
    }

    // Add WAN node
    async function addWANNode() {
      const url = document.getElementById('wan-url-input').value.trim();
      if (!url) return;
      const status = document.getElementById('add-node-status');
      status.textContent = '追加中...';
      try {
        // Probe the node
        const info = await fetch(url + '/api/pair/info').then(r=>r.json());
        status.textContent = `✓ 発見: ${info.name || url} (${info.memory_gb}GB)`;
        document.getElementById('wan-url-input').value = '';
        // Ask server to add this as manual host
        await fetch(BASE+'/api/rpc/workers', {
          method:'POST',
          headers:{'Content-Type':'application/json'},
          body: JSON.stringify({host: new URL(url).hostname, port: 50052})
        });
        setTimeout(refreshNodes, 1000);
      } catch(e) {
        status.textContent = '❌ 接続失敗: ' + e.message;
      }
    }

    // Add RPC worker manually from the distributed inference step 3
    async function addRPCWorkerManual() {
      const host = document.getElementById('rpc-worker-host').value.trim();
      const portStr = document.getElementById('rpc-worker-port').value.trim();
      const port = parseInt(portStr) || 50052;
      if (!host) { alert('IPアドレスを入力してください'); return; }
      try {
        await fetch(BASE+'/api/rpc/workers', {
          method:'POST', headers:{'Content-Type':'application/json'},
          body: JSON.stringify({host, port})
        });
        document.getElementById('rpc-worker-host').value = '';
        document.getElementById('rpc-worker-port').value = '';
        setTimeout(refreshRPC, 500);
      } catch(e) { alert('追加失敗: ' + e.message); }
    }

    // ======= RPC / Distributed =======
    async function refreshRPC() {
      try {
        const r = await fetch(BASE+'/api/rpc/status').then(r=>r.json());
        rpcDistEnabled = r.distributed_enabled;
        const workers = r.workers || [];
        const onlineCount = workers.filter(w=>w.status==='online').length;

        document.getElementById('rpc-enable-btn').textContent =
          r.distributed_enabled ? '✓ 分散モード: ON' : '分散モード: OFF';
        document.getElementById('rpc-enable-btn').className =
          'btn ' + (r.distributed_enabled ? 'btn-green' : 'btn-muted');

        let html = `<div style="display:flex;gap:12px;flex-wrap:wrap;margin-bottom:8px">
          <span class="badge ${r.local_rpc_running?'badge-green':'badge-red'}">
            ${r.local_rpc_running?'● ローカルRPC稼働中 :' + r.local_rpc_port:'○ ローカルRPC停止中'}
          </span>
          <span class="badge ${r.rpc_server_available?'badge-blue':'badge-red'}">
            rpc-server: ${r.rpc_server_available?'✓':'✗ (要ビルド)'}
          </span>
          <span class="badge badge-blue">ワーカー: ${onlineCount}/${workers.length} online</span>
        </div>`;

        if (workers.length > 0) {
          html += '<div style="margin-top:4px">' + workers.map(w =>
            `<div style="display:flex;align-items:center;gap:6px;padding:4px 0;font-size:12px">
              <span class="dot ${w.status==='online'?'on pulse':'off'}"></span>
              <span style="font-family:monospace">${w.host}:${w.port}</span>
              <span class="badge ${w.status==='online'?'badge-green':w.status==='offline'?'badge-red':'badge-muted'}">${w.status}</span>
              <button onclick="removeWorker('${w.host}',${w.port})" class="btn btn-muted" style="padding:1px 6px;font-size:10px">削除</button>
            </div>`
          ).join('') + '</div>';
        } else {
          html += '<div style="color:var(--muted);font-size:11px">RPCワーカーなし。ペアリング済みノードが起動するか、手動追加してください。</div>';
        }

        if (r.local_rpc_running && r.rpc_server_available) {
          html += `<div class="code" style="margin-top:10px">llama-server --model <path> --rpc ${IP}:50052 --n-gpu-layers 99<button class="copy-btn" onclick="copyEl('rpc-cmd')">コピー</button></div>`;
        }
        document.getElementById('rpc-status').innerHTML = html;

        // Speculative decoding status (auto)
        const specAutoEl = document.getElementById('speculative-auto-status');
        if (specAutoEl) {
          if (r.speculative_enabled) {
            specAutoEl.textContent = '✓ 有効 — ドラフトモデル: ' + (r.draft_model || '自動');
            specAutoEl.style.color = 'var(--green)';
          } else {
            specAutoEl.textContent = '無効 — 小型モデルが検出されると自動で有効化されます';
            specAutoEl.style.color = 'var(--muted)';
          }
        }
      } catch(e) { console.error('RPC status error:', e); }
    }

    async function rpcAction(action) {
      await fetch(BASE+'/api/rpc/'+action, {method:'POST'});
      setTimeout(refreshRPC, 500);
    }
    async function rpcRefresh() {
      await fetch(BASE+'/api/rpc/refresh', {method:'POST'});
      setTimeout(refreshRPC, 1000);
    }
    async function rpcToggleEnable() {
      await fetch(BASE+'/api/rpc/enable', {
        method:'POST', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({enabled: !rpcDistEnabled})
      });
      setTimeout(refreshRPC, 300);
    }
    async function removeWorker(host, port) {
      await fetch(BASE+'/api/rpc/workers', {
        method:'DELETE', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({host, port})
      });
      setTimeout(refreshRPC, 300);
    }
    async function setSpeculative(enabled) {
      const path = document.getElementById('draft-model-path').value.trim();
      await fetch(BASE+'/api/rpc/speculative', {
        method:'POST', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({enabled, draft_model: path || undefined})
      });
      document.getElementById('speculative-status').textContent = enabled ? '✓ 有効化しました' : '無効化しました';
      setTimeout(refreshRPC, 500);
    }

    // ======= Blackboard =======
    async function refreshBlackboard() {
      try {
        const entries = await fetch(BASE+'/api/blackboard').then(r=>r.json()).catch(()=>[]);
        const el = document.getElementById('bb-list');
        if (!Array.isArray(entries) || entries.length === 0) {
          el.innerHTML = '<div style="color:var(--muted);font-size:12px">エントリなし。上のフォームから追加してください。</div>';
          return;
        }
        el.innerHTML = entries.map(e => {
          const age = Math.floor(Date.now()/1000 - e.timestamp);
          const ageStr = age < 60 ? age+'s' : age < 3600 ? Math.floor(age/60)+'m' : Math.floor(age/3600)+'h';
          const tags = (e.tags||[]).map(t=>`<span class="badge" style="background:var(--border);color:var(--muted)">${t}</span>`).join('');
          return `<div class="bb-row">
            <div class="bb-key">${e.key}</div>
            <div class="bb-val">${e.value} ${tags}</div>
            <div class="bb-meta">${e.author} · ${ageStr}</div>
            <button onclick="bbDelete('${e.key}')" class="btn btn-muted" style="padding:1px 6px;font-size:10px;flex-shrink:0">✕</button>
          </div>`;
        }).join('');
      } catch(e) { console.error('Blackboard error:', e); }
    }
    async function setRewardMode(mode) {
      await fetch(BASE+'/api/rewards/mode', {
        method:'POST', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({mode})
      });
      updateRewardModeUI(mode);
    }
    function updateRewardModeUI(mode) {
      const japanEl = document.getElementById('mode-japan');
      const globalEl = document.getElementById('mode-global');
      const walletEl = document.getElementById('wallet-section');
      const nchEl = document.getElementById('nch-info');
      if (!japanEl) return;
      if (mode === 'japan') {
        japanEl.style.borderColor = 'var(--green)';
        japanEl.style.background = '#0a1f0a';
        globalEl.style.borderColor = 'var(--border)';
        globalEl.style.background = 'transparent';
        walletEl.style.display = 'none';
        nchEl.style.display = 'block';
      } else {
        globalEl.style.borderColor = 'var(--blue)';
        globalEl.style.background = '#0a1a2a';
        japanEl.style.borderColor = 'var(--border)';
        japanEl.style.background = 'transparent';
        walletEl.style.display = 'block';
        nchEl.style.display = 'none';
      }
    }
    async function depinSetWallet() {
      const wallet = document.getElementById('depin-wallet-input').value.trim();
      if (!wallet) return;
      const res = await fetch(BASE+'/api/rewards/wallet', {
        method:'POST', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({wallet})
      });
      if (res.ok) {
        document.getElementById('depin-wallet-input').value = '';
        const el = document.getElementById('depin-wallet-current');
        if (el) { el.textContent = '登録済み: ' + wallet.slice(0,6) + '...' + wallet.slice(-4); el.style.color='var(--green)'; }
      }
    }
    async function bbSet() {
      const key = document.getElementById('bb-new-key').value.trim();
      const val = document.getElementById('bb-new-val').value.trim();
      if (!key || !val) return;
      await fetch(BASE+'/api/blackboard/'+encodeURIComponent(key), {
        method:'POST', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({value: val})
      });
      document.getElementById('bb-new-key').value = '';
      document.getElementById('bb-new-val').value = '';
      refreshBlackboard();
    }
    async function bbDelete(key) {
      await fetch(BASE+'/api/blackboard/'+encodeURIComponent(key), {method:'DELETE'});
      refreshBlackboard();
    }
    async function bbSync() {
      // Sync with all discovered nodes
      const nodes = await fetch(BASE+'/api/nodes').then(r=>r.json()).catch(()=>[]);
      for (const n of nodes.filter(n=>n.healthy && n.paired)) {
        try {
          const remote = await fetch(n.url+'/api/blackboard/export').then(r=>r.json());
          await fetch(BASE+'/api/blackboard/sync', {
            method:'POST', headers:{'Content-Type':'application/json'},
            body: JSON.stringify(remote)
          });
        } catch {}
      }
      refreshBlackboard();
    }

    // ======= Benchmark =======
    async function runBenchmark() {
      const btn = document.getElementById('bench-btn');
      const status = document.getElementById('bench-status');
      const results = document.getElementById('bench-results');
      btn.disabled = true; btn.textContent = '⏳ 実行中...';
      status.textContent = 'MLXとllama.cppを比較中 (約30秒)...';
      try {
        const r = await fetch(BASE+'/api/benchmark',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({slot:'main'})});
        const d = await r.json();
        results.classList.remove('hidden');
        document.getElementById('bench-mlx-tps').textContent = d.mlx.ok ? d.mlx.gen_tps.toFixed(1) : '—';
        document.getElementById('bench-lcpp-tps').textContent = d.llamacpp.ok ? d.llamacpp.gen_tps.toFixed(1) : '—';
        document.getElementById('bench-mlx-tps').style.color = d.winner==='mlx' ? 'var(--green)' : 'var(--muted)';
        document.getElementById('bench-lcpp-tps').style.color = d.winner==='llamacpp' ? 'var(--green)' : 'var(--muted)';
        const winLabel = d.winner === 'llamacpp' ? 'llama.cpp' : 'MLX';
        document.getElementById('bench-winner').innerHTML = '✅ ' + winLabel + ' をデフォルトに設定しました';
        status.textContent = '';
        refresh();
      } catch(e) { status.textContent = 'エラー: ' + e.message; }
      btn.disabled = false; btn.textContent = '▶ ベンチマーク実行';
    }

    async function toggleRuntime(slot, current) {
      const next = current === 'mlx' ? 'llamacpp' : 'mlx';
      if (!confirm('Switch ' + slot + ' runtime to ' + next + '?')) return;
      await fetch(BASE+'/api/runtime',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({slot,runtime:next})});
      refresh();
    }

    // ======= Model Library =======
    async function refreshModelLibrary() {
      try {
        const local = await fetch(BASE+'/api/models/available').then(r=>r.json()).catch(()=>[]);
        const localEl = document.getElementById('local-models');
        localEl.innerHTML = local.length === 0
          ? '<div style="color:var(--muted);font-size:12px">~/models/ にGGUFファイルなし</div>'
          : local.map(m => `<div class="model-row">
              <div><div class="model-name" style="font-size:12px">${m.name}</div>
              <div class="model-meta">${m.type}</div></div>
              <span class="badge badge-blue">${fmtSize(m.size)}</span>
            </div>`).join('');

        const networkEl = document.getElementById('network-models');
        networkEl.innerHTML = local.length > 0
          ? '<div style="color:var(--muted);font-size:12px">あなたのモデルはネットワーク上の他のNOUノードから利用可能です。</div>'
          : '<div style="color:var(--muted);font-size:12px">ペアリング済みノードのメニューバーから「モデルを取得」で入手できます。</div>';
      } catch(e) { console.error('Model library error:', e); }
    }

    // ======= Blackboard beta toggle =======
    function toggleBlackboard() {
      const bbSection = document.getElementById('blackboard-section');
      const btn = document.getElementById('bb-toggle-btn');
      const enabled = bbSection.style.display !== 'none';
      if (enabled) {
        bbSection.style.display = 'none';
        btn.textContent = '有効化';
        btn.className = 'btn btn-muted';
        localStorage.setItem('nou.beta.blackboard', 'false');
      } else {
        bbSection.style.display = 'block';
        btn.textContent = '無効化';
        btn.className = 'btn btn-muted';
        localStorage.setItem('nou.beta.blackboard', 'true');
        refreshBlackboard();
      }
    }

    // On load: restore blackboard state from localStorage
    (function() {
      if (localStorage.getItem('nou.beta.blackboard') === 'true') {
        const bbSection = document.getElementById('blackboard-section');
        if (bbSection) bbSection.style.display = 'block';
        const btn = document.getElementById('bb-toggle-btn');
        if (btn) { btn.textContent = '無効化'; btn.className = 'btn btn-muted'; }
      }
    })();

    // ======= Init & intervals =======
    initAutoRelay();
    refresh();
    setInterval(refresh, 5000);
    refreshDepin();
    setInterval(refreshDepin, 10000);
    refreshNodes();
    setInterval(refreshNodes, 10000);
    refreshRPC();
    setInterval(refreshRPC, 15000);
    refreshBlackboard();
    setInterval(refreshBlackboard, 20000);
    refreshModelLibrary();
    setInterval(refreshModelLibrary, 30000);
    </script>
    </body>
    </html>
    """#
}
