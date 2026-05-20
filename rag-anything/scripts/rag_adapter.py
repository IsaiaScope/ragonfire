#!/usr/bin/env python3
"""Local adapter around LightRAG and RAG-Anything integration points."""
from __future__ import annotations

import sys
import logging
from pathlib import Path
from typing import Callable


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
    """Create a LightRAG instance while shielding callers from import side effects."""
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

    require_private_raganything_interface(rag)
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

    require_private_raganything_interface(rag)
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
