#!/usr/bin/env bash
# One-command start (macOS / Linux): sets up the Python venv, launches the
# app (prebuilt bundle if present, otherwise builds it with Flutter) and runs
# the inference server in the foreground. Ctrl+C stops the server.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d .venv ]; then
    echo "creating Python venv..."
    python3 -m venv .venv
fi
if ! .venv/bin/python -c "import torch, fastapi, librosa" 2>/dev/null; then
    echo "installing Python dependencies (first run takes a few minutes)..."
    .venv/bin/pip install -q -r requirements.txt
fi

launch_app() {
    case "$(uname -s)" in
    Darwin)
        local app="app/build/macos/Build/Products/Release/Genre Analyzer.app"
        if [ ! -d "$app" ]; then
            require_flutter
            (cd app && flutter build macos --release)
        fi
        open "$app"
        ;;
    Linux)
        local app="app/build/linux/x64/release/bundle/genre_analyzer"
        if [ ! -x "$app" ]; then
            require_flutter
            (cd app && flutter build linux --release)
        fi
        "$app" &
        ;;
    esac
}

require_flutter() {
    if ! command -v flutter >/dev/null; then
        echo "No prebuilt app and no Flutter SDK found."
        echo "Either install Flutter (https://flutter.dev) or download the"
        echo "prebuilt app from GitHub Releases and unzip it into the path above."
        exit 1
    fi
}

launch_app

if curl -s -o /dev/null http://127.0.0.1:8000/status; then
    echo "inference server is already running on :8000"
else
    echo "starting inference server on :8000 (Ctrl+C to stop)"
    exec .venv/bin/uvicorn server.main:app --port 8000
fi
