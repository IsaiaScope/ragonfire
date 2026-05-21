#!/usr/bin/env python3
"""Render RagOnFire runtime path values into a .env file."""
from __future__ import annotations

import argparse
from pathlib import Path


def runtime_path_updates(
    repo_root: Path,
    *,
    data_dir: Path | None = None,
    ollama_models: Path | None = None,
    pgdata_img_cap: str | None = None,
) -> dict[str, str]:
    data = data_dir or repo_root / "data"
    updates = {
        "RAGONFIRE_REPO_DIR": str(repo_root),
        "RAGONFIRE_DATA_DIR": str(data),
        "INPUT_DIR": str(data / "input"),
        "OUTPUT_DIR": str(data / "output"),
        "WORKING_DIR": str(data / "working"),
        "BACKUPS_DIR": str(data / "backups"),
        "OLLAMA_MODELS": str(ollama_models or Path.home() / ".ollama" / "models"),
        "HF_HOME": str(data / "hf"),
        "MINERU_MODELS_DIR": str(data / "mineru"),
        "PGDATA_IMG": str(data / "pgdata.ext4.img"),
        "HOST_LOGS_DIR": str(data / "logs"),
    }
    if pgdata_img_cap:
        updates["PGDATA_IMG_CAP"] = pgdata_img_cap
    return updates


def apply_updates(env_text: str, updates: dict[str, str]) -> str:
    seen: set[str] = set()
    lines: list[str] = []
    for line in env_text.splitlines():
        key = line.split("=", 1)[0] if "=" in line else None
        if key in updates:
            lines.append(f"{key}={updates[key]}")
            seen.add(key)
        else:
            lines.append(line)

    missing = [key for key in updates if key not in seen]
    if missing:
        if lines and lines[-1] != "":
            lines.append("")
        lines.append("# Paths stamped by render_env.py")
        for key in missing:
            lines.append(f"{key}={updates[key]}")
    return "\n".join(lines) + "\n"


def render_env_file(env_path: Path, updates: dict[str, str]) -> None:
    env_path.write_text(apply_updates(env_path.read_text(), updates))


def parse_key_value(raw: str) -> tuple[str, str]:
    if "=" not in raw:
        raise ValueError(f"expected KEY=VALUE, got {raw!r}")
    key, value = raw.split("=", 1)
    if not key:
        raise ValueError(f"expected non-empty key in {raw!r}")
    return key, value


def main() -> int:
    parser = argparse.ArgumentParser(description="Stamp RagOnFire runtime paths into a .env file")
    parser.add_argument("env_file", type=Path)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--data-dir", type=Path)
    parser.add_argument("--ollama-models", type=Path)
    parser.add_argument("--pgdata-img-cap")
    parser.add_argument("--set", dest="overrides", action="append", default=[], metavar="KEY=VALUE")
    args = parser.parse_args()

    updates = runtime_path_updates(
        args.repo_root.resolve(),
        data_dir=args.data_dir.resolve() if args.data_dir else None,
        ollama_models=args.ollama_models.expanduser().resolve() if args.ollama_models else None,
        pgdata_img_cap=args.pgdata_img_cap,
    )
    for raw in args.overrides:
        try:
            key, value = parse_key_value(raw)
        except ValueError as exc:
            parser.error(str(exc))
        updates[key] = value
    render_env_file(args.env_file, updates)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
