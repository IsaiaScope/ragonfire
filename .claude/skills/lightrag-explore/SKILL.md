---
name: lightrag-explore
description: Explore entities and relationships in the local LightRAG knowledge graph. Use this skill when the user wants to know what their knowledge base contains about a topic, explore connections in the graph, list entities, or understand how concepts relate. Triggers on phrases like "what does my KB know about", "explore the graph for", "show me connections to", "what entities relate to", "/lightrag-explore", or any request to browse or inspect the knowledge graph structure.
---

# LightRAG Explore

Search entities and traverse the knowledge graph.

## Configuration

- **Server:** `http://localhost:9622`

## Preflight

```bash
curl -sf http://localhost:9622/health >/dev/null || { echo "Server down — run /lightrag-start"; exit 1; }
```

## Step 1 — Find entities matching the topic

LightRAG 1.4.5 has no server-side label search endpoint. Pull the full label
list and filter client-side (case-insensitive substring):

```bash
curl -s "http://localhost:9622/graph/label/list" \
  | python3 -c 'import sys,json; t="SEARCH_TERM".lower(); print([x for x in json.load(sys.stdin) if t in x.lower()])'
```

Returns a JSON array of matching entity names.

## Step 2 — Subgraph around an entity

```bash
curl -s "http://localhost:9622/graphs?label=ENTITY_NAME&max_depth=2&max_nodes=30"
```

Parameters:
- `label` — entity name (URL-encode spaces / parens)
- `max_depth` — relationship hops (default 2)
- `max_nodes` — cap (default 30)

Returns:
- `nodes` — entities (`id`, `description`, ...)
- `edges` — relationships (`source`, `target`, `description`)

## Step 3 — Format

1. **Entity found:** name
2. **Connected to:** list of related entities + relationship description
3. **Key relationships:** most interesting connections

## Other useful endpoints

```bash
# All entity labels
curl -s "http://localhost:9622/graph/label/list"

# Existence check
curl -s "http://localhost:9622/graph/entity/exists?name=ENTITY_NAME"
```

## Example flow

User: "What does my KB know about MinerU?"

1. `curl -s "http://localhost:9622/graph/label/list" | python3 -c 'import sys,json; t="mineru"; print([x for x in json.load(sys.stdin) if t in x.lower()])'` → `["MinerU", "MinerU Parser"]`
2. `curl -s "http://localhost:9622/graphs?label=MinerU&max_depth=2&max_nodes=20"`
3. Present:
   > **MinerU** is connected to:
   > - RAG-Anything (uses MinerU as default parser)
   > - PDF Processing (MinerU's primary modality)
   > - Layout Detection (MinerU runs layout models per page)
   > - ...

## Error Handling

- **Server unreachable** — run `/lightrag-start`
- **No entities match** — suggest broader search term, or check `/lightrag-status` to confirm documents are indexed
- **Graph empty** — knowledge base hasn't been populated yet
