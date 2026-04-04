# NOU — Private AI on Your Mac

NOU is a native macOS menu bar app that runs large language models (up to 122B parameters) entirely on your device using Apple Silicon and MLX. No cloud, no subscriptions, no data leaves your machine.

Connect multiple Macs on your local network to form a distributed AI mesh, pooling compute across devices for faster inference on larger models.

## Features

- **100% On-Device AI** -- All inference runs locally via MLX on Apple Silicon. Your data never leaves your Mac.
- **Menu Bar App** -- Lives in your macOS menu bar. Always one click away, never in the way.
- **Distributed Mesh Networking** -- Discover and connect nearby Macs via Bonjour (`_nou._tcp`). Split model layers across machines for larger models and faster generation.
- **Smart Router** -- Automatically picks the best available model and node for each request based on load and capability.
- **OpenAI-Compatible API** -- Exposes a local HTTP server so any tool that speaks the OpenAI API can use your local models (IDE plugins, scripts, other apps).
- **Built-in Plugins** -- Web search, image generation, and code execution plugins extend the AI's capabilities.
- **Quick AI Panel** -- A floating panel for fast queries without opening a full window.
- **Dashboard** -- Monitor model status, connected nodes, and request statistics from a built-in web dashboard.
- **Tunnel Support** -- Securely expose your local NOU instance for remote access.
- **Pairing System** -- Securely pair new devices to your mesh with token-based authentication.

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1/M2/M3/M4)
- Swift 5.9+

## Installation

### Download

Download the latest `.app` bundle from [Releases](https://github.com/yukihamada/NOU/releases), move it to `/Applications`, and open it.

### Build from Source

```bash
cd NOU.app-src
swift build -c release
```

Or use the included build script to produce a full `.app` bundle:

```bash
cd NOU.app-src
./build-app.sh
open NOU.app
```

## Architecture

```
NOU.app-src/
  Package.swift          # Swift Package Manager manifest
  Sources/
    App/                 # AppDelegate, main entry, dashboard view, popover, quick AI panel
    Client/              # API client for node-to-node communication
    Dashboard/           # Built-in web dashboard HTML
    Discovery/           # Bonjour service publisher and browser
    Menubar/             # Menu bar controller
    MLX/                 # Model configuration for MLX inference
    Plugins/             # Web search, image gen, code execution plugins
    Server/              # HTTP server (Hummingbird), proxy, handlers, distributed inference
    Stats/               # Request statistics tracking
site/                    # Landing page at nou.link
```

## How It Works

1. **Launch** -- NOU starts as a menu bar icon on macOS.
2. **Model Loading** -- MLX loads a quantized LLM into unified memory on Apple Silicon.
3. **Local Server** -- A Hummingbird HTTP server starts on localhost, exposing OpenAI-compatible endpoints.
4. **Discovery** -- Bonjour advertises the node on the local network. Other NOU instances auto-discover and connect.
5. **Distributed Inference** -- When a request arrives, the Smart Router decides whether to run it locally or distribute layers across mesh nodes for optimal throughput.

## Tech Stack

- **Swift** + **SwiftUI** (macOS native)
- **MLX** via [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) for on-device inference
- **Hummingbird** HTTP server for the local API
- **Bonjour / mDNS** for zero-config mesh discovery

## License

MIT

## Links

- Website: [nou.link](https://nou.link/)
- Organization: [EnablerDAO](https://enablerdao.com)
