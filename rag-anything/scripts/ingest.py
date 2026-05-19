#!/usr/bin/env python3
"""RAG-Anything multimodal ingest using Ollama (qwen2.5-vl 7B + bge-m3).

Usage:
    python scripts/ingest.py <file_path> [--output-dir DIR]
"""
from __future__ import annotations

import argparse
import asyncio
import os
import subprocess
import sys
from pathlib import Path

import ollama
from dotenv import load_dotenv

PROJECT_DIR = Path(__file__).resolve().parent.parent
load_dotenv(PROJECT_DIR / ".env")

if os.environ.get("POSTGRES_HOST_EXTERNAL"):
    os.environ["POSTGRES_HOST"] = os.environ["POSTGRES_HOST_EXTERNAL"]
if os.environ.get("POSTGRES_PORT_EXTERNAL"):
    os.environ["POSTGRES_PORT"] = os.environ["POSTGRES_PORT_EXTERNAL"]
if os.environ.get("POSTGRES_HOST_EXTERNAL"):
    for _key in ("LLM_BINDING_HOST", "EMBEDDING_BINDING_HOST"):
        _value = os.environ.get(_key)
        if _value:
            os.environ[_key] = _value.replace("host.docker.internal", "localhost")

_VENV_BIN = str(Path(sys.executable).parent)
if _VENV_BIN not in os.environ.get("PATH", "").split(os.pathsep):
    os.environ["PATH"] = _VENV_BIN + os.pathsep + os.environ.get("PATH", "")

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


def _resolve_mineru_device(raw: str) -> str:
    if raw != "auto":
        return raw
    probe = Path(__file__).resolve().parent / "mineru-device.sh"
    try:
        out = subprocess.check_output([str(probe)], text=True, timeout=10).strip()
        return out or "cpu"
    except Exception:
        return "cpu"


MINERU_DEVICE = _resolve_mineru_device(os.environ.get("MINERU_DEVICE", "auto"))


def _lightrag_kwargs() -> dict[str, object]:
    return {
        "kv_storage": os.environ.get("LIGHTRAG_KV_STORAGE", "JsonKVStorage"),
        "vector_storage": os.environ.get("LIGHTRAG_VECTOR_STORAGE", "NanoVectorDBStorage"),
        "graph_storage": os.environ.get("LIGHTRAG_GRAPH_STORAGE", "NetworkXStorage"),
        "doc_status_storage": os.environ.get("LIGHTRAG_DOC_STATUS_STORAGE", "JsonDocStatusStorage"),
        "workspace": os.environ.get("POSTGRES_WORKSPACE", "default"),
        "top_k": int(os.environ.get("TOP_K", "40")),
        "cosine_threshold": float(os.environ.get("COSINE_THRESHOLD", "0.2")),
        "chunk_token_size": int(os.environ.get("CHUNK_SIZE", "1200")),
        "chunk_overlap_token_size": int(os.environ.get("CHUNK_OVERLAP_SIZE", "100")),
        "embedding_batch_num": int(os.environ.get("EMBEDDING_BATCH_NUM", "10")),
        "max_parallel_insert": int(os.environ.get("MAX_PARALLEL_INSERT", "2")),
    }


async def llm_func(prompt, system_prompt=None, history_messages=None, **kwargs):
    pass_through = {
        k: v for k, v in kwargs.items()
        if k not in ("hashing_kv", "model")
    }
    return await ollama_model_complete(
        prompt,
        system_prompt=system_prompt,
        history_messages=history_messages or [],
        hashing_kv=kwargs.get("hashing_kv"),
        host=OLLAMA_HOST,
        timeout=int(os.environ.get("TIMEOUT", "300")),
        **pass_through,
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

    client = ollama.AsyncClient(
        host=OLLAMA_HOST,
        timeout=int(os.environ.get("TIMEOUT", "600")),
    )
    response = await client.chat(model=LLM_MODEL, messages=messages)
    return response["message"]["content"]


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
    print(f"[ingest] kv         : {os.environ.get('LIGHTRAG_KV_STORAGE', '(default)')}")
    print(f"[ingest] vector     : {os.environ.get('LIGHTRAG_VECTOR_STORAGE', '(default)')}")
    print(f"[ingest] graph      : {os.environ.get('LIGHTRAG_GRAPH_STORAGE', '(default)')}")
    print(f"[ingest] doc-status : {os.environ.get('LIGHTRAG_DOC_STATUS_STORAGE', '(default)')}")
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

    argv = sys.argv[:]
    try:
        sys.argv = [sys.argv[0]]
        from lightrag import LightRAG
        from lightrag.kg.shared_storage import initialize_pipeline_status

        lightrag = LightRAG(
            working_dir=WORKING_DIR,
            llm_model_func=llm_func,
            llm_model_name=LLM_MODEL,
            embedding_func=embed_func,
            **_lightrag_kwargs(),
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
