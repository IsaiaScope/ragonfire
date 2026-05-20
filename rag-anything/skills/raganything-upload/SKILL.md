---
name: raganything-upload
description: Process a multimodal document (PDF with images/tables/charts/equations, DOCX, PPTX, XLSX, scanned images) through the local RAG-Anything pipeline into the LightRAG knowledge graph. MinerU parses layout + extracts visual content; qwen2.5-vl interprets images via Ollama; entities written to Postgres-backed LightRAG storage. Use this skill whenever the user wants to ingest a PDF or complex document containing non-text content.
---

# RAG-Anything Upload

Process a multimodal document through RAG-Anything: MinerU parses structure, qwen2.5-vl interprets images, bge-m3 embeds chunks, and LightRAG stores retrieval state in Postgres.

Postgres handles concurrent ingest + query, so the server stays up during multimodal upload.

## Usage

```bash
~/rag-anything/.venv/bin/python \
  ~/rag-anything/scripts/ingest.py \
  "/path/to/document.pdf"
```

## Supported file types

PDF, DOCX, PPTX, XLSX, JPG, PNG, BMP, TIFF, GIF, WebP, TXT, MD.

## Error Handling

- `ModuleNotFoundError: raganything` - venv not installed. Run the repo's `rag-anything/bootstrap.sh`.
- `Connection refused: 11434` - Ollama is down. Run `/lightrag-start`, then retry.
- MinerU model download on first run can take several minutes.
- MPS/CUDA memory pressure - set `MINERU_DEVICE=cpu` in `.env`.
