#!/bin/bash
# 编译 → 跑三组测试 → 备份并替换已安装的看板程序 → 重新签名 → 重启看板。
# 不读写 data/workspace.json，不联网。旧程序备份到 Application Support/PersonalWorkspace/app-backups/时间戳/。
set -euo pipefail
APP_SRC="$(cd "$(dirname "$0")" && pwd)"
BUILD="$APP_SRC/.build"
APPSUP="$HOME/Library/Application Support/PersonalWorkspace"
STAMP="$(date '+%Y%m%d-%H%M%S')"
NEW="$BUILD/PersonalWorkspace"
mkdir -p "$BUILD"
exec > >(tee "$BUILD/update.log") 2>&1
echo "开始：$STAMP"

echo "== 1/4 编译 =="
/bin/bash "$APP_SRC/build.sh"

echo "== 2/4 测试 =="
/usr/bin/swiftc "$APP_SRC/TimelineData.swift" "$APP_SRC/tests/main.swift" -o "$BUILD/test-timeline"
"$BUILD/test-timeline" "$APP_SRC/../data/workspace.json"
/usr/bin/swiftc "$APP_SRC/DailyTimerState.swift" "$APP_SRC/tests/timer/main.swift" -o "$BUILD/test-timer"
"$BUILD/test-timer"
/usr/bin/swiftc "$APP_SRC/TitleFormatter.swift" "$APP_SRC/tests/titles/main.swift" -o "$BUILD/test-titles"
"$BUILD/test-titles"

echo "== 3/4 替换已安装程序 =="
TARGETS=()
add() { local p="$1"; [ -n "$p" ] && [ -f "$p" ] && [ -x "$p" ] || return 0
  case "$p" in "$BUILD"/*) return 0;; esac
  for t in "${TARGETS[@]+"${TARGETS[@]}"}"; do [ "$t" = "$p" ] && return 0; done
  TARGETS+=("$p"); }
# 正在运行的看板
while IFS= read -r p; do add "$p"; done < <(ps -axo comm= | grep '/PersonalWorkspace$' || true)
# 已知安装位置
add "$APPSUP/Personal Workspace.app/Contents/MacOS/PersonalWorkspace"
add "$APPSUP/ReadOnlySync/PersonalWorkspace"
# 登录启动项里引用的程序
for plist in "$HOME/Library/LaunchAgents"/*.plist; do
  [ -f "$plist" ] || continue
  while IFS= read -r p; do
    case "$p" in *.app) add "$p/Contents/MacOS/PersonalWorkspace";; *) add "$p";; esac
  done < <(/usr/bin/plutil -extract ProgramArguments json -o - "$plist" 2>/dev/null | tr ',' '\n' | sed -n 's/.*"\(\/[^"]*PersonalWorkspace[^"]*\)".*/\1/p' | sed 's/\\\//\//g')
done
if [ ${#TARGETS[@]} -eq 0 ]; then echo "没有找到已安装的看板程序，未替换。新程序在：$NEW"; exit 1; fi
BK="$APPSUP/app-backups/$STAMP"; mkdir -p "$BK"
n=0
for exe in "${TARGETS[@]}"; do
  n=$((n+1))
  case "$exe" in
    *.app/Contents/MacOS/*) cp -Rp "${exe%/Contents/MacOS/*}" "$BK/$n-$(basename "${exe%/Contents/MacOS/*}")";;
    *) cp -p "$exe" "$BK/$n-$(basename "$exe")";;
  esac
  printf '%s\t%s\n' "$n" "$exe" >> "$BK/where.txt"
  cp "$NEW" "$exe"; chmod 755 "$exe"
  case "$exe" in
    *.app/Contents/MacOS/*)
      app="${exe%/Contents/MacOS/*}"
      res="$app/Contents/Resources"
      if [ -d "$res" ]; then
        for f in main.swift TimelineData.swift TimelineViews.swift DailyTimerState.swift DailyTimerView.swift TitleFormatter.swift BoardStyle.swift; do cp "$APP_SRC/$f" "$res/$f"; done
        if [ -f "$res/Workspace.swift" ]; then
          cat "$APP_SRC/TimelineData.swift" "$APP_SRC/DailyTimerState.swift" "$APP_SRC/TitleFormatter.swift" "$APP_SRC/BoardStyle.swift" "$APP_SRC/DailyTimerView.swift" "$APP_SRC/TimelineViews.swift" "$APP_SRC/main.swift" > "$res/Workspace.swift"
        fi
      fi
      /usr/bin/codesign --force --deep --sign - "$app"
      echo "已替换并签名：$app";;
    *)
      /usr/bin/codesign --force --sign - "$exe"
      echo "已替换并签名：$exe";;
  esac
done

echo "== 4/4 重启看板 =="
pkill -x PersonalWorkspace 2>/dev/null || true
sleep 3
if ! pgrep -x PersonalWorkspace >/dev/null; then
  for exe in "${TARGETS[@]}"; do
    case "$exe" in *.app/Contents/MacOS/*) open "${exe%/Contents/MacOS/*}"; break;; esac
  done
fi
sleep 2
pgrep -x PersonalWorkspace >/dev/null && echo "看板已重启。" || echo "看板未自动启动，请手动打开。"
echo "旧版本备份在：${BK}（where.txt 记录原位置）"
