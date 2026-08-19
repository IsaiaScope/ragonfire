---
name: lightrag-query
description: Query the local LightRAG knowledge base from Claude Code and return a formatted answer with source references. Use this skill when the user wants to ask their knowledge base a question, search their knowledge graph, query LightRAG, or retrieve information from their indexed documents. Triggers on phrases like "ask my knowledge base", "query lightrag", "search my documents", "what does my KB say about", "/lightrag-query", or any natural-language question that should be answered from indexed content.
---

# LightRAG Query

Query the local LightRAG knowledge base via REST and return a formatted answer with sources.

## Configuration

- **Server:** `http://localhost:9622`

## Preflight: server must be up

```bash
curl -sf http://localhost:9622/health >/dev/null || { echo "Server down — run /lightrag-start"; exit 1; }
```

If down, invoke `/lightrag-start` first.

## Usage

```bash
curl -s -X POST http://localhost:9622/query \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"USER_QUESTION_HERE\", \"mode\": \"hybrid\"}"
```

## Query Modes

- `hybrid` (default, recommended) — entity relationships + graph traversal + vectors
- `mix` — knowledge graph + vector retrieval combined (best with reranker)
- `naive` — basic vector similarity (traditional RAG)
- `local` — immediate entity relationships only
- `global` — high-level cross-graph knowledge

If the user does not specify a mode, use `hybrid`.

## Response format

JSON with:
- `response` — answer text (markdown)
- `references` — list of source documents

Format for the user:
1. Answer (markdown)
2. **Sources** — bulleted list of references

## Example

User: "What's the relationship between Anthropic and Claude Code?"

```bash
curl -s -X POST http://localhost:9622/query \
  -H "Content-Type: application/json" \
  -d '{"query": "What is the relationship between Anthropic and Claude Code?", "mode": "hybrid"}'
```

## Error Handling

- **Server unreachable** — run `/lightrag-start`
- **Empty answer** — try a different mode (`mix`, `local`, `global`) or check `/lightrag-status` to verify documents are indexed
- **Slow first query** — Ollama loads models on first request (~10-30s). Subsequent queries are fast.
