#!/bin/sh
#runs the installed mac koreader from terminal so plugin logs n crashes print out
#plugin is symlinked into koreaders user plugin dir so just edit the repo n re-run this
#
#usage:
#  ./dev.sh                   open koreader normally
#  ./dev.sh path/to/book.epub open straight into a book
#  KO_DEBUG=1 ./dev.sh        verbose logging (logger.dbg stuff)

KO_DIR="/Applications/KOReader.app/Contents/koreader"

cd "$KO_DIR" || { echo "KOReader.app not found at $KO_DIR"; exit 1; }

if [ -n "$KO_DEBUG" ]; then
    exec ./reader.lua -d "$@"
else
    exec ./reader.lua "$@"
fi
