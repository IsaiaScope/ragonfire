# ADR 0003: Route PDFs by Text Layer and Image Coverage

## Status

Accepted

## Context

MinerU gives strong structure and multimodal extraction, but it can spend
minutes OCRing documents that already have a good text layer. PyMuPDF is much
faster for text-layer PDFs, but it does not caption meaningful figures.

## Decision

Use parser routing for PDFs:

- no text layer: `mineru`
- text layer plus meaningful page image coverage: `hybrid`
- text layer with no or decorative images: `pymupdf`

The hybrid path uses MinerU for multimodal structure and recovers text that
MinerU may drop from narrow columns.

## Consequences

Text-heavy PDFs ingest quickly, scanned PDFs still get OCR, and figure-bearing
PDFs preserve multimodal content. The routing heuristics are part of the runtime
interface and must be covered by focused tests.
