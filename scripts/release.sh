#!/usr/bin/env bash
# Build a release archive of the app for the current platform into dist/.
# CI (.github/workflows/release.yml) runs the same steps on all platforms.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist

case "$(uname -s)" in
Darwin)
    (cd app && flutter build macos --release)
    ditto -c -k --keepParent \
        "app/build/macos/Build/Products/Release/Genre Analyzer.app" \
        dist/GenreAnalyzer-macos.zip
    echo "dist/GenreAnalyzer-macos.zip"
    ;;
Linux)
    (cd app && flutter build linux --release)
    tar -czf dist/GenreAnalyzer-linux-x64.tar.gz \
        -C app/build/linux/x64/release bundle
    echo "dist/GenreAnalyzer-linux-x64.tar.gz"
    ;;
*)
    echo "use scripts/release.ps1 on Windows"
    exit 1
    ;;
esac
