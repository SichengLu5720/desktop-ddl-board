#!/bin/bash
# Personal Workspace 本地版安装：只运行一次。
# 做的事：迁移当前看板数据 → 停用 Google 推送同步（只停用，不删除）→ 注册本地文件监听 → 立即同步一次。
set -euo pipefail

BASE="$HOME/Personal Workspace"
LA="$HOME/Library/LaunchAgents"
APPSUP="$HOME/Library/Application Support/PersonalWorkspace"
LABEL="local.user.personalworkspace.localsync"
PLIST="$LA/$LABEL.plist"
GUI="gui/$(id -u)"

echo "== Personal Workspace 本地版安装 =="
mkdir -p "$BASE/data" "$BASE/backups" "$BASE/logs" "$BASE/disabled-agents" "$LA"

# 0. 清理上次装错的位置 ~/PersonalWorkspace（无空格）：数据和停用的旧配置搬过来
OLDBASE="$HOME/PersonalWorkspace"
if [ -d "$OLDBASE" ] && [ "$OLDBASE" != "$BASE" ]; then
  if [ ! -f "$BASE/data/workspace.json" ] && [ -f "$OLDBASE/data/workspace.json" ]; then
    cp "$OLDBASE/data/workspace.json" "$BASE/data/workspace.json"
  fi
  if [ -d "$OLDBASE/disabled-agents" ]; then
    for f in "$OLDBASE/disabled-agents"/*.plist; do
      [ -e "$f" ] && mv "$f" "$BASE/disabled-agents/"
    done
  fi
  mv "$OLDBASE" "$BASE/old-PersonalWorkspace-$(date '+%Y%m%d-%H%M%S')"
  echo "[0/4] 已把上次装错位置的文件移到 $BASE"
fi

# 1. 迁移数据：用看板当前快照作为本地数据源（已存在则不覆盖）
if [ ! -f "$BASE/data/workspace.json" ]; then
  if [ -f "$APPSUP/snapshot.json" ]; then
    cp "$APPSUP/snapshot.json" "$BASE/data/workspace.json"
    chmod 644 "$BASE/data/workspace.json"
    cp "$BASE/data/workspace.json" "$BASE/backups/workspace-migrated-$(date '+%Y%m%d-%H%M%S').json"
    echo "[1/4] 已从看板快照迁移数据"
  else
    echo "[1/4] 失败：找不到 $APPSUP/snapshot.json" >&2
    exit 1
  fi
else
  echo "[1/4] data/workspace.json 已存在，保留不动"
fi

# 2. 停用 Google 推送同步（plist 移到 disabled-agents，可随时恢复）
for L in local.user.personalworkspace.readonlysync local.user.personalworkspace.googlepush; do
  launchctl bootout "$GUI/$L" 2>/dev/null || true
  if [ -f "$LA/$L.plist" ]; then
    mv "$LA/$L.plist" "$BASE/disabled-agents/"
  fi
done
echo "[2/4] 已停用 Google 推送同步（旧配置在 disabled-agents/）"

# 3. 注册本地文件监听：data/ 文件夹一变化就运行 apply.sh
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$BASE/bin/apply.sh</string>
  </array>
  <key>WatchPaths</key>
  <array>
    <string>$BASE/data</string>
  </array>
  <key>ThrottleInterval</key><integer>2</integer>
  <key>StandardOutPath</key><string>$BASE/logs/launchd.out.log</string>
  <key>StandardErrorPath</key><string>$BASE/logs/launchd.err.log</string>
</dict>
</plist>
EOF
launchctl bootout "$GUI/$LABEL" 2>/dev/null || true
launchctl bootstrap "$GUI" "$PLIST"
echo "[3/4] 已注册本地监听：$LABEL"

# 4. 立即同步一次并显示结果
rm -f "$BASE/logs/.last-hash"
/bin/bash "$BASE/bin/apply.sh" || true
echo "[4/4] 同步结果：$(cat "$BASE/logs/last-sync.txt" 2>/dev/null || echo 未知)"

echo
echo "安装完成。以后 ~/Personal Workspace/data/workspace.json 一改，看板就会自动刷新。"
echo "可以关闭这个窗口了。"
