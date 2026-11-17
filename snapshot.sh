#!/bin/zsh
# Рендер поповера в PNG (debug-збірка): ./snapshot.sh out.png
"$(dirname "$0")/.build-dd/Build/Products/Debug/EB3AMonitor.app/Contents/MacOS/EB3AMonitor" --snapshot | sed -n 's/^PNG://p' | base64 -d > "${1:-popover.png}"
