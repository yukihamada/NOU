# 🧠 NOU — Private AI

**あなたのMacとiPhoneで動くローカルAI。クラウド不要、データはデバイスの外に出ない。**

[![macOS](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple)](https://github.com/yukihamada/NOU/releases/latest)
[![iOS](https://img.shields.io/badge/iOS-17%2B-blue?logo=apple)](https://testflight.apple.com/join/NOUiPhone)
[![Windows](https://img.shields.io/badge/Windows-10%2F11-blue?logo=windows)](https://github.com/yukihamada/NOU/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Homebrew](https://img.shields.io/badge/Homebrew-yukihamada%2Ftap-orange?logo=homebrew)](https://github.com/yukihamada/homebrew-tap)

![NOU demo](https://nou.link/assets/demo.gif)

---

## ダウンロード

| プラットフォーム | インストール方法 |
|---|---|
| **Mac (Apple Silicon)** | `brew tap yukihamada/tap && brew install --cask nou` または [DMGをダウンロード](https://github.com/yukihamada/NOU/releases/latest/download/NOU-Installer.dmg) |
| **iPhone** | [TestFlightで参加](https://testflight.apple.com/join/NOUiPhone) |
| **Windows 10/11** | [NOU-Setup-Windows.exe](https://github.com/yukihamada/NOU/releases/latest/download/NOU-Setup-Windows.exe) + [Ollama](https://ollama.com/download) |
| **Linux** | `curl -sSL nou.link/install.sh \| bash` |

---

## 特徴

- **🔒 完全プライベート** — 会話は一切サーバーに送信されない。Apple Silicon上でMLXが推論
- **🧠 メニューバーアプリ** — 左クリックでクイックチャット、右クリックで設定メニュー
- **📱 iPhone対応** — iPhoneからMacのAIにシームレスに接続
- **🌐 分散推論** — 複数のMacをBonjour経由でメッシュ接続、モデルを分散実行
- **🔌 OpenAI互換API** — Claude Code / Cursor / Aider などのツールがそのまま使える
- **⚡ ワンクリックセットアップ** — Ollama / MLX-LM の自動インストール対応
- **🪟 Windows対応** — Ollama経由でWindows PCからも使用可能

---

## クイックスタート (Mac)

```bash
# Homebrew でインストール（推奨）
brew tap yukihamada/tap
brew install --cask nou

# または curl で一発インストール
curl -sSL nou.link/install.sh | bash
```

インストール後、アプリを起動するとウェルカム画面が表示されます。
画面の指示に従って Ollama とモデルをインストールしてください。

---

## 対応モデル

| モデル | 必要RAM | 特徴 |
|---|---|---|
| Gemma 4 2B (4bit) | 4GB | 超高速、日常用途 |
| **Gemma 4 4B (4bit) ★推奨** | 6GB | 高速 + 高品質のバランス |
| Gemma 4 31B (4bit) | 20GB | 最高品質、M3 Max以上推奨 |
| Llama 3.1 8B | 10GB | 英語特化 |
| Qwen3 14B | 18GB | 多言語対応 |

---

## アーキテクチャ

```
Browser/iPhone ──→ NOU Proxy (localhost:4001)
                         │
              ┌──────────┴──────────────┐
              ↓                         ↓
        MLX-LM Server              Ollama Server
     (Apple Silicon GPU)          (CPU / GPU)
        port 5000-5002              port 11434
              │
              └──→ 分散推論 (Bonjour mDNS)
                   → 他のMac / iPhone
```

```
NOU.app-src/          # macOS メニューバーアプリ (Swift + Hummingbird)
Sources/              # iOS アプリ (SwiftUI + LocalLLMClient)
site/                 # ランディングページ (nou.link)
nou-windows/          # Windows インストーラー (NSIS)
```

---

## 開発環境のセットアップ

### macOS アプリ

```bash
cd NOU.app-src
swift build -c release
./build-app.sh 2.3.0
open NOU.app
```

### iOS アプリ

```bash
# Xcodegenでプロジェクト生成
xcodegen generate
open NOU.xcodeproj
```

---

## プライバシー

NOU はあなたの会話データをサーバーに送信しません。
詳細は[プライバシーポリシー](https://nou.link/privacy.html)をご覧ください。

---

## ライセンス

MIT License © 2026 EnablerDAO

## リンク

- 🌐 **サイト**: [nou.link](https://nou.link)
- 🍺 **Homebrew Tap**: [yukihamada/homebrew-tap](https://github.com/yukihamada/homebrew-tap)
- 📦 **リリース**: [GitHub Releases](https://github.com/yukihamada/NOU/releases)
- 🏢 **開発元**: [EnablerDAO](https://enablerdao.com)
