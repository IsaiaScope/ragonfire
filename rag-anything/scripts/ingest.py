#!/usr/bin/env python3
"""RAG-Anything multimodal ingest using Ollama (qwen2.5-vl 7B + bge-m3).

Usage:
    python scripts/ingest.py <file_path> [--output-dir DIR]
"""
from __future__ import annotations

from native_warning_filter import install_native_warning_filter

install_native_warning_filter()

import argparse
import asyncio
import logging
import os
import re
import sys
from pathlib import Path

import ollama

PROJECT_DIR = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = Path(__file__).resolve().parent
from ragonfire_runtime import (
    build_runtime,
    check_ollama,
    env_float,
    lightrag_kwargs,
    load_runtime_env,
    validate_input_file,
)
from extraction_tuning import install_extraction_tuning, repair_extraction_result
from parser_routing import route_parser
from rag_adapter import (
    create_lightrag,
    create_raganything,
    ingest_mineru_with_recovery,
    initialize_lightrag,
    insert_text_content_list,
)

load_runtime_env(PROJECT_DIR)

from lightrag.llm.ollama import ollama_model_complete, ollama_embed
from lightrag.utils import EmbeddingFunc
from raganything import RAGAnythingConfig


RUNTIME = build_runtime(PROJECT_DIR, SCRIPTS_DIR)
logging.basicConfig(level=logging.INFO, format="[ingest] %(message)s")
LOGGER = logging.getLogger("ragonfire.ingest")

# LightRAG's wrapper does not set temperature, so Ollama falls back to 0.8 and
# extraction is non-deterministic. Force deterministic for reliable recall.
# NOTE: do NOT set num_ctx per-request -- qwen2.5-vl asserts in its vision
# merger when a per-request num_ctx forces a model reload. Set context length at
# the server via OLLAMA_CONTEXT_LENGTH (lightrag-start.sh) instead.
EXTRACTION_TEMPERATURE = env_float("EXTRACTION_TEMPERATURE", "0.0")
OLLAMA_OPTIONS = {"temperature": EXTRACTION_TEMPERATURE}


async def llm_func(prompt, system_prompt=None, history_messages=None, **kwargs):
    pass_through = {
        k: v for k, v in kwargs.items()
        if k not in ("hashing_kv", "model", "options")
    }
    merged_options = {**OLLAMA_OPTIONS, **kwargs.get("options", {})}
    result = await ollama_model_complete(
        prompt,
        system_prompt=system_prompt,
        history_messages=history_messages or [],
        hashing_kv=kwargs.get("hashing_kv"),
        host=RUNTIME.ollama_host,
        timeout=int(os.environ.get("TIMEOUT", "300")),
        options=merged_options,
        **pass_through,
    )
    return repair_extraction_result(result)


async def vision_func(prompt, system_prompt=None, history_messages=None, image_data=None, messages=None, **kwargs):
    """Vision model handles images. Pass image via messages."""
    if messages is None:
        if image_data:
            msg = [{"role": "user", "content": prompt, "images": [image_data]}]
        else:
            msg = [{"role": "user", "content": prompt}]
        if system_prompt:
            msg.insert(0, {"role": "system", "content": system_prompt})
        if history_messages:
            msg = (history_messages or []) + msg
        messages = msg

    client = ollama.AsyncClient(
        host=RUNTIME.ollama_host,
        timeout=int(os.environ.get("TIMEOUT", "600")),
    )
    response = await client.chat(
        model=RUNTIME.vision_model,
        messages=messages,
        options=OLLAMA_OPTIONS,
    )
    return response["message"]["content"]


embed_func = EmbeddingFunc(
    embedding_dim=RUNTIME.embed_dim,
    max_token_size=8192,
    func=lambda texts: ollama_embed(texts, embed_model=RUNTIME.embed_model, host=RUNTIME.ollama_host),
)


def _pymupdf_content_list(pdf_path: Path) -> list[dict]:
    """Extract a PDF to structured markdown via pymupdf4llm.

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


def _recover_dropped_text(pdf_path: Path, content_list: list[dict]) -> str:
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


async def ingest(file_path: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    Path(RUNTIME.working_dir).mkdir(parents=True, exist_ok=True)
    check_ollama(RUNTIME.ollama_host)

    is_pdf = file_path.suffix.lower() == ".pdf"
    parser = route_parser(file_path, RUNTIME.parser)
    use_pymupdf = parser == "pymupdf" and is_pdf
    use_hybrid = parser == "hybrid" and is_pdf

    LOGGER.info("file       : %s", file_path)
    LOGGER.info("kv         : %s", os.environ.get("LIGHTRAG_KV_STORAGE", "(default)"))
    LOGGER.info("vector     : %s", os.environ.get("LIGHTRAG_VECTOR_STORAGE", "(default)"))
    LOGGER.info("graph      : %s", os.environ.get("LIGHTRAG_GRAPH_STORAGE", "(default)"))
    LOGGER.info("doc-status : %s", os.environ.get("LIGHTRAG_DOC_STATUS_STORAGE", "(default)"))
    LOGGER.info("storage    : %s", RUNTIME.working_dir)
    LOGGER.info("output     : %s", output_dir)
    _parser_label = parser if parser == RUNTIME.parser else f"{RUNTIME.parser}->{parser}"
    LOGGER.info(
        "parser     : %s (method=%s, device=%s)",
        _parser_label,
        RUNTIME.parse_method,
        RUNTIME.mineru_device,
    )
    LOGGER.info("extract    : ollama %s", RUNTIME.extraction_model)
    LOGGER.info("vision     : ollama %s", RUNTIME.vision_model)
    LOGGER.info("embed      : ollama %s (%sd)", RUNTIME.embed_model, RUNTIME.embed_dim)

    config = RAGAnythingConfig(
        # pymupdf is our own text path, not a RAG-Anything parser; pass a valid
        # parser name for config (it is unused when use_pymupdf bypasses it).
        working_dir=RUNTIME.working_dir,
        parser="mineru" if (use_pymupdf or use_hybrid) else parser,
        parse_method=RUNTIME.parse_method,
        enable_image_processing=RUNTIME.enable_image,
        enable_table_processing=RUNTIME.enable_table,
        enable_equation_processing=RUNTIME.enable_equation,
    )

    install_extraction_tuning()
    lightrag = create_lightrag(RUNTIME, embed_func, llm_func, lightrag_kwargs())
    await initialize_lightrag(lightrag)
    rag = create_raganything(lightrag, config, llm_func, vision_func, embed_func)

    if use_pymupdf:
        content_list = _pymupdf_content_list(file_path)
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
            RUNTIME.parse_method,
            RUNTIME.mineru_device,
            _recover_dropped_text,
        )
    else:
        await rag.process_document_complete(
            file_path=str(file_path),
            output_dir=str(output_dir),
            parse_method=RUNTIME.parse_method,
            device=RUNTIME.mineru_device,
        )

    LOGGER.info("done. KG updated at %s", RUNTIME.working_dir)


def main() -> int:
    p = argparse.ArgumentParser(description="RAG-Anything multimodal ingest")
    p.add_argument("file", type=Path, help="Document path (PDF/DOCX/PPTX/XLSX/image)")
    p.add_argument("--output-dir", type=Path, default=RUNTIME.output_dir)
    args = p.parse_args()

    try:
        file_path = validate_input_file(args.file)
        asyncio.run(ingest(file_path, args.output_dir.expanduser().resolve()))
    except Exception as exc:
        LOGGER.error("FATAL: %s", exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
