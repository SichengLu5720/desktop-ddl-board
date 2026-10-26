#!/bin/bash
# Personal Workspace 本地版：data/workspace.json 一变化，launchd 就运行本脚本，
# 用看板自带的校验导入命令刷新桌面看板。事件触发，不轮询，不联网。
set -u

BASE="$HOME/Personal Workspace"
SRC="$BASE/data/workspace.json"
LOGDIR="$BASE/logs"
BACKUPS="$BASE/backups"
LOG="$LOGDIR/sync.log"
STATUS="$LOGDIR/last-sync.txt"
HASHFILE="$LOGDIR/.last-hash"

IMPORTER="$HOME/Library/Application Support/PersonalWorkspace/ReadOnlySync/PersonalWorkspace"
if [ ! -x "$IMPORTER" ]; then
  IMPORTER="$HOME/Library/Application Support/PersonalWorkspace/Personal Workspace.app/Contents/MacOS/PersonalWorkspace"
fi

mkdir -p "$LOGDIR" "$BACKUPS"
now() { date '+%Y-%m-%d %H:%M:%S'; }

[ -f "$SRC" ] || exit 0

# 写入方可能分几步落盘，稍等文件稳定
sleep 1

HASH=$(shasum -a 256 "$SRC" | cut -d' ' -f1)
if [ -f "$HASHFILE" ] && [ "$(cat "$HASHFILE")" = "$HASH" ]; then
  exit 0
fi

if [ ! -x "$IMPORTER" ]; then
  echo "$(now) FAIL 找不到看板导入程序" >> "$LOG"
  echo "FAIL $(now) 找不到看板导入程序" > "$STATUS"
  exit 1
fi

if OUT=$("$IMPORTER" --import-snapshot "$SRC" 2>&1); then
  cp "$SRC" "$BACKUPS/workspace-$(date '+%Y%m%d-%H%M%S').json"
  echo "$HASH" > "$HASHFILE"
  echo "$(now) OK $HASH" >> "$LOG"
  echo "OK $(now)" > "$STATUS"
  # 只保留最近 60 份备份
  ls -1t "$BACKUPS"/workspace-*.json 2>/dev/null | tail -n +61 | while IFS= read -r f; do rm -f "$f"; done
else
  echo "$(now) FAIL $OUT" >> "$LOG"
  echo "FAIL $(now) $OUT" > "$STATUS"
  exit 1
fi
