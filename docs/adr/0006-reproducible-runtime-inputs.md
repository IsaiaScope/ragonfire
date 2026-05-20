<h3 align="center">ADR 0006 · Reproducible Runtime Inputs 🔒</h3>

<p align="center">
  <em>Lock Python dependencies, pin Docker base images by digest, and build Apache AGE from a fixed commit.</em>
</p>

<br />

<p align="center">
  <img src="https://img.shields.io/badge/status-accepted-2EA043?logoColor=white" alt="status: accepted" />
  <img src="https://img.shields.io/badge/deps-locked-3776AB?logo=python&logoColor=white" alt="deps locked" />
  <img src="https://img.shields.io/badge/images-pinned%20by%20digest-2496ED?logo=docker&logoColor=white" alt="images pinned" />
</p>

---

## 📍 Context

RagOnFire depends on a large Python stack, two Docker base images, and Apache
AGE built from source. Direct dependency pins are not enough to keep installs
repeatable because transitive Python dependencies and floating Docker tags can
change underneath the same source checkout.

## ✅ Decision

Install the host runtime from `rag-anything/requirements.lock`, pin Docker base
images by digest, and build Apache AGE from a fixed commit.

## 🔮 Consequences

Clean installs are more reproducible. Dependency updates become an explicit
maintenance task: regenerate the lock file, refresh Docker digests, verify the
AGE ref, and run the smoke checks.

> 🔧 The how-to for that maintenance task lives in [dependency-updates.md](../dependency-updates.md).

---

<p align="center">
  Same inputs in, same stack out. 🔥
</p>
