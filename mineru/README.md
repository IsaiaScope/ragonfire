
<h3 align="center">MinerU — Multimodal Document Parser</h3>

<p align="center">
  <em>Turns PDFs, Office docs, and images into clean text + tables + equations + cropped image regions.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/MinerU-2-2496ED?logoColor=white" alt="MinerU" />
  <img src="https://img.shields.io/badge/MPS-Apple%20GPU-A2AAAD?logo=apple&logoColor=white" alt="MPS" />
  <img src="https://img.shields.io/badge/PaddleOCR-OCR-D02C2F?logoColor=white" alt="PaddleOCR" />
  <img src="https://img.shields.io/badge/LaTeX-equations-008080?logo=latex&logoColor=white" alt="LaTeX" />
</p>

---

## ⛏️ Role in RagOnFire

MinerU is the **document parser**. Before we can build a knowledge graph from a 50-page paper, we need to know *what is in it*: where the body text is, what the figures depict, which cells belong to which table, which characters form which equation.

MinerU runs layout-detection + OCR + table-recognition + formula-recognition models locally and emits a structured representation that RAG-Anything can feed to the LLM and the embedder.

```
input PDF ─┐
           ▼
    ┌──────────────────────┐
    │  MinerU pipeline     │   on Apple Silicon GPU (MPS)
    │  ─────────────────   │
    │  • layout detect     │
    │  • OCR (if scanned)  │
    │  • table recognise   │
    │  • formula recognise │
    │  • image crop        │
    └──────────┬───────────┘
               ▼
       parsed.md  (clean Markdown)
       images/    (cropped PNGs)
       layout.json (block-level metadata)
```

## 📥 Supported inputs

PDF · DOCX · PPTX · XLSX · JPG · PNG · BMP · TIFF · GIF · WebP · TXT · MD

## 🚀 How RagOnFire uses it

You don't call MinerU directly. RAG-Anything wires it in:

```python
config = RAGAnythingConfig(parser="mineru", parse_method="auto")
rag = RAGAnything(config=config, ...)
await rag.process_document_complete(file_path="paper.pdf", device="mps")
```

Output lands in `~/rag-anything/output/<doc-name>/`:

```
output/paper/
├── paper.md            ← parsed markdown (text + tables + equations)
├── images/             ← cropped figures/charts
│   ├── img-001.png
│   └── ...
└── layout.json         ← every block's bbox, class, page, ordering
```

## 📦 Models

MinerU pulls several layout / OCR / formula models on first use (~5 GB total) from ModelScope or Hugging Face. They land in `~/.mineru/` by default.

| Model | Role | Size |
|-------|------|------|
| `doclayout_yolo` | Detect text/figure/table regions on each page | ~50 MB |
| `pp-ocr-v4` | OCR for scanned / non-textual pages | ~10 MB |
| `tabrecognizer` | Recognise table structure (rows/cols/headers) | ~250 MB |
| `unimernet` | Recognise math formulas (→ LaTeX) | ~1.5 GB |
| `pp-formula` | Formula detection | small |
| weights cache | Various tokenizers, configs | rest |

## 🗄️ Relocate models to external drive (optional)

```bash
mkdir -p /path/to/external/drive/models/{mineru,modelscope,huggingface}

# Tell MinerU + its model hubs where to cache
cat >> ~/rag-anything/.env <<'EOF'
MODELSCOPE_CACHE=/path/to/external/drive/models/modelscope
HF_HOME=/path/to/external/drive/models/huggingface
HF_HUB_CACHE=/path/to/external/drive/models/huggingface/hub
EOF
```

Models download on first ingest, into these dirs.

## ⚙️ Tunables (env vars)

| Env var | What it does | Default |
|---------|--------------|---------|
| `MINERU_DEVICE` | `cpu`, `cuda`, `npu`, or `mps` | `mps` on RagOnFire |
| `MINERU_BACKEND` | `pipeline` (multi-model) or `vlm` (single VLM) | `pipeline` |
| `MODELSCOPE_CACHE` | Where ModelScope weights live | `~/.cache/modelscope` |
| `HF_HOME` | Hugging Face cache root | `~/.cache/huggingface` |

## 🩺 Sanity check

```bash
~/rag-anything/.venv/bin/python -c "
from mineru.cli.common import prepare_env
print('MinerU import OK')
"
```

First real ingest will trigger the model download (one-time).

## ⚡ Speed (rough, Apple Silicon)

| Document | MinerU time (MPS) |
|----------|-------------------|
| 1-page text PDF | 5-10 s |
| 10-page paper with 2-3 figures | 1-2 min |
| 50-page paper with tables + equations | 5-10 min |

MinerU is layout-bound. Each page runs a YOLO-style detector. Throughput scales with GPU speed.

## 📚 Links

- Project: [opendatalab/MinerU](https://github.com/opendatalab/MinerU)
- Paper: [arXiv:2409.18839](https://arxiv.org/abs/2409.18839)
- License: AGPL-3.0
