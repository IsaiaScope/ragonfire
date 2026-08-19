#!/usr/bin/env python3
"""Build the Ollama-backed LLM/vision/embedding callables for one runtime.

These were module-level closures over a global RUNTIME singleton in ingest.py,
which made them impossible to test or reconfigure. The factory binds them to an
explicit IngestRuntime so callers can inject a test runtime instead.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable


@dataclass(frozen=True)
class ModelCallables:
    llm: Callable[..., Any]
    vision: Callable[..., Any]
    embed: Any  # lightrag EmbeddingFunc


def build_model_callables(runtime) -> ModelCallables:
    """Bind LLM/vision/embedding callables to an explicit runtime."""
    import ollama
    from lightrag.llm.ollama import ollama_model_complete, ollama_embed
    from lightrag.utils import EmbeddingFunc

    from extraction_tuning import repair_extraction_result

    # NOTE: do NOT set num_ctx per-request -- qwen2.5-vl asserts in its vision
    # merger when a per-request num_ctx forces a model reload. Set context length
    # at the server via OLLAMA_CONTEXT_LENGTH (lightrag-start.sh) instead.
    options = {"temperature": runtime.extraction_temperature}

    async def llm(prompt, system_prompt=None, history_messages=None, **kwargs):
        pass_through = {
            k: v for k, v in kwargs.items()
            if k not in ("hashing_kv", "model", "options")
        }
        merged_options = {**options, **kwargs.get("options", {})}
        result = await ollama_model_complete(
            prompt,
            system_prompt=system_prompt,
            history_messages=history_messages or [],
            hashing_kv=kwargs.get("hashing_kv"),
            host=runtime.ollama_host,
            timeout=runtime.text_timeout,
            options=merged_options,
            **pass_through,
        )
        return repair_extraction_result(result)

    async def vision(prompt, system_prompt=None, history_messages=None,
                     image_data=None, messages=None, **kwargs):
        """Vision model handles images. Pass image via messages."""
        if messages is None:
            if image_data:
                messages = [{"role": "user", "content": prompt, "images": [image_data]}]
            else:
                messages = [{"role": "user", "content": prompt}]
            if system_prompt:
                messages.insert(0, {"role": "system", "content": system_prompt})
            if history_messages:
                messages = list(history_messages) + messages

        client = ollama.AsyncClient(host=runtime.ollama_host, timeout=runtime.vision_timeout)
        response = await client.chat(
            model=runtime.vision_model,
            messages=messages,
            options=options,
        )
        return response["message"]["content"]

    embed = EmbeddingFunc(
        embedding_dim=runtime.embed_dim,
        max_token_size=8192,
        func=lambda texts: ollama_embed(
            texts, embed_model=runtime.embed_model, host=runtime.ollama_host
        ),
    )

    return ModelCallables(llm=llm, vision=vision, embed=embed)
