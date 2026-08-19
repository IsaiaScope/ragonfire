#!/usr/bin/env python3
"""PyMuPDF text extraction and MinerU dropped-text recovery.

These functions read a PDF's text layer directly via pymupdf4llm. They back the
pymupdf fast path and the hybrid path's column-recovery, and are kept here (not
in rag_adapter) so the LightRAG/RAG-Anything adapter stays free of PDF concerns.
"""
from __future__ import annotations

import re
from pathlib import Path


def pdf_to_markdown_content(pdf_path: Path) -> list[dict]:
    """Extract a PDF to a structured-markdown content list via pymupdf4llm.

    MinerU's layout model discards narrow side columns (e.g. CV date rails) into
    discarded_blocks and flattens column newlines, silently dropping content.
    pymupdf4llm reads the PDF text layer directly and is column- and
    heading-aware, so the date rail survives AND stays attached to its section
    (raw get_text with sort=True interleaves columns row-by-row and garbles
    two-column layouts). Text-only: images/tables are not captioned (use the
    mineru parser for figure-heavy documents).
    """
    import pymupdf4llm

    md = pymupdf4llm.to_markdown(str(pdf_path)).strip()
    if not md:
        return []
    return [{"type": "text", "text": md}]


def _norm(s: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[#*_`>|\-–—]", " ", s)).strip().lower()


def recover_dropped_text(pdf_path: Path, content_list: list[dict]) -> str:
    """Lines present in the PDF (via pymupdf4llm) but absent from MinerU's output.

    MinerU's layout model discards narrow columns (e.g. CV date rails) it deems
    page furniture. This recovers them by line-diffing pymupdf4llm's markdown
    against MinerU's text -- using only the parser's *public* content_list, not
    its internal middle.json schema, so it is not coupled to MinerU internals.
    """
    import pymupdf4llm

    mineru_norm = _norm(
        " ".join(i.get("text", "") for i in content_list if i.get("type") == "text")
    )
    missing: list[str] = []
    seen: set[str] = set()
    for line in pymupdf4llm.to_markdown(str(pdf_path)).splitlines():
        s = line.strip().strip("#*_> ").strip()
        n = _norm(s)
        if len(n) < 3 or n in seen or n in mineru_norm:
            continue
        missing.append(s)
        seen.add(n)
    return "\n".join(missing)
