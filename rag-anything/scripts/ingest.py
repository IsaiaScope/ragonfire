#!/usr/bin/env python3
"""RAG-Anything multimodal ingest using Ollama (qwen2.5-vl 7B + bge-m3).

Usage:
    python scripts/ingest.py <file_path> [--output-dir DIR]
"""
from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = Path(__file__).resolve().parent

from native_warning_filter import install_native_warning_filter
from ragonfire_runtime import (
    build_runtime,
    check_ollama,
    lightrag_kwargs,
    load_runtime_env,
    validate_input_file,
)
from parser_routing import route_parser
from pdf_text import pdf_to_markdown_content, recover_dropped_text
from rag_adapter import (
    create_lightrag,
    create_raganything,
    create_raganything_config,
    ingest_document,
    initialize_lightrag,
)

logging.basicConfig(level=logging.INFO, format="[ingest] %(message)s")
LOGGER = logging.getLogger("ragonfire.ingest")


async def build_rag(runtime, callables, parser: str, is_pdf: bool, kwargs: dict):
    """Construct the initialized RAG-Anything instance for one ingest.

    This is the seam ingest() builds its pipeline through. The default wires the
    real LightRAG + RAG-Anything stack; tests inject a fake builder so the whole
    ingest() orchestration can run without a live stack.
    """
    config = create_raganything_config(runtime, parser, is_pdf)
    lightrag = create_lightrag(runtime, callables.embed, callables.llm, kwargs)
    await initialize_lightrag(lightrag)
    return create_raganything(lightrag, config, callables.llm, callables.vision, callables.embed)


async def ingest(
    runtime,
    callables,
    file_path: Path,
    output_dir: Path,
    *,
    rag_builder=build_rag,
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    Path(runtime.working_dir).mkdir(parents=True, exist_ok=True)
    check_ollama(runtime.ollama_host)

    is_pdf = file_path.suffix.lower() == ".pdf"
    parser = route_parser(file_path, runtime.parser)
    kwargs = lightrag_kwargs()

    LOGGER.info("file       : %s", file_path)
    LOGGER.info("kv         : %s", kwargs["kv_storage"])
    LOGGER.info("vector     : %s", kwargs["vector_storage"])
    LOGGER.info("graph      : %s", kwargs["graph_storage"])
    LOGGER.info("doc-status : %s", kwargs["doc_status_storage"])
    LOGGER.info("storage    : %s", runtime.working_dir)
    LOGGER.info("output     : %s", output_dir)
    _parser_label = parser if parser == runtime.parser else f"{runtime.parser}->{parser}"
    LOGGER.info(
        "parser     : %s (method=%s, device=%s)",
        _parser_label,
        runtime.parse_method,
        runtime.mineru_device,
    )
    LOGGER.info("extract    : ollama %s", runtime.extraction_model)
    LOGGER.info("vision     : ollama %s", runtime.vision_model)
    LOGGER.info("embed      : ollama %s (%sd)", runtime.embed_model, runtime.embed_dim)

    rag = await rag_builder(runtime, callables, parser, is_pdf, kwargs)

    await ingest_document(
        rag,
        parser,
        is_pdf,
        file_path,
        output_dir,
        runtime,
        to_markdown=pdf_to_markdown_content,
        recover_text=recover_dropped_text,
    )

    LOGGER.info("done. KG updated at %s", runtime.working_dir)


def main() -> int:
    install_native_warning_filter()
    load_runtime_env(PROJECT_DIR)
    runtime = build_runtime(PROJECT_DIR, SCRIPTS_DIR)

    from model_callables import build_model_callables

    callables = build_model_callables(runtime)

    p = argparse.ArgumentParser(description="RAG-Anything multimodal ingest")
    p.add_argument("file", type=Path, help="Document path (PDF/DOCX/PPTX/XLSX/image)")
    p.add_argument("--output-dir", type=Path, default=runtime.output_dir)
    args = p.parse_args()

    try:
        file_path = validate_input_file(args.file)
        asyncio.run(ingest(runtime, callables, file_path, args.output_dir.expanduser().resolve()))
    except Exception as exc:
        LOGGER.error("FATAL: %s", exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
