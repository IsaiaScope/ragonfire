#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import importlib.util
import re
import sys
import tempfile
import types
import unittest
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "rag-anything" / "scripts"

if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))


def load_script_module(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


class ParserRoutingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_script_module("parser_routing")

    def test_non_auto_parser_is_preserved(self) -> None:
        parser = self.module.route_parser(Path("doc.pdf"), "mineru")
        self.assertEqual(parser, "mineru")

    def test_non_pdf_auto_parser_is_preserved(self) -> None:
        parser = self.module.route_parser(Path("doc.docx"), "auto")
        self.assertEqual(parser, "auto")

    def test_scanned_pdf_routes_to_mineru(self) -> None:
        parser = self.module.route_parser(
            Path("doc.pdf"),
            "auto",
            has_text_layer=lambda _path: False,
            max_image_coverage=lambda _path: 0.0,
        )
        self.assertEqual(parser, "mineru")

    def test_digital_pdf_with_figures_routes_to_hybrid(self) -> None:
        parser = self.module.route_parser(
            Path("doc.pdf"),
            "auto",
            has_text_layer=lambda _path: True,
            max_image_coverage=lambda _path: 0.25,
        )
        self.assertEqual(parser, "hybrid")

    def test_text_pdf_routes_to_pymupdf(self) -> None:
        parser = self.module.route_parser(
            Path("doc.pdf"),
            "auto",
            has_text_layer=lambda _path: True,
            max_image_coverage=lambda _path: 0.01,
        )
        self.assertEqual(parser, "pymupdf")


class ExtractionTuningTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_script_module("extraction_tuning")

    def test_repairs_html_breaks_and_missing_tuple_parens(self) -> None:
        raw = '("entity"<|>"Python"<|>"technology"<|>"Language."><br>##'
        repaired = self.module.repair_extraction_result(raw)
        self.assertEqual(repaired, '("entity"<|>"Python"<|>"technology"<|>"Language.")##')

    def test_non_string_results_pass_through(self) -> None:
        value = {"response": "ok"}
        self.assertIs(self.module.repair_extraction_result(value), value)

    def test_install_is_noop_when_disabled(self) -> None:
        # Disabled path returns before importing lightrag, so no stub is needed.
        self.module.install_extraction_tuning(False)

    def test_install_injects_rules_when_enabled(self) -> None:
        anchor = "######################\n---Examples---"
        fake_prompt = types.ModuleType("lightrag.prompt")
        fake_prompt.PROMPTS = {
            "entity_extraction": f"head\n{anchor}\ntail",
            "entity_extraction_examples": [],
        }
        fake_lightrag = types.ModuleType("lightrag")
        fake_lightrag.prompt = fake_prompt
        saved = {k: sys.modules.get(k) for k in ("lightrag", "lightrag.prompt")}
        sys.modules["lightrag"] = fake_lightrag
        sys.modules["lightrag.prompt"] = fake_prompt
        try:
            self.module.install_extraction_tuning(True)
            self.assertIn("---Extraction rules---", fake_prompt.PROMPTS["entity_extraction"])
            self.assertEqual(len(fake_prompt.PROMPTS["entity_extraction_examples"]), 1)
        finally:
            for key, value in saved.items():
                if value is None:
                    sys.modules.pop(key, None)
                else:
                    sys.modules[key] = value


class RagAdapterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_script_module("rag_adapter")

    def test_private_interface_check_accepts_expected_methods(self) -> None:
        class FakeRag:
            def _ensure_lightrag_initialized(self):
                pass

            def _generate_content_based_doc_id(self, _content):
                return "doc"

            def _process_multimodal_content(self, _items, _path, _doc_id):
                pass

        self.module.require_private_raganything_interface(FakeRag())

    def test_private_interface_check_fails_clearly(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "private interface changed"):
            self.module.require_private_raganything_interface(object())


class IngestDispatchTests(unittest.TestCase):
    """ingest_document is the single Parser Routing -> ingest seam."""

    def setUp(self) -> None:
        self.module = load_script_module("rag_adapter")
        self.runtime = SimpleNamespace(parse_method="auto", mineru_device="cpu")

    def _dispatch(self, parser: str, *, is_pdf: bool = True, to_markdown=None):
        calls: list[str] = []

        async def fake_insert(rag, file_path, content_list):
            calls.append("pymupdf")
            return "doc"

        async def fake_hybrid(rag, file_path, output_dir, parse_method, device, recover):
            calls.append("hybrid")

        class FakeRag:
            async def process_document_complete(self, **_kwargs):
                calls.append("mineru")

        self.module.insert_text_content_list = fake_insert
        self.module.ingest_mineru_with_recovery = fake_hybrid

        asyncio.run(
            self.module.ingest_document(
                FakeRag(),
                parser,
                is_pdf,
                Path("doc.pdf"),
                Path("/tmp/out"),
                self.runtime,
                to_markdown=to_markdown or (lambda _p: [{"type": "text", "text": "x"}]),
                recover_text=lambda _p, _c: "",
            )
        )
        return calls

    def test_pymupdf_path_inserts_text(self) -> None:
        self.assertEqual(self._dispatch("pymupdf"), ["pymupdf"])

    def test_hybrid_path_runs_recovery(self) -> None:
        self.assertEqual(self._dispatch("hybrid"), ["hybrid"])

    def test_mineru_path_runs_full_pipeline(self) -> None:
        self.assertEqual(self._dispatch("mineru"), ["mineru"])

    def test_non_pdf_pymupdf_falls_through_to_mineru(self) -> None:
        # parser may say pymupdf, but a non-pdf can't use the text path.
        self.assertEqual(self._dispatch("pymupdf", is_pdf=False), ["mineru"])

    def test_empty_pymupdf_content_raises(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "no text layer"):
            self._dispatch("pymupdf", to_markdown=lambda _p: [])


class IngestPipelineTests(unittest.TestCase):
    """End-to-end wiring of ingest(): route -> rag_builder seam -> dispatch.

    Exercises the orchestration that unit tests skip, using an injected fake
    builder + fake rag so no live Ollama/LightRAG/Postgres stack is required.
    """

    def setUp(self) -> None:
        # ragonfire_runtime imports python-dotenv at module load; stub it so the
        # pipeline test runs without the optional dep (matches test_ragonfire_runtime).
        sys.modules.setdefault(
            "dotenv", types.SimpleNamespace(load_dotenv=lambda *_a, **_k: None)
        )
        self.module = load_script_module("ingest")
        # ingest() probes Ollama before building; stub it out (no network).
        self.module.check_ollama = lambda _host: None
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def _runtime(self, parser: str) -> SimpleNamespace:
        return SimpleNamespace(
            working_dir=str(self.tmp / "kg"),
            output_dir=self.tmp / "out",
            ollama_host="http://localhost:11434",
            parser=parser,
            parse_method="auto",
            mineru_device="cpu",
            extraction_model="qwen2.5:7b",
            vision_model="qwen2.5vl:7b",
            embed_model="bge-m3",
            embed_dim=1024,
        )

    def test_ingest_routes_builds_then_dispatches(self) -> None:
        calls: list = []

        class FakeRag:
            async def process_document_complete(self, **_kwargs):
                calls.append("dispatch:mineru")

        async def fake_builder(runtime, callables, parser, is_pdf, kwargs):
            calls.append(("build", parser, is_pdf))
            return FakeRag()

        callables = SimpleNamespace(llm=None, vision=None, embed=None)
        asyncio.run(
            self.module.ingest(
                self._runtime("mineru"),
                callables,
                self.tmp / "doc.pdf",
                self.tmp / "out",
                rag_builder=fake_builder,
            )
        )

        # builder receives the routed parser + pdf flag, then dispatch runs.
        self.assertEqual(calls, [("build", "mineru", True), "dispatch:mineru"])

    def test_ingest_creates_working_and_output_dirs(self) -> None:
        async def fake_builder(*_args, **_kwargs):
            class FakeRag:
                async def process_document_complete(self, **_kwargs):
                    pass

            return FakeRag()

        out_dir = self.tmp / "fresh-out"
        callables = SimpleNamespace(llm=None, vision=None, embed=None)
        asyncio.run(
            self.module.ingest(
                self._runtime("mineru"),
                callables,
                self.tmp / "doc.pdf",
                out_dir,
                rag_builder=fake_builder,
            )
        )

        self.assertTrue(out_dir.is_dir())
        self.assertTrue((self.tmp / "kg").is_dir())


class DataRootLayoutConsistencyTests(unittest.TestCase):
    """The Data Root subdir layout is spelled in two languages: render_env.py
    (stamps .env at init) and lib/ragonfire.sh (runtime fallbacks). They cannot
    share a literal across the Python<->bash seam, so this test locks them
    together: drift in either fails CI instead of silently desyncing.
    """

    # Keys whose value is derived from the Data Root. RAGONFIRE_DATA_DIR itself,
    # OLLAMA_MODELS (home-based) and bash-only vars (LOG_DIR, RF_OS) are excluded.
    DATA_DERIVED_KEYS = {
        "INPUT_DIR",
        "OUTPUT_DIR",
        "WORKING_DIR",
        "BACKUPS_DIR",
        "HF_HOME",
        "MINERU_MODELS_DIR",
        "PGDATA_IMG",
        "HOST_LOGS_DIR",
    }

    def _python_layout(self) -> dict[str, str]:
        render_env = load_script_module("render_env")
        updates = render_env.runtime_path_updates(Path("/repo"), data_dir=Path("/D"))
        return {
            key: updates[key][len("/D/"):]
            for key in self.DATA_DERIVED_KEYS
            if updates[key].startswith("/D/")
        }

    def _bash_layout(self) -> dict[str, str]:
        lib = (SCRIPTS / "lib" / "ragonfire.sh").read_text()
        # Match: KEY="${KEY:-$RAGONFIRE_DATA_DIR/suffix}"
        pattern = re.compile(
            r'(\w+)="\$\{\1:-\$RAGONFIRE_DATA_DIR/([^"}]+)\}"'
        )
        found = {key: suffix for key, suffix in pattern.findall(lib)}
        return {k: v for k, v in found.items() if k in self.DATA_DERIVED_KEYS}

    def test_layouts_cover_the_same_keys(self) -> None:
        self.assertEqual(set(self._python_layout()), self.DATA_DERIVED_KEYS)
        self.assertEqual(set(self._bash_layout()), self.DATA_DERIVED_KEYS)

    def test_python_and_bash_agree_on_every_subpath(self) -> None:
        self.assertEqual(self._python_layout(), self._bash_layout())


class RenderEnvTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_script_module("render_env")

    def test_apply_updates_replaces_existing_keys_and_appends_missing(self) -> None:
        text = "RAGONFIRE_DATA_DIR=/old\nPOSTGRES_USER=ragonfire\n"
        updates = {
            "RAGONFIRE_DATA_DIR": "/new/data",
            "INPUT_DIR": "/new/data/input",
        }

        rendered = self.module.apply_updates(text, updates)

        self.assertIn("RAGONFIRE_DATA_DIR=/new/data\n", rendered)
        self.assertIn("POSTGRES_USER=ragonfire\n", rendered)
        self.assertIn("INPUT_DIR=/new/data/input\n", rendered)
        self.assertNotIn("RAGONFIRE_DATA_DIR=/old", rendered)

    def test_runtime_path_updates_use_data_root(self) -> None:
        updates = self.module.runtime_path_updates(
            Path("/repo"),
            data_dir=Path("/tmp/data"),
            pgdata_img_cap="500M",
        )

        self.assertEqual(updates["RAGONFIRE_REPO_DIR"], "/repo")
        self.assertEqual(updates["INPUT_DIR"], "/tmp/data/input")
        self.assertEqual(updates["PGDATA_IMG"], "/tmp/data/pgdata.ext4.img")
        self.assertEqual(updates["PGDATA_IMG_CAP"], "500M")

    def test_parse_key_value_accepts_values_with_equals(self) -> None:
        key, value = self.module.parse_key_value("TOKEN_SECRET=a=b")

        self.assertEqual(key, "TOKEN_SECRET")
        self.assertEqual(value, "a=b")

    def test_parse_key_value_rejects_missing_key(self) -> None:
        with self.assertRaisesRegex(ValueError, "non-empty key"):
            self.module.parse_key_value("=value")


class NativeWarningFilterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_script_module("native_warning_filter")

    def test_suppresses_known_onnxruntime_device_discovery_warning(self) -> None:
        line = (
            b'2026-05-20 20:49:22.498570723 '
            b'[W:onnxruntime:Default, device_discovery.cc:133 GetPciBusId] '
            b'Skipping pci_bus_id for PCI path at "/sys/devices/LNXSYSTM:00" '
            b'because filename "5620e0c7" did not match expected pattern\n'
        )

        self.assertTrue(self.module.should_suppress_native_stderr_line(line))

    def test_preserves_other_native_stderr_lines(self) -> None:
        line = b"[E:onnxruntime:Default] real runtime failure\n"

        self.assertFalse(self.module.should_suppress_native_stderr_line(line))


if __name__ == "__main__":
    unittest.main()
