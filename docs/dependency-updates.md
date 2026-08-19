<h3 align="center">Dependency Update Checklist 🔄</h3>

<p align="center">
  <em>The deliberate maintenance pass for refreshing RagOnFire's runtime inputs — Python pins, Docker digests, and the Apache AGE commit.</em>
</p>

<br />

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white" alt="Python" />
  <img src="https://img.shields.io/badge/uv-lockfile-DE5FE9?logo=astral&logoColor=white" alt="uv" />
  <img src="https://img.shields.io/badge/Docker-pinned%20digests-2496ED?logo=docker&logoColor=white" alt="Docker" />
  <img src="https://img.shields.io/badge/Apache_AGE-fixed%20commit-336791?logoColor=white" alt="Apache AGE" />
</p>

> Pairs with [ADR 0006 — Reproducible Runtime Inputs](adr/0006-reproducible-runtime-inputs.md). That ADR says *why* inputs are locked; this checklist is *how* to move them forward on purpose.

---

## 1️⃣ Update direct Python pins

Edit the direct dependency versions in `rag-anything/requirements.txt`.

## 2️⃣ Regenerate the lock

For the runtime Python version:

```bash
uv pip compile --python-version 3.12 rag-anything/requirements.txt -o rag-anything/requirements.lock
```

## 3️⃣ Refresh Docker base image digests

```bash
docker buildx imagetools inspect python:3.12-slim
docker buildx imagetools inspect pgvector/pgvector:pg16
```

Copy the new `sha256:` digests into the `FROM` lines of the two Dockerfiles.

## 4️⃣ Re-pin Apache AGE (only if it changes)

```bash
git ls-remote https://github.com/apache/age.git refs/tags/PG16/v1.5.0-rc0
```

Update `AGE_REF` in `infra/postgres/Dockerfile` to the resolved commit SHA.

## 5️⃣ Verify

```bash
python3 -m py_compile rag-anything/scripts/*.py tests/test_*.py
bash -n rag-anything/bootstrap.sh rag-anything/scripts/*.sh rag-anything/scripts/lib/*.sh infra/os/*.sh infra/postgres/entrypoint-loop.sh tests/*.sh
python3 tests/test_ragonfire_runtime.py
python3 tests/test_ingest_modules.py
bash tests/runtime-helper-test.sh
bash tests/phase1-smoke.sh
```

## 6️⃣ Full ingest confidence

For end-to-end confidence, run the manual `integration-smoke` GitHub Action.

---

<p align="center">
  Bump on purpose, verify before trusting. 🔥
</p>
