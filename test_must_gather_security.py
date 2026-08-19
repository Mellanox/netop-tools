#!/usr/bin/env python3
import os
import shutil
import stat
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "python_tools"))
from must_gather import NetworkOperatorMustGather


class TestMustGatherArtifactSafety(unittest.TestCase):
    def test_default_artifact_dir_is_private_and_unpredictable(self):
        path = NetworkOperatorMustGather.create_artifact_dir(None)
        self.addCleanup(shutil.rmtree, path)

        predictable = Path(f"/tmp/nvidia-network-operator_{datetime.now().strftime('%Y%m%d_%H%M')}")

        self.assertTrue(path.is_dir())
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700)
        self.assertNotEqual(path, predictable)
        self.assertRegex(path.name, r"^nvidia-network-operator_\d{8}_\d{6}_.+")

    def test_explicit_existing_artifact_dir_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            existing_dir = Path(temp_dir) / "must-gather"
            existing_dir.mkdir()

            with self.assertRaises(FileExistsError):
                NetworkOperatorMustGather.create_artifact_dir(str(existing_dir))

    def test_artifact_write_refuses_preexisting_symlink(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            artifact_dir = base / "must-gather"
            artifact_dir.mkdir(mode=0o700)
            target = base / "target"
            target.write_text("keep\n", encoding="utf-8")
            (artifact_dir / "network_operator_pod.log").symlink_to(target)

            gather = object.__new__(NetworkOperatorMustGather)
            gather.artifact_dir = artifact_dir

            with self.assertRaises(FileExistsError):
                gather.write_artifact("network_operator_pod.log", "overwrite\n")

            self.assertEqual(target.read_text(encoding="utf-8"), "keep\n")

    def test_artifact_write_creates_private_file(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            artifact_dir = Path(temp_dir) / "must-gather"
            artifact_dir.mkdir(mode=0o700)

            gather = object.__new__(NetworkOperatorMustGather)
            gather.artifact_dir = artifact_dir
            gather.write_artifact("nodes.status", "node data\n")

            output = artifact_dir / "nodes.status"
            self.assertEqual(output.read_text(encoding="utf-8"), "node data\n")
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
