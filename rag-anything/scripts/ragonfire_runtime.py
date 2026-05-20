#!/usr/bin/env python3
"""Shared runtime helpers for RagOnFire Python entrypoints."""
from __future__ import annotations

import os
import subprocess
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv


@dataclass(frozen=True)
class IngestRuntime:
    working_dir: str
    output_dir: Path
    ollama_host: str
    llm_model: str
    embed_model: str
    embed_dim: int
    parse_method: str
    parser: str
    mineru_device: str


def load_runtime_env(project_dir: Path) -> None:
    load_dotenv(project_dir / ".env")
    if os.environ.get("POSTGRES_HOST_EXTERNAL"):
        os.environ["POSTGRES_HOST"] = os.environ["POSTGRES_HOST_EXTERNAL"]
    if os.environ.get("POSTGRES_PORT_EXTERNAL"):
        os.environ["POSTGRES_PORT"] = os.environ["POSTGRES_PORT_EXTERNAL"]

    if os.environ.get("POSTGRES_HOST_EXTERNAL"):
        for key in ("LLM_BINDING_HOST", "EMBEDDING_BINDING_HOST"):
            value = os.environ.get(key)
            if value:
                os.environ[key] = value.replace("host.docker.internal", "localhost")

    venv_bin = str(Path(sys.executable).parent)
    if venv_bin not in os.environ.get("PATH", "").split(os.pathsep):
        os.environ["PATH"] = venv_bin + os.pathsep + os.environ.get("PATH", "")


def require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"missing required environment variable: {name}")
    return value


def env_int(name: str, default: str) -> int:
    value = os.environ.get(name, default)
    try:
        return int(value)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be an integer, got {value!r}") from exc


def env_float(name: str, default: str) -> float:
    value = os.environ.get(name, default)
    try:
        return float(value)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be a number, got {value!r}") from exc


def resolve_mineru_device(raw: str, scripts_dir: Path) -> str:
    if raw != "auto":
        return raw
    probe = scripts_dir / "mineru-device.sh"
    try:
        out = subprocess.check_output([str(probe)], text=True, timeout=10).strip()
        return out or "cpu"
    except Exception:
        return "cpu"


def validate_input_file(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    if not resolved.exists():
        raise FileNotFoundError(f"file not found: {resolved}")
    if not resolved.is_file():
        raise RuntimeError(f"input path is not a file: {resolved}")
    return resolved


def check_ollama(host: str) -> None:
    url = host.rstrip("/") + "/api/tags"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            if response.status >= 400:
                raise RuntimeError(f"Ollama returned HTTP {response.status} at {url}")
    except Exception as exc:
        raise RuntimeError(f"Ollama is not reachable at {url}. Run /lightrag-start, then retry.") from exc


def build_runtime(project_dir: Path, scripts_dir: Path) -> IngestRuntime:
    output_dir = Path(os.environ.get("OUTPUT_DIR", str(project_dir / "output")))
    return IngestRuntime(
        working_dir=require_env("WORKING_DIR"),
        output_dir=output_dir,
        ollama_host=os.environ.get("LLM_BINDING_HOST", "http://localhost:11434"),
        llm_model=os.environ.get("LLM_MODEL", "qwen2.5vl:7b"),
        embed_model=os.environ.get("EMBEDDING_MODEL", "bge-m3"),
        embed_dim=env_int("EMBEDDING_DIM", "1024"),
        parse_method=os.environ.get("PARSE_METHOD", "auto"),
        parser=os.environ.get("PARSER", "mineru"),
        mineru_device=resolve_mineru_device(os.environ.get("MINERU_DEVICE", "auto"), scripts_dir),
    )


def lightrag_kwargs() -> dict[str, object]:
    return {
        "kv_storage": os.environ.get("LIGHTRAG_KV_STORAGE", "JsonKVStorage"),
        "vector_storage": os.environ.get("LIGHTRAG_VECTOR_STORAGE", "NanoVectorDBStorage"),
        "graph_storage": os.environ.get("LIGHTRAG_GRAPH_STORAGE", "NetworkXStorage"),
        "doc_status_storage": os.environ.get("LIGHTRAG_DOC_STATUS_STORAGE", "JsonDocStatusStorage"),
        "workspace": os.environ.get("WORKSPACE", os.environ.get("POSTGRES_WORKSPACE", "default")),
        "top_k": env_int("TOP_K", "40"),
        "cosine_threshold": env_float("COSINE_THRESHOLD", "0.2"),
        "chunk_token_size": env_int("CHUNK_SIZE", "1200"),
        "chunk_overlap_token_size": env_int("CHUNK_OVERLAP_SIZE", "100"),
        "embedding_batch_num": env_int("EMBEDDING_BATCH_NUM", "10"),
        "max_parallel_insert": env_int("MAX_PARALLEL_INSERT", "2"),
    }
