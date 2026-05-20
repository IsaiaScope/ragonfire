#!/usr/bin/env python3
"""Process-level stderr filtering for noisy native dependencies."""
from __future__ import annotations

import os
import threading
import atexit


_INSTALLED = False


def should_suppress_native_stderr_line(line: bytes) -> bool:
    text = line.decode("utf-8", errors="replace")
    return (
        "[W:onnxruntime:Default, device_discovery.cc:" in text
        and "Skipping pci_bus_id for PCI path" in text
        and "did not match expected pattern" in text
    )


def install_native_warning_filter() -> None:
    """Drop one known-benign ONNX Runtime sysfs warning, preserving all else."""
    global _INSTALLED
    if _INSTALLED:
        return
    _INSTALLED = True

    os.environ.setdefault("ORT_LOG_SEVERITY_LEVEL", "3")

    read_fd, write_fd = os.pipe()
    original_stderr_fd = os.dup(2)
    os.dup2(write_fd, 2)
    os.close(write_fd)

    def forward_stderr() -> None:
        with os.fdopen(read_fd, "rb", buffering=0) as source:
            for line in source:
                if not should_suppress_native_stderr_line(line):
                    os.write(original_stderr_fd, line)

    thread = threading.Thread(
        target=forward_stderr,
        name="native-stderr-filter",
        daemon=True,
    )
    thread.start()

    def restore_stderr() -> None:
        try:
            os.dup2(original_stderr_fd, 2)
        except OSError:
            return
        thread.join(timeout=1)
        try:
            os.close(original_stderr_fd)
        except OSError:
            pass

    atexit.register(restore_stderr)
