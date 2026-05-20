#!/usr/bin/env python3
"""RAG-Anything multimodal ingest using Ollama (qwen2.5-vl 7B + bge-m3).

Usage:
    python scripts/ingest.py <file_path> [--output-dir DIR]
"""
from __future__ import annotations

import argparse
import asyncio
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
    lightrag_kwargs,
    load_runtime_env,
    validate_input_file,
)

load_runtime_env(PROJECT_DIR)

from lightrag.llm.ollama import ollama_model_complete, ollama_embed
from lightrag.utils import EmbeddingFunc
from raganything import RAGAnything, RAGAnythingConfig


RUNTIME = build_runtime(PROJECT_DIR, SCRIPTS_DIR)
_HTML_BREAK_RE = re.compile(r"</?br\s*/?>", re.IGNORECASE)
# qwen2.5-vl drops the closing `)` on entity/relationship tuples: emits
# `("entity"<|>...">##` instead of `("entity"<|>...")##`. LightRAG's parser
# uses `\((.*)\)` to extract tuple bodies, so missing `)` discards all records.
_MISSING_CLOSE_PAREN_RE = re.compile(r'">(\s*(?:##|<\|COMPLETE\|>))')


async def llm_func(prompt, system_prompt=None, history_messages=None, **kwargs):
    pass_through = {
        k: v for k, v in kwargs.items()
        if k not in ("hashing_kv", "model")
    }
    result = await ollama_model_complete(
        prompt,
        system_prompt=system_prompt,
        history_messages=history_messages or [],
        hashing_kv=kwargs.get("hashing_kv"),
        host=RUNTIME.ollama_host,
        timeout=int(os.environ.get("TIMEOUT", "300")),
        **pass_through,
    )
    if isinstance(result, str):
        result = _HTML_BREAK_RE.sub("", result)
        result = _MISSING_CLOSE_PAREN_RE.sub(r'")\1', result)
    return result


async def vision_func(prompt, system_prompt=None, history_messages=None, image_data=None, messages=None, **kwargs):
    """qwen2.5-vl handles both text and vision. Pass image via messages."""
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
    response = await client.chat(model=RUNTIME.llm_model, messages=messages)
    return response["message"]["content"]


embed_func = EmbeddingFunc(
    embedding_dim=RUNTIME.embed_dim,
    max_token_size=8192,
    func=lambda texts: ollama_embed(texts, embed_model=RUNTIME.embed_model, host=RUNTIME.ollama_host),
)


async def ingest(file_path: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    Path(RUNTIME.working_dir).mkdir(parents=True, exist_ok=True)
    check_ollama(RUNTIME.ollama_host)

    print(f"[ingest] file       : {file_path}")
    print(f"[ingest] kv         : {os.environ.get('LIGHTRAG_KV_STORAGE', '(default)')}")
    print(f"[ingest] vector     : {os.environ.get('LIGHTRAG_VECTOR_STORAGE', '(default)')}")
    print(f"[ingest] graph      : {os.environ.get('LIGHTRAG_GRAPH_STORAGE', '(default)')}")
    print(f"[ingest] doc-status : {os.environ.get('LIGHTRAG_DOC_STATUS_STORAGE', '(default)')}")
    print(f"[ingest] storage    : {RUNTIME.working_dir}")
    print(f"[ingest] output     : {output_dir}")
    print(f"[ingest] parser     : {RUNTIME.parser} (method={RUNTIME.parse_method}, device={RUNTIME.mineru_device})")
    print(f"[ingest] llm/vlm    : ollama {RUNTIME.llm_model}")
    print(f"[ingest] embed      : ollama {RUNTIME.embed_model} ({RUNTIME.embed_dim}d)")
    print()

    config = RAGAnythingConfig(
        working_dir=RUNTIME.working_dir,
        parser=RUNTIME.parser,
        parse_method=RUNTIME.parse_method,
        enable_image_processing=True,
        enable_table_processing=True,
        enable_equation_processing=True,
    )

    argv = sys.argv[:]
    try:
        sys.argv = [sys.argv[0]]
        from lightrag import LightRAG
        from lightrag.kg.shared_storage import initialize_pipeline_status

        lightrag = LightRAG(
            working_dir=RUNTIME.working_dir,
            llm_model_func=llm_func,
            llm_model_name=RUNTIME.llm_model,
            embedding_func=embed_func,
            **lightrag_kwargs(),
        )
    finally:
        sys.argv = argv

    await lightrag.initialize_storages()
    await initialize_pipeline_status()

    rag = RAGAnything(
        lightrag=lightrag,
        config=config,
        llm_model_func=llm_func,
        vision_model_func=vision_func,
        embedding_func=embed_func,
    )

    await rag.process_document_complete(
        file_path=str(file_path),
        output_dir=str(output_dir),
        parse_method=RUNTIME.parse_method,
        device=RUNTIME.mineru_device,
    )

    print(f"\n[ingest] done. KG updated at {RUNTIME.working_dir}")


def main() -> int:
    p = argparse.ArgumentParser(description="RAG-Anything multimodal ingest")
    p.add_argument("file", type=Path, help="Document path (PDF/DOCX/PPTX/XLSX/image)")
    p.add_argument("--output-dir", type=Path, default=RUNTIME.output_dir)
    args = p.parse_args()

    try:
        file_path = validate_input_file(args.file)
        asyncio.run(ingest(file_path, args.output_dir.expanduser().resolve()))
    except Exception as exc:
        print(f"[ingest] FATAL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
