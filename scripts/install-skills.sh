#!/usr/bin/env bash
# RagOnFire — skills-only installer
#
# Copies every SKILL.md from rag-anything/skills/ into one or more AI agent
# skill directories.
#
# Usage:
#   ./install-skills.sh                                # default: claude-code
#   ./install-skills.sh --agent codex
#   ./install-skills.sh --agent claude-code --agent codex
#   ./install-skills.sh --agent all                    # both agents
#   ./install-skills.sh --dry-run                      # list skills only
#
# For a full install (Ollama, models, Python venv, skills), use:
#   ./rag-anything/bootstrap.sh
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
SRC="$REPO_DIR/rag-anything/skills"

log() { printf "\033[1;36m[install-skills]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; exit 1; }

agent_dir() {
  case "$1" in
    claude-code) echo "$HOME/.claude/skills" ;;
    codex)       echo "$HOME/.codex/skills" ;;
    *) err "unknown agent: $1 (expected: claude-code | codex | all)" ;;
  esac
}

usage() {
  awk 'NR==1 { next } /^[^#]/ { exit } { sub(/^# ?/, ""); print }' "$0"
  exit "${1:-0}"
}

# Parse args
AGENTS=()
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)    AGENTS+=("$2"); shift 2 ;;
    --agent=*)  AGENTS+=("${1#*=}"); shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    -h|--help)  usage 0 ;;
    *)          err "unknown arg: $1 (try --help)" ;;
  esac
done

# Expand "all" or default
if [ ${#AGENTS[@]} -eq 0 ]; then
  AGENTS=("claude-code")
fi
EXPANDED=()
for a in "${AGENTS[@]}"; do
  if [ "$a" = "all" ]; then
    EXPANDED+=("claude-code" "codex")
  else
    EXPANDED+=("$a")
  fi
done
AGENTS=("${EXPANDED[@]}")

# Dedupe
SEEN=""
UNIQUE=()
for a in "${AGENTS[@]}"; do
  case " $SEEN " in
    *" $a "*) ;;
    *) UNIQUE+=("$a"); SEEN="$SEEN $a" ;;
  esac
done
AGENTS=("${UNIQUE[@]}")

[ -d "$SRC" ] || err "no skills dir at $SRC"

if [ "$DRY_RUN" -eq 1 ]; then
  for skill_dir in "$SRC"/*/; do
    name=$(basename "$skill_dir")
    [ -f "$skill_dir/SKILL.md" ] || continue
    echo "$name/SKILL.md"
  done
  exit 0
fi

# Install loop
total=0
for agent in "${AGENTS[@]}"; do
  DEST=$(agent_dir "$agent")
  mkdir -p "$DEST"
  log "→ installing into $agent ($DEST)"
  count=0
  for skill_dir in "$SRC"/*/; do
    name=$(basename "$skill_dir")
    [ -f "$skill_dir/SKILL.md" ] || { log "  skip $name (no SKILL.md)"; continue; }
    mkdir -p "$DEST/$name"
    cp "$skill_dir/SKILL.md" "$DEST/$name/SKILL.md"
    log "  ✓ $name"
    count=$((count + 1))
  done
  log "  installed $count skills"
  total=$((total + count))
done

cat <<EOF

\033[1;32mDone. Installed $total skill entries across ${#AGENTS[@]} agent(s): ${AGENTS[*]}\033[0m

Try the slash commands:
  /lightrag-start       — boot LightRAG server
  /lightrag-stop        — shut it down
  /lightrag-upload      — push a text doc (REST)
  /raganything-upload   — multimodal ingest via MinerU + VLM
  /lightrag-status      — KB health
  /lightrag-query       — ask the KG
  /lightrag-explore     — walk the graph
  /db-snapshot          — take a pg_dump backup
  /db-restore           — restore a pg_dump backup
  /db-list-snapshots    — list pg_dump backups
  /db-grow              — resize the pgdata image
  /lightrag-eject       — stop stack and eject drive
  /lightrag-upgrade     — rebuild after schema pin changes

Skills assume the runtime exists at ~/rag-anything/ with the LightRAG server
on :9622 and Ollama on :11434. If not yet set up, run:
  ./rag-anything/bootstrap.sh
EOF
