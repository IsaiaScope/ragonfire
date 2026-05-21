#!/usr/bin/env python3
"""Local adapter around LightRAG and RAG-Anything integration points."""
from __future__ import annotations

import sys
import logging
from pathlib import Path
from typing import Callable

from parser_routing import HYBRID, MINERU, PYMUPDF, is_custom_pdf_path


LOGGER = logging.getLogger("ragonfire.ingest")

PRIVATE_RAGANYTHING_METHODS = (
    "_ensure_lightrag_initialized",
    "_generate_content_based_doc_id",
    "_process_multimodal_content",
)


def require_private_raganything_interface(rag: object) -> None:
    """Fail clearly if the pinned RAG-Anything private interface drifts."""
    missing = [name for name in PRIVATE_RAGANYTHING_METHODS if not hasattr(rag, name)]
    if missing:
        names = ", ".join(missing)
        raise RuntimeError(
            "RAG-Anything private interface changed; missing "
            f"{names}. Check the raganything pin and update rag_adapter.py."
        )


def create_lightrag(runtime, embedding_func, llm_func, lightrag_kwargs: dict[str, object]):
    """Create a LightRAG instance while shielding callers from import side effects.

    Extraction-prompt tuning is installed here, before LightRAG is constructed, so
    the temporal coupling (tuning must precede prompt use) cannot be misordered by
    callers.
    """
    from extraction_tuning import install_extraction_tuning

    install_extraction_tuning(runtime.extraction_tuning)
    argv = sys.argv[:]
    try:
        sys.argv = [sys.argv[0]]
        from lightrag import LightRAG

        return LightRAG(
            working_dir=runtime.working_dir,
            llm_model_func=llm_func,
            llm_model_name=runtime.extraction_model,
            embedding_func=embedding_func,
            **lightrag_kwargs,
        )
    finally:
        sys.argv = argv


async def initialize_lightrag(lightrag) -> None:
    from lightrag.kg.shared_storage import initialize_pipeline_status

    await lightrag.initialize_storages()
    await initialize_pipeline_status()


def create_raganything_config(runtime, parser: str, is_pdf: bool):
    """Build a RAGAnythingConfig for one runtime and resolved parser.

    pymupdf/hybrid are our own PDF paths, not RAG-Anything parsers; for them we
    pass a valid upstream parser name ("mineru") that is unused because the custom
    paths bypass process_document_complete.
    """
    from raganything import RAGAnythingConfig

    use_custom_pdf_path = is_custom_pdf_path(parser, is_pdf)
    return RAGAnythingConfig(
        working_dir=runtime.working_dir,
        parser=MINERU if use_custom_pdf_path else parser,
        parse_method=runtime.parse_method,
        enable_image_processing=runtime.enable_image,
        enable_table_processing=runtime.enable_table,
        enable_equation_processing=runtime.enable_equation,
    )


def create_raganything(lightrag, config, llm_func, vision_func, embedding_func):
    from raganything import RAGAnything

    rag = RAGAnything(
        lightrag=lightrag,
        config=config,
        llm_model_func=llm_func,
        vision_model_func=vision_func,
        embedding_func=embedding_func,
    )
    require_private_raganything_interface(rag)
    return rag


async def insert_text_content_list(rag, file_path: Path, content_list: list[dict]) -> str:
    """Insert an already parsed text content list into LightRAG."""
    from raganything.utils import insert_text_content, separate_content

    await rag._ensure_lightrag_initialized()
    doc_id = rag._generate_content_based_doc_id(content_list)
    text_content, _ = separate_content(content_list)
    await insert_text_content(
        rag.lightrag,
        text_content,
        file_paths=file_path.name,
        ids=doc_id,
    )
    return doc_id


async def ingest_mineru_with_recovery(
    rag,
    file_path: Path,
    output_dir: Path,
    parse_method: str,
    device: str,
    recover_dropped_text: Callable[[Path, list[dict]], str],
) -> None:
    """Run MinerU parse, append recovered text, then insert text and multimodal items."""
    from raganything.utils import insert_text_content, separate_content

    content_list, doc_id = await rag.parse_document(
        str(file_path), str(output_dir), parse_method, False, device=device
    )
    recovered = recover_dropped_text(file_path, content_list)
    if recovered:
        LOGGER.info("recovered %s dropped line(s) via pymupdf4llm", len(recovered.splitlines()))
        content_list = content_list + [{"type": "text", "text": recovered}]
    text_content, multimodal_items = separate_content(content_list)
    if text_content.strip():
        await insert_text_content(
            rag.lightrag, text_content, file_paths=file_path.name, ids=doc_id
        )
    if multimodal_items:
        await rag._process_multimodal_content(multimodal_items, str(file_path), doc_id)


async def ingest_document(
    rag,
    parser: str,
    is_pdf: bool,
    file_path: Path,
    output_dir: Path,
    runtime,
    *,
    to_markdown: Callable[[Path], list[dict]],
    recover_text: Callable[[Path, list[dict]], str],
) -> None:
    """Dispatch one document to its parser path: pymupdf, hybrid, or full mineru.

    This is the single seam for Parser Routing -> ingest. Each path is selected
    here and its implementation lives in this module (or is injected), so the full
    Multimodal Ingest flow is readable in one place. The PDF text helpers are
    injected (to_markdown, recover_text) to keep this module free of pymupdf.
    """
    use_pymupdf = parser == PYMUPDF and is_pdf
    use_hybrid = parser == HYBRID and is_pdf

    if use_pymupdf:
        content_list = to_markdown(file_path)
        if not content_list:
            raise RuntimeError(
                f"PyMuPDF found no text layer in {file_path.name}; it may be a scanned "
                "PDF. Use PARSER=mineru for OCR."
            )
        await insert_text_content_list(rag, file_path, content_list)
    elif use_hybrid:
        await ingest_mineru_with_recovery(
            rag,
            file_path,
            output_dir,
            runtime.parse_method,
            runtime.mineru_device,
            recover_text,
        )
    else:
        await rag.process_document_complete(
            file_path=str(file_path),
            output_dir=str(output_dir),
            parse_method=runtime.parse_method,
            device=runtime.mineru_device,
        )
