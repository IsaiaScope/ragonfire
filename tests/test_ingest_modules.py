#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "rag-anything" / "scripts"


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
