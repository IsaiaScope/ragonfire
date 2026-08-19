#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import stat
import sys
import tempfile
import types
import unittest
from unittest import mock
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "rag-anything" / "scripts" / "ragonfire_runtime.py"


def load_module():
    sys.modules["dotenv"] = types.SimpleNamespace(load_dotenv=lambda *_args, **_kwargs: None)
    spec = importlib.util.spec_from_file_location("ragonfire_runtime", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    sys.modules["ragonfire_runtime"] = module
    spec.loader.exec_module(module)
    return module


class RuntimeHelperTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()
        self.old_env = os.environ.copy()

    def tearDown(self) -> None:
        os.environ.clear()
        os.environ.update(self.old_env)

    def test_endpoint_rewrite_for_host_ingest(self) -> None:
        os.environ["POSTGRES_HOST_EXTERNAL"] = "localhost"
        os.environ["POSTGRES_PORT_EXTERNAL"] = "5433"
        os.environ["LLM_BINDING_HOST"] = "http://host.docker.internal:11434"
        os.environ["EMBEDDING_BINDING_HOST"] = "http://host.docker.internal:11434"

        self.module.load_runtime_env(Path("/tmp/unused"))

        self.assertEqual(os.environ["POSTGRES_HOST"], "localhost")
        self.assertEqual(os.environ["POSTGRES_PORT"], "5433")
        self.assertEqual(os.environ["LLM_BINDING_HOST"], "http://localhost:11434")
        self.assertEqual(os.environ["EMBEDDING_BINDING_HOST"], "http://localhost:11434")

    def test_typed_env_errors_are_clear(self) -> None:
        os.environ["EMBEDDING_DIM"] = "not-an-int"
        with self.assertRaisesRegex(RuntimeError, "EMBEDDING_DIM must be an integer"):
            self.module.env_int("EMBEDDING_DIM", "1024")

        os.environ["COSINE_THRESHOLD"] = "not-a-float"
        with self.assertRaisesRegex(RuntimeError, "COSINE_THRESHOLD must be a number"):
            self.module.env_float("COSINE_THRESHOLD", "0.2")

    def test_build_runtime_requires_working_dir(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "missing required environment variable: WORKING_DIR"):
            self.module.build_runtime(Path("/tmp/unused"), Path("/tmp/unused/scripts"))

    def test_validate_input_file_rejects_missing_and_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaises(FileNotFoundError):
                self.module.validate_input_file(root / "missing.pdf")
            with self.assertRaisesRegex(RuntimeError, "not a file"):
                self.module.validate_input_file(root)

    def test_build_runtime_uses_device_probe(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            scripts = Path(tmp) / "scripts"
            scripts.mkdir()
            probe = scripts / "mineru-device.sh"
            probe.write_text("#!/usr/bin/env bash\necho cuda\n")
            probe.chmod(probe.stat().st_mode | stat.S_IXUSR)

            os.environ["WORKING_DIR"] = str(Path(tmp) / "working")
            os.environ["MINERU_DEVICE"] = "auto"

            runtime = self.module.build_runtime(Path(tmp), scripts)
            self.assertEqual(runtime.mineru_device, "cuda")

    def test_build_runtime_centralizes_timeout_and_tuning_config(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            scripts = Path(tmp) / "scripts"
            scripts.mkdir()
            os.environ["WORKING_DIR"] = str(Path(tmp) / "working")
            os.environ["MINERU_DEVICE"] = "cpu"
            os.environ["TIMEOUT"] = "120"
            os.environ.pop("VISION_TIMEOUT", None)
            os.environ["EXTRACTION_TEMPERATURE"] = "0.0"
            os.environ["EXTRACTION_TUNING"] = "0"

            runtime = self.module.build_runtime(Path(tmp), scripts)

            self.assertEqual(runtime.text_timeout, 120)
            # vision falls back to TIMEOUT when VISION_TIMEOUT is unset
            self.assertEqual(runtime.vision_timeout, 120)
            self.assertEqual(runtime.extraction_temperature, 0.0)
            self.assertFalse(runtime.extraction_tuning)

    def test_build_runtime_uses_cpu_when_device_probe_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            scripts = Path(tmp) / "scripts"
            scripts.mkdir()
            os.environ["WORKING_DIR"] = str(Path(tmp) / "working")
            os.environ["MINERU_DEVICE"] = "auto"

            runtime = self.module.build_runtime(Path(tmp), scripts)
            self.assertEqual(runtime.mineru_device, "cpu")

    def test_lightrag_kwargs_are_typed(self) -> None:
        os.environ["TOP_K"] = "9"
        os.environ["COSINE_THRESHOLD"] = "0.42"
        os.environ["MIN_RERANK_SCORE"] = "0.0"
        os.environ["CHUNK_SIZE"] = "700"
        os.environ["CHUNK_OVERLAP_SIZE"] = "70"
        os.environ["EMBEDDING_BATCH_NUM"] = "3"
        os.environ["MAX_PARALLEL_INSERT"] = "4"
        os.environ["WORKSPACE"] = "papers"

        kwargs = self.module.lightrag_kwargs()

        self.assertEqual(kwargs["workspace"], "papers")
        self.assertEqual(kwargs["top_k"], 9)
        self.assertEqual(kwargs["cosine_threshold"], 0.42)
        self.assertEqual(kwargs["chunk_token_size"], 700)
        self.assertEqual(kwargs["chunk_overlap_token_size"], 70)
        self.assertEqual(kwargs["embedding_batch_num"], 3)
        self.assertEqual(kwargs["max_parallel_insert"], 4)
        self.assertEqual(kwargs["min_rerank_score"], 0.0)
        self.assertTrue(callable(kwargs["rerank_model_func"]))

    def test_dependency_warning_defaults_are_quiet(self) -> None:
        os.environ.pop("ORT_LOG_SEVERITY_LEVEL", None)
        self.module.quiet_dependency_warnings()
        self.assertEqual(os.environ["ORT_LOG_SEVERITY_LEVEL"], "3")

    def test_check_ollama_reports_recovery_hint(self) -> None:
        with mock.patch.object(self.module.urllib.request, "urlopen", side_effect=OSError("refused")):
            with self.assertRaisesRegex(RuntimeError, "Run /lightrag-start"):
                self.module.check_ollama("http://localhost:11434")


if __name__ == "__main__":
    unittest.main()
