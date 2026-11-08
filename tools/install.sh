#!/bin/bash
# Builds clove natively and installs it.
#   tools/install.sh [DEST_DIR]      from the repository root; AIL=/path/to/ail (default ../ail)
# DEST_DIR defaults to ~/.local/bin. Prints the installed path.
set -eu
cd "$(git rev-parse --show-toplevel)"
dest=${1:-$HOME/.local/bin}
mkdir -p "$dest"
"${AIL:-../ail}/ail" build clove.ail -o "$dest/clove"
echo "installed $dest/clove"
case ":$PATH:" in *":$dest:"*) ;; *) echo "note: $dest is not on PATH" ;; esac
