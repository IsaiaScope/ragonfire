#!/usr/bin/env bash
# RagOnFire — skills-only installer
#
# Copies every SKILL.md from rag-anything/skills/ into ~/.claude/skills/<name>/.
# Use this when you only want the slash commands and have already set up
# Ollama + venv elsewhere (or are not running the pipeline locally).
#
# For a full install (Ollama, models, Python venv, skills), use:
#   ./rag-anything/bootstrap.sh
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
SRC="$REPO_DIR/rag-anything/skills"
DEST="$HOME/.claude/skills"

log() { printf "\033[1;36m[install-skills]\033[0m %s\n" "$*"; }

[ -d "$SRC" ] || { echo "✗ no skills dir at $SRC"; exit 1; }
mkdir -p "$DEST"

count=0
for skill_dir in "$SRC"/*/; do
  name=$(basename "$skill_dir")
  [ -f "$skill_dir/SKILL.md" ] || { log "skip $name (no SKILL.md)"; continue; }
  mkdir -p "$DEST/$name"
  cp "$skill_dir/SKILL.md" "$DEST/$name/SKILL.md"
  log "✓ $name"
  count=$((count + 1))
done

cat <<EOF

\033[1;32mInstalled $count skills to $DEST\033[0m

Try in Claude Code:
  /lightrag-start       — boot LightRAG server
  /lightrag-stop        — shut it down
  /lightrag-upload      — push a text doc (REST)
  /raganything-upload   — multimodal ingest via MinerU + VLM
  /lightrag-status      — KB health
  /lightrag-query       — ask the KG
  /lightrag-explore     — walk the graph

Note: the skills assume the runtime exists at ~/rag-anything/ with the
LightRAG server on :9621 and Ollama on :11434. If not yet set up, run:
  ./rag-anything/bootstrap.sh
EOF
