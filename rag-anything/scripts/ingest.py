#!/usr/bin/env python3
"""RAG-Anything multimodal ingest using Ollama (qwen2.5-vl 7B + bge-m3).

Usage:
    python scripts/ingest.py <file_path> [--output-dir DIR]
"""
from __future__ import annotations

import argparse
import asyncio
import os
import sys
from pathlib import Path

from dotenv import load_dotenv

PROJECT_DIR = Path(__file__).resolve().parent.parent
load_dotenv(PROJECT_DIR / ".env")

from lightrag.llm.ollama import ollama_model_complete, ollama_embed
from lightrag.utils import EmbeddingFunc
from raganything import RAGAnything, RAGAnythingConfig


WORKING_DIR = os.environ["WORKING_DIR"]
OUTPUT_DIR = os.environ.get("OUTPUT_DIR", str(PROJECT_DIR / "output"))
OLLAMA_HOST = os.environ.get("LLM_BINDING_HOST", "http://localhost:11434")
LLM_MODEL = os.environ.get("LLM_MODEL", "qwen2.5vl:7b")
EMBED_MODEL = os.environ.get("EMBEDDING_MODEL", "bge-m3")
EMBED_DIM = int(os.environ.get("EMBEDDING_DIM", "1024"))
PARSE_METHOD = os.environ.get("PARSE_METHOD", "auto")
PARSER = os.environ.get("PARSER", "mineru")
MINERU_DEVICE = os.environ.get("MINERU_DEVICE", "mps")


async def llm_func(prompt, system_prompt=None, history_messages=None, **kwargs):
    return await ollama_model_complete(
        prompt,
        system_prompt=system_prompt,
        history_messages=history_messages or [],
        hashing_kv=kwargs.get("hashing_kv"),
        host=OLLAMA_HOST,
        model=LLM_MODEL,
        timeout=int(os.environ.get("TIMEOUT", "300")),
        **{k: v for k, v in kwargs.items() if k not in ("hashing_kv",)},
    )


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

    return await ollama_model_complete(
        prompt,
        system_prompt=system_prompt,
        history_messages=history_messages or [],
        hashing_kv=kwargs.get("hashing_kv"),
        host=OLLAMA_HOST,
        model=LLM_MODEL,
        timeout=int(os.environ.get("TIMEOUT", "600")),
        messages=messages,
    )


embed_func = EmbeddingFunc(
    embedding_dim=EMBED_DIM,
    max_token_size=8192,
    func=lambda texts: ollama_embed(texts, embed_model=EMBED_MODEL, host=OLLAMA_HOST),
)


async def ingest(file_path: Path, output_dir: Path) -> None:
    file_path = file_path.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    Path(WORKING_DIR).mkdir(parents=True, exist_ok=True)

    print(f"[ingest] file       : {file_path}")
    print(f"[ingest] storage    : {WORKING_DIR}")
    print(f"[ingest] output     : {output_dir}")
    print(f"[ingest] parser     : {PARSER} (method={PARSE_METHOD}, device={MINERU_DEVICE})")
    print(f"[ingest] llm/vlm    : ollama {LLM_MODEL}")
    print(f"[ingest] embed      : ollama {EMBED_MODEL} ({EMBED_DIM}d)")
    print()

    config = RAGAnythingConfig(
        working_dir=WORKING_DIR,
        parser=PARSER,
        parse_method=PARSE_METHOD,
        enable_image_processing=True,
        enable_table_processing=True,
        enable_equation_processing=True,
    )

    rag = RAGAnything(
        config=config,
        llm_model_func=llm_func,
        vision_model_func=vision_func,
        embedding_func=embed_func,
    )

    await rag.process_document_complete(
        file_path=str(file_path),
        output_dir=str(output_dir),
        parse_method=PARSE_METHOD,
        device=MINERU_DEVICE,
    )

    print(f"\n[ingest] done. KG updated at {WORKING_DIR}")


def main() -> int:
    p = argparse.ArgumentParser(description="RAG-Anything multimodal ingest")
    p.add_argument("file", type=Path, help="Document path (PDF/DOCX/PPTX/XLSX/image)")
    p.add_argument("--output-dir", type=Path, default=Path(OUTPUT_DIR))
    args = p.parse_args()

    if not args.file.exists():
        print(f"[error] file not found: {args.file}", file=sys.stderr)
        return 1

    asyncio.run(ingest(args.file, args.output_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main())
