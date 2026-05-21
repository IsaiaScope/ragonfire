#!/usr/bin/env python3
"""Parser routing for RagOnFire ingest."""
from __future__ import annotations

from pathlib import Path


# Parser vocabulary. These three names are the only parsers RagOnFire selects by
# routing; any other value is a configured pass-through handed straight to
# RAG-Anything. Defined here, the single home of Parser Routing, so the dispatch
# seam in rag_adapter imports them instead of re-spelling the literals.
PYMUPDF = "pymupdf"  # fast text-layer path, our own (not a RAG-Anything parser)
HYBRID = "hybrid"    # MinerU vision + pymupdf text recovery, our own
MINERU = "mineru"    # full MinerU OCR pipeline (an upstream RAG-Anything parser)

# pymupdf and hybrid are PDF paths implemented in this repo, not upstream parsers.
# "Is this one of our custom PDF paths?" is asked in two places (dispatch and
# config); is_custom_pdf_path owns that rule so the two cannot disagree.
CUSTOM_PDF_PARSERS = (PYMUPDF, HYBRID)


def is_custom_pdf_path(parser: str, is_pdf: bool) -> bool:
    """True if RagOnFire owns this document's parse path (vs. delegating upstream)."""
    return is_pdf and parser in CUSTOM_PDF_PARSERS


# A digital PDF whose largest page-image coverage meets this fraction is treated
# as figure-bearing (route to hybrid for MinerU vision). Below it, images are
# decorative (headshot/logo) and the pymupdf fast path loses nothing.
FIGURE_COVERAGE_THRESHOLD = 0.15


def pdf_has_text_layer(pdf_path: Path, min_chars: int = 100) -> bool:
    """True if the PDF carries a real text layer, false if it is scanned."""
    import fitz

    with fitz.open(str(pdf_path)) as doc:
        return sum(len(p.get_text("text")) for p in doc) >= min_chars


def pdf_max_image_coverage(pdf_path: Path) -> float:
    """Largest fraction of any page covered by raster images."""
    import fitz

    worst = 0.0
    with fitz.open(str(pdf_path)) as doc:
        for page in doc:
            page_area = (page.rect.width * page.rect.height) or 1.0
            covered = 0.0
            for img in page.get_images(full=True):
                try:
                    covered += sum(r.width * r.height for r in page.get_image_rects(img[0]))
                except Exception:
                    continue
            worst = max(worst, covered / page_area)
    return worst


def route_parser(
    file_path: Path,
    configured_parser: str,
    *,
    has_text_layer=pdf_has_text_layer,
    max_image_coverage=pdf_max_image_coverage,
    figure_coverage_threshold: float = FIGURE_COVERAGE_THRESHOLD,
) -> str:
    """Resolve the effective parser for one input file."""
    is_pdf = file_path.suffix.lower() == ".pdf"
    if configured_parser != "auto" or not is_pdf:
        return configured_parser
    if not has_text_layer(file_path):
        return MINERU
    if max_image_coverage(file_path) >= figure_coverage_threshold:
        return HYBRID
    return PYMUPDF
