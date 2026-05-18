---
name: raganything-upload
description: Process a multimodal document (PDF with images/tables/charts/equations, DOCX, PPTX, XLSX, scanned images) through the local RAG-Anything pipeline into the LightRAG knowledge graph. MinerU parses layout + extracts visual content; qwen2.5-vl interprets images via Ollama; entities written to the shared LightRAG storage. Use this skill whenever the user wants to ingest a PDF or complex document containing non-text content (charts, tables, images, equations) or any office file (DOCX/PPTX/XLSX). Triggers on phrases like "process this PDF", "raganything upload", "ingest this with raganything", "add this document to the knowledge graph with multimodal support", or any request to process documents with visual/tabular content.
---

# RAG-Anything Upload

Process a multimodal document through RAG-Anything: MinerU parses structure (text/tables/equations/images), qwen2.5-vl (Ollama) interprets images, bge-m3 embeds chunks, entities written to LightRAG storage.

## When to use this vs /lightrag-upload

- **`/lightrag-upload`** — plain text (TXT, MD, simple PDF). REST API, fast.
- **`/raganything-upload`** — PDFs/DOCX/PPTX/XLSX with images, tables, charts, equations, or any image file. Runs full multimodal pipeline (MinerU + VLM). Slower but understands non-text content.

## Configuration

- **Project:** `/Users/isaia/rag-anything` (code), `/Volumes/Crucial-4T/rag-anything` (storage/output)
- **Python:** `/Users/isaia/rag-anything/.venv/bin/python` (Python 3.12 venv)
- **Script:** `/Users/isaia/rag-anything/scripts/ingest.py`
- **Storage:** `/Volumes/Crucial-4T/rag-anything/storage` (shared with LightRAG server)
- **Output:** `/Volumes/Crucial-4T/rag-anything/output` (MinerU parsed artifacts: markdown, images, JSON)
- **Models:** qwen2.5-vl 7B (LLM + vision) + bge-m3 (embed), both via Ollama
- **Parser:** MinerU on MPS (Apple Silicon GPU)
- **No API keys needed** — fully local

## Supported file types

PDF, DOCX, PPTX, XLSX, JPG, PNG, BMP, TIFF, GIF, WebP, TXT, MD.

## Usage

### Process a single document

The LightRAG server holds storage files open. Stop it before ingest to prevent corruption, then restart after to reload the updated graph.

```bash
# 1. Stop server (releases storage lock)
/Users/isaia/rag-anything/scripts/server-stop.sh

# 2. Run multimodal ingest
/Users/isaia/rag-anything/.venv/bin/python \
  /Users/isaia/rag-anything/scripts/ingest.py \
  "/path/to/document.pdf"

# 3. Restart server (reloads KG from disk)
/Users/isaia/rag-anything/scripts/server-start.sh
```

### Process multiple documents

Loop: stop once → ingest all → restart once.

```bash
/Users/isaia/rag-anything/scripts/server-stop.sh
for f in /path/to/docs/*.pdf; do
  /Users/isaia/rag-anything/.venv/bin/python \
    /Users/isaia/rag-anything/scripts/ingest.py "$f"
done
/Users/isaia/rag-anything/scripts/server-start.sh
```

## What happens under the hood

1. **MinerU** parses the doc on MPS (Apple Silicon GPU) — identifies text blocks, tables, equations, images. No API calls.
2. **Text / tables / equations** → structured text → qwen2.5-vl (Ollama) for entity extraction.
3. **Images / charts** → base64 → qwen2.5-vl vision endpoint (Ollama) for visual interpretation → entities extracted.
4. **bge-m3** (Ollama) embeds all chunks (1024-dim).
5. **Knowledge graph + vector DB** written to `/Volumes/Crucial-4T/rag-anything/storage/`.
6. **MinerU artifacts** (parsed markdown, extracted images, layout JSON) saved to `/Volumes/Crucial-4T/rag-anything/output/<filename>/`.

## Timing (rough, on M4 32GB)

- 1-page text PDF: ~30 sec
- 10-page PDF with tables + a few images: 3-8 min
- 50-page paper with many figures + equations: 15-30 min

MinerU layout pass dominates. Ollama inference is the next biggest chunk (loads model on first call, ~10s warmup).

## Example flow

User: "Process this research paper through RAG-Anything" (provides path)

1. Confirm file path.
2. Stop server: `scripts/server-stop.sh`.
3. Run `ingest.py <path>`.
4. Stream output — show MinerU progress (`Parsing page X/Y`), entity counts.
5. Restart server: `scripts/server-start.sh`.
6. Confirm: "Document processed through RAG-Anything. MinerU detected X text blocks, Y tables, Z images. Entities added to KG. Server back up — query with /lightrag-query."

## Error Handling

- **`ModuleNotFoundError: raganything`** — venv not installed. Run `/Users/isaia/rag-anything/bootstrap.sh`.
- **`Connection refused: 11434`** — Ollama down. `brew services start ollama`, then retry.
- **MinerU model download (first run)** — multi-GB download to `~/.mineru/`. Normal. Subsequent runs use cache.
- **MPS out of memory** — set `MINERU_DEVICE=cpu` in `.env` (slower but works). Or close other GPU-heavy apps.
- **Storage lock errors** — server still running. Re-run `server-stop.sh` and confirm with `server-status.sh` before ingesting.
- **Crucial-4T not mounted** — drive must be plugged in. Storage path will not resolve.
- **Vector dim mismatch** — `.env` says `EMBEDDING_DIM=1024` (bge-m3). If you swap embedding model, update dim AND wipe `storage/` (vectors incompatible across models).

## Free-tier sanity

Zero API keys, zero per-token cost. Everything runs locally on the M4. Ollama models live in `~/.ollama/models/`. MinerU models in `~/.mineru/`. KG + vectors in `/Volumes/Crucial-4T/rag-anything/storage/`.
