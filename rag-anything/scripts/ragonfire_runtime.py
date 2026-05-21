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


def quiet_dependency_warnings() -> None:
    """Silence known noisy native-library warnings that do not affect ingest."""
    os.environ.setdefault("ORT_LOG_SEVERITY_LEVEL", "3")
    try:
        import onnxruntime
    except Exception:
        return
    onnxruntime.set_default_logger_severity(int(os.environ["ORT_LOG_SEVERITY_LEVEL"]))


@dataclass(frozen=True)
class IngestRuntime:
    working_dir: str
    output_dir: Path
    ollama_host: str
    extraction_model: str
    vision_model: str
    embed_model: str
    embed_dim: int
    parse_method: str
    parser: str
    mineru_device: str
    enable_image: bool
    enable_table: bool
    enable_equation: bool
    text_timeout: int
    vision_timeout: int
    extraction_temperature: float
    extraction_tuning: bool


def load_runtime_env(project_dir: Path) -> None:
    quiet_dependency_warnings()
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


def env_bool(name: str, default: str = "true") -> bool:
    return os.environ.get(name, default).strip().lower() in ("1", "true", "yes", "on")


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
    llm_model = os.environ.get("LLM_MODEL", "qwen2.5vl:7b")
    return IngestRuntime(
        working_dir=require_env("WORKING_DIR"),
        output_dir=output_dir,
        ollama_host=os.environ.get("LLM_BINDING_HOST", "http://localhost:11434"),
        # Split models: text extraction needs a model that follows LightRAG's
        # tuple format and survives long entity-type prompts. qwen2.5vl (vision)
        # mangles the `<|>` delimiter and asserts in M-RoPE on long prompts, so
        # a text model extracts and the VL model is kept for images only.
        extraction_model=os.environ.get("EXTRACTION_MODEL", "qwen2.5:7b"),
        vision_model=os.environ.get("VISION_MODEL", llm_model),
        embed_model=os.environ.get("EMBEDDING_MODEL", "bge-m3"),
        embed_dim=env_int("EMBEDDING_DIM", "1024"),
        parse_method=os.environ.get("PARSE_METHOD", "auto"),
        parser=os.environ.get("PARSER", "auto"),
        mineru_device=resolve_mineru_device(os.environ.get("MINERU_DEVICE", "auto"), scripts_dir),
        # Multimodal toggles (default on). Image captioning runs the vision model
        # per image; disable for text-only docs (CVs, contracts) where a photo
        # adds nothing and the VL call dominates runtime.
        enable_image=env_bool("ENABLE_IMAGE_PROCESSING", "true"),
        enable_table=env_bool("ENABLE_TABLE_PROCESSING", "true"),
        enable_equation=env_bool("ENABLE_EQUATION_PROCESSING", "true"),
        # Timeouts: TIMEOUT drives text extraction; vision falls back to TIMEOUT
        # then 600s (vision calls are slower). Both centralized here so callers
        # never read os.environ for timeout config.
        text_timeout=env_int("TIMEOUT", "300"),
        vision_timeout=env_int("VISION_TIMEOUT", os.environ.get("TIMEOUT", "600")),
        # LightRAG's wrapper does not set temperature, so Ollama falls back to 0.8
        # and extraction is non-deterministic. Force deterministic for recall.
        extraction_temperature=env_float("EXTRACTION_TEMPERATURE", "0.0"),
        extraction_tuning=env_bool("EXTRACTION_TUNING", "1"),
    )


# LightRAG's default extraction prompt biases to org/person/geo only. This wider
# set makes skills/tech/dates first-class entities. It is a guide, not a ceiling:
# the extraction rules let the model coin its own type when none of these fit, so
# new document domains are handled without editing this list.
DEFAULT_ENTITY_TYPES = [
    "person", "organization", "geo", "event",
    "concept", "category", "technology", "tool",
    "skill", "product", "role", "date",
    "certification", "degree", "language",
]


async def identity_rerank(query: str, documents: list[dict], top_n: int | None = None, **_kwargs) -> list[dict]:
    """Satisfy LightRAG's rerank seam while preserving original chunk order."""
    return documents


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
        "rerank_model_func": identity_rerank,
        "min_rerank_score": env_float("MIN_RERANK_SCORE", "0.0"),
        # Gleaning rounds re-prompt each chunk for missed entities. Each round is
        # an extra LLM call per chunk, so it dominates runtime. 1 balances recall
        # vs speed; raise to 2 for max recall on dense docs (slower).
        "entity_extract_max_gleaning": env_int("ENTITY_EXTRACT_MAX_GLEANING", "1"),
        "addon_params": {"entity_types": DEFAULT_ENTITY_TYPES},
    }
