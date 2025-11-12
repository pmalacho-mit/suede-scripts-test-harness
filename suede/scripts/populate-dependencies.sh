#!/usr/bin/env bash
set -euo pipefail

# Populates ./dist/.dependencies with:
#  - one <folder>.gitrepo file for each immediate child folder that contains a .gitrepo
#  - a minimal package.json containing only { "dependencies": { ... } } if package.json exists
#  - a requirements.txt copy if requirements.txt exists
#
# Safe to run on GitHub runners and locally. Existing files are overwritten.

ROOT="$PWD"
DEST_DIR="$ROOT/dist/.dependencies"

log() { printf '[populate-deps] %s\n' "$*"; }

# Ensure destination directory exists
mkdir -p "$DEST_DIR"
log "Ensured destination directory: $DEST_DIR"

# Copy .gitrepo files from immediate child directories (root-level folders only)
# Skips 'dist' and '.git' folders.
shopt -s nullglob dotglob
for dir in "$ROOT"/*/ ; do
  [[ -d "$dir" ]] || continue
  base="$(basename "$dir")"
  [[ "$base" == "dist" || "$base" == ".git" ]] && continue

  src="$dir/.gitrepo"
  if [[ -f "$src" ]]; then
    dst="$DEST_DIR/$base.gitrepo"
    cp -f "$src" "$dst"
    log "Copied $src -> $dst"
  fi
done
shopt -u nullglob dotglob

# Extract only "dependencies" from package.json, write to dist/.dependencies/package.json
pkg_src="$ROOT/package.json"
pkg_dst="$DEST_DIR/package.json"
if [[ -f "$pkg_src" ]]; then
  log "Found package.json; extracting dependencies"
  if command -v jq >/dev/null 2>&1; then
    jq '{dependencies: (.dependencies // {})}' "$pkg_src" > "$pkg_dst"
  elif command -v node >/dev/null 2>&1; then
    node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json","utf8"));console.log(JSON.stringify({dependencies:p.dependencies||{}}, null, 2));' > "$pkg_dst"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' > "$pkg_dst"
import json
with open("package.json","r",encoding="utf-8") as f:
    p=json.load(f)
print(json.dumps({"dependencies": p.get("dependencies", {})}, indent=2))
PY
  else
    log "WARNING: Could not find jq, node, or python3; skipping package.json dependency extraction"
  fi
  [[ -f "$pkg_dst" ]] && log "Wrote $pkg_dst"
fi

# Copy requirements.txt if present
req_src="$ROOT/requirements.txt"
req_dst="$DEST_DIR/requirements.txt"
if [[ -f "$req_src" ]]; then
  cp -f "$req_src" "$req_dst"
  log "Copied $req_src -> $req_dst"
fi

log "Done."
