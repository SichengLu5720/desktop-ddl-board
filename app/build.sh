#!/bin/bash
# Build the offline desktop application. Does not install, sync, or edit task data.
set -euo pipefail
APP_SRC="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$APP_SRC/.build"
mkdir -p "$BUILD_DIR"
/usr/bin/swiftc "$APP_SRC/main.swift" "$APP_SRC/TimelineData.swift" "$APP_SRC/TimelineViews.swift" "$APP_SRC/DailyTimerState.swift" "$APP_SRC/DailyTimerView.swift" "$APP_SRC/TitleFormatter.swift" "$APP_SRC/BoardStyle.swift" -o "$BUILD_DIR/PersonalWorkspace" -framework AppKit -framework SwiftUI
echo "Built: $BUILD_DIR/PersonalWorkspace"
