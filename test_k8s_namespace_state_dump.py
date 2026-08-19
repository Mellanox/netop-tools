#!/usr/bin/env python3
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import k8s_namespace_state_dump as dump


class FakeCollector:
    def __init__(self) -> None:
        self.namespace = "nvidia-network-operator"
        self.timeout = 1
        self.run_args = []
        self.capture_args = []
        self.saved = []
        self.summary = {"warnings": [], "files": []}

    def log_component(self, component: str) -> None:
        pass

    def warn(self, message: str) -> None:
        self.summary["warnings"].append(message)

    def save_text(self, relpath: str, text: str):
        self.saved.append((relpath, text))
        self.summary["files"].append(relpath)
        return relpath

    def run(self, args, *, timeout=None):
        args = list(args)
        self.run_args.append(args)

        if args == ["api-resources", "--verbs=list", "--namespaced=true", "-o", "name"]:
            return self.result(args, "pods\nsecrets\nconfigmaps\n")
        if args == ["get", "crds", "-o", "json"]:
            return self.result(args, '{"items": []}')
        if args[:2] == ["get", "namespace"]:
            namespace = args[2] if len(args) > 2 else self.namespace
            return self.result(args, f'{{"metadata": {{"name": "{namespace}"}}}}')
        if args[:2] == ["get", "pods"] and args[-2:] == ["-o", "json"]:
            return self.result(args, '{"items": []}')
        if args[:2] == ["get", "persistentvolumeclaims"] and args[-2:] == ["-o", "json"]:
            return self.result(args, '{"items": []}')

        return self.result(args, "ok\n")

    def capture(self, relpath: str, args, *, timeout=None):
        args = list(args)
        self.capture_args.append(args)
        return self.result(args, "ok\n")

    @staticmethod
    def result(args, stdout: str, rc: int = 0):
        return dump.CmdResult(argv=["kubectl", *args], rc=rc, stdout=stdout, stderr="")


class TestSecretCollectionSafety(unittest.TestCase):
    def test_sensitive_resource_detection_is_secret_specific(self):
        self.assertTrue(dump.is_sensitive_namespace_resource("secrets"))
        self.assertTrue(dump.is_sensitive_namespace_resource("secret"))
        self.assertTrue(dump.is_sensitive_namespace_resource("v1/secrets"))
        self.assertFalse(dump.is_sensitive_namespace_resource("secretproviderclasses.secrets-store.csi.x-k8s.io"))

    def test_must_gather_resource_list_excludes_secrets(self):
        self.assertNotIn("secrets", dump._NETWORK_MUST_GATHER_NAMESPACE_RESOURCES)

    def test_namespace_dump_skips_discovered_secrets(self):
        collector = FakeCollector()

        dump.dump_namespace_resources(collector)

        self.assertNotIn(
            ["get", "secrets", "-n", collector.namespace, "-o", "yaml"],
            collector.capture_args,
        )
        self.assertIn(
            ["get", "pods", "-n", collector.namespace, "-o", "yaml"],
            collector.capture_args,
        )
        self.assertIn(
            ["get", "configmaps", "-n", collector.namespace, "-o", "yaml"],
            collector.capture_args,
        )

    def test_network_must_gather_skips_sensitive_namespace_resources(self):
        collector = FakeCollector()

        with (
            patch.object(dump, "_NETWORK_MUST_GATHER_RESOURCES", []),
            patch.object(dump, "_NETWORK_MUST_GATHER_NAMESPACES", ["kube-system"]),
            patch.object(dump, "_NETWORK_MUST_GATHER_NAMESPACE_RESOURCES", ["pods", "secrets", "configmaps"]),
        ):
            dump.dump_network_must_gather(collector, log_tail=10)

        self.assertNotIn(
            ["get", "secrets", "-n", "kube-system", "-o", "yaml"],
            collector.run_args,
        )
        self.assertIn(
            ["get", "pods", "-n", "kube-system", "-o", "yaml"],
            collector.run_args,
        )
        self.assertIn(
            ["get", "configmaps", "-n", "kube-system", "-o", "yaml"],
            collector.run_args,
        )

    def test_connected_objects_do_not_fetch_secret_refs(self):
        collector = FakeCollector()
        pods = [
            {
                "metadata": {"name": "operand"},
                "spec": {
                    "serviceAccountName": "operator-sa",
                    "imagePullSecrets": [{"name": "pull-secret"}],
                    "volumes": [
                        {"name": "config", "configMap": {"name": "operator-config"}},
                        {"name": "token", "secret": {"secretName": "mounted-secret"}},
                    ],
                    "containers": [
                        {
                            "name": "operand",
                            "envFrom": [{"secretRef": {"name": "envfrom-secret"}}],
                            "env": [
                                {
                                    "name": "TOKEN",
                                    "valueFrom": {"secretKeyRef": {"name": "env-secret", "key": "token"}},
                                }
                            ],
                        }
                    ],
                },
            }
        ]

        dump.dump_connected_objects(collector, pods, [], set())

        self.assertFalse(
            any(args[:2] == ["get", "secret"] for args in collector.capture_args),
            collector.capture_args,
        )
        self.assertIn(
            ["get", "serviceaccount", "operator-sa", "-n", collector.namespace, "-o", "yaml"],
            collector.capture_args,
        )
        self.assertIn(
            ["get", "configmap", "operator-config", "-n", collector.namespace, "-o", "yaml"],
            collector.capture_args,
        )


class TestGlobalOpsLoadingSafety(unittest.TestCase):
    def test_find_default_global_ops_ignores_cwd(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            base_dir = Path(temp_dir)
            script_dir = base_dir / "repo"
            cwd_dir = base_dir / "attacker-cwd"
            script_dir.mkdir()
            cwd_dir.mkdir()
            (cwd_dir / "global_ops.cfg").write_text('K8CL="attacker-kubectl"\n', encoding="utf-8")

            old_cwd = os.getcwd()
            try:
                os.chdir(cwd_dir)
                with patch.object(dump, "__file__", str(script_dir / "k8s_namespace_state_dump.py")):
                    self.assertIsNone(dump.find_default_global_ops())
            finally:
                os.chdir(old_cwd)

    def test_global_ops_is_parsed_without_shell_execution(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            cfg = Path(temp_dir) / "global_ops.cfg"
            sentinel = Path(temp_dir) / "sourced"
            cfg.write_text(
                f'touch "{sentinel}"\n'
                'export K8CL=${K8CL:-"kubectl"}\n'
                'export HELMCL="microk8s helm"\n',
                encoding="utf-8",
            )

            with (
                patch.object(dump.subprocess, "run", side_effect=AssertionError("global_ops.cfg must not execute")),
                patch.dict(os.environ, {}, clear=True),
            ):
                commands = dump.load_global_ops_commands(cfg)

            self.assertEqual(commands.k8cl, "kubectl")
            self.assertEqual(commands.helmcl, "microk8s helm")
            self.assertFalse(sentinel.exists())


if __name__ == "__main__":
    unittest.main()
