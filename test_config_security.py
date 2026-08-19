#!/usr/bin/env python3
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "python_tools"))
import config


def make_fake_root(base: Path, global_cfg: str = "", user_cfg: str = "") -> Path:
    root = base / "netop-tools"
    (root / "python_tools").mkdir(parents=True)
    (root / "python_tools" / "config.py").write_text("# marker\n", encoding="utf-8")
    (root / "global_ops.cfg").write_text(global_cfg, encoding="utf-8")
    if user_cfg:
        (root / "global_ops_user.cfg").write_text(user_cfg, encoding="utf-8")
    return root


class TestNetOpConfigRootSafety(unittest.TestCase):
    def test_from_env_does_not_fallback_to_cwd(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            attacker_cwd = base / "attacker-cwd"
            attacker_cwd.mkdir()
            (attacker_cwd / "allsh").write_text("# marker\n", encoding="utf-8")
            (attacker_cwd / "global_ops.cfg").write_text('K8CL="/tmp/evil"\n', encoding="utf-8")
            (attacker_cwd / "global_ops_user.cfg").write_text('CREATE_CONFIG_ONLY="0"\n', encoding="utf-8")

            old_cwd = os.getcwd()
            try:
                os.chdir(attacker_cwd)
                with (
                    patch.object(config, "__file__", str(base / "not-repo" / "python_tools" / "config.py")),
                    patch.dict(os.environ, {}, clear=True),
                ):
                    with self.assertRaises(RuntimeError):
                        config.NetOpConfig.from_env()
            finally:
                os.chdir(old_cwd)

    def test_autodetected_config_cannot_override_execution_controls(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = make_fake_root(
                Path(temp_dir),
                global_cfg='K8CL="/tmp/global-evil"\nCREATE_CONFIG_ONLY="0"\n',
                user_cfg='K8CL="/tmp/user-evil"\nCREATE_CONFIG_ONLY="0"\nNETOP_NAMESPACE="from-user"\n',
            )

            with (
                patch.object(config, "__file__", str(root / "python_tools" / "config.py")),
                patch.dict(os.environ, {}, clear=True),
            ):
                loaded = config.NetOpConfig.from_env()

            self.assertEqual(loaded.netop_root_dir, str(root))
            self.assertEqual(loaded.k8_client, "kubectl")
            self.assertTrue(loaded.create_config_only)
            self.assertEqual(loaded.netop_namespace, "from-user")

    def test_explicit_env_overrides_config_execution_controls(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = make_fake_root(
                Path(temp_dir),
                user_cfg='K8CL="/tmp/user-evil"\nCREATE_CONFIG_ONLY="0"\n',
            )

            with patch.dict(
                os.environ,
                {
                    "NETOP_ROOT_DIR": str(root),
                    "K8CL": "env-kubectl",
                    "CREATE_CONFIG_ONLY": "1",
                },
                clear=True,
            ):
                loaded = config.NetOpConfig.from_env()

            self.assertEqual(loaded.k8_client, "env-kubectl")
            self.assertTrue(loaded.create_config_only)

    def test_explicit_root_can_load_execution_controls_from_config(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = make_fake_root(
                Path(temp_dir),
                user_cfg='K8CL="microk8s kubectl"\nCREATE_CONFIG_ONLY="0"\n',
            )

            with patch.dict(os.environ, {"NETOP_ROOT_DIR": str(root)}, clear=True):
                loaded = config.NetOpConfig.from_env()

            self.assertEqual(loaded.k8_client, "microk8s kubectl")
            self.assertFalse(loaded.create_config_only)


if __name__ == "__main__":
    unittest.main()
