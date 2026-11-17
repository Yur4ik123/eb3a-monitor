#!/bin/zsh
# Збірка Release і встановлення в /Applications: ./install.sh
set -e
cd "$(dirname "$0")/mac"
xcodegen generate -q
xcodebuild -project EB3AMonitor.xcodeproj -scheme EB3AMonitor -configuration Release \
  -derivedDataPath ../.build-dd -allowProvisioningUpdates build -quiet
pkill -x EB3AMonitor || true
sleep 1
rm -rf /Applications/EB3AMonitor.app
cp -R ../.build-dd/Build/Products/Release/EB3AMonitor.app /Applications/
open /Applications/EB3AMonitor.app
echo "Встановлено: /Applications/EB3AMonitor.app"
