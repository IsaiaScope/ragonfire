---
name: lightrag-upload
description: Upload a plain-text document (TXT, MD, simple PDF) to the local LightRAG knowledge base via REST API. Use this skill for text-only files. For PDFs containing images, tables, charts, or equations, use /raganything-upload instead. Triggers on phrases like "upload to lightrag", "add this to my knowledge base", "index this document", "ingest this file", or any request to add a text document to the knowledge graph.
---

# LightRAG Upload

Upload a text-based document to the local LightRAG knowledge base via REST. LightRAG processes the file in the background — extracting entities, building the knowledge graph, creating embeddings.

Postgres handles concurrent ingest + query, so the server stays up during upload.

## When to use this vs /raganything-upload

- **`/lightrag-upload`** — plain text (TXT, MD, CSV, simple text-only PDFs). REST API, fast.
- **`/raganything-upload`** — PDFs/DOCX/PPTX with images, tables, charts, equations. Runs MinerU + VLM pipeline locally. Slower but understands non-text content.

## Configuration

- **Server:** `http://localhost:9622`
- **Runtime dir:** `~/rag-anything`
- **Data dir:** `$RAGONFIRE_DATA_DIR` from `~/rag-anything/.env`

## Preflight: ensure server is up

```bash
curl -sf http://localhost:9622/health >/dev/null || { echo "Server down — run /lightrag-start first"; exit 1; }
```

If the check fails, invoke `/lightrag-start` before continuing.

## Usage

### Upload a file

```bash
curl -s -X POST http://localhost:9622/documents/upload \
  -F "file=@/path/to/document.txt"
```

Supported file types: TXT, MD, CSV, PDF (text-only), DOCX (light), and other text-based formats.

### Check processing status

```bash
curl -s http://localhost:9622/documents/pipeline_status
```

Key fields:
- `busy` — `true` if documents are still being processed
- `latest_message` — current step
- `docs` — documents in the current batch

### Wait for completion

Poll every 5-10s until `busy` is `false`:

```bash
while curl -s http://localhost:9622/documents/pipeline_status | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('busy') else 1)"; do
  sleep 5
done
echo "Done."
```

### Insert raw text (no file)

```bash
curl -s -X POST http://localhost:9622/documents/text \
  -H "Content-Type: application/json" \
  -d "{\"text\": \"The text content to index here\"}"
```

## Example Flow

User: "Add my research notes to the knowledge base" (provides file path)

1. Check server up → if not, `/lightrag-start`
2. POST file to `/documents/upload`
3. Poll `/documents/pipeline_status` until `busy=false`
4. Hit `/graph/label/popular?limit=5` to show the top new entities
5. Confirm: "Document indexed. LightRAG extracted X entities, Y relationships. Top entities: ..."

## Error Handling

- **Server unreachable** — run `/lightrag-start`. If still down, run `/lightrag-status` and inspect `$HOST_LOGS_DIR`.
- **Upload fails** — verify file exists and is text-based. For PDFs with visual content, use `/raganything-upload`.
- **Pipeline stuck** — large files take minutes. Check `latest_message` for progress.
