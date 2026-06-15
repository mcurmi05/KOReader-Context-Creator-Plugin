#!/bin/sh
#installs the plugin into the local mac koreader by replacing the old copy with this repos version
#edit the repo, re-run this, then restart koreader to pick up the changes (plugins only load at startup)
#
#usage:
#  ./dev.sh   copy contextcreator.koplugin into koreaders plugin dir, replacing whats there

SRC="$(cd "$(dirname "$0")" && pwd)/contextcreator.koplugin"
DEST_DIR="$HOME/Library/Application Support/koreader/plugins"
DEST="$DEST_DIR/contextcreator.koplugin"

[ -d "$SRC" ] || { echo "plugin source not found at $SRC"; exit 1; }
mkdir -p "$DEST_DIR"

#drop whatever is installed now (old copy, or the old dev symlink) and drop the fresh plugin in.
#rm on a symlink only removes the link, so this never touches the repo
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "installed contextcreator.koplugin -> $DEST"
echo "restart koreader to load it"
