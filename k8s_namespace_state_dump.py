#!/usr/bin/env python3
"""Save a namespace-focused Kubernetes state bundle.

Examples:
  tools/k8s_namespace_state_dump.py -n default
  tools/k8s_namespace_state_dump.py -n dpf-operator-system --global-ops /path/to/global_ops.cfg
  tools/k8s_namespace_state_dump.py -n dpf-operator-system --cmd "microk8s kubectl" --helm-cmd "microk8s helm"
  tools/k8s_namespace_state_dump.py -n default --cmd "kubectl --context my-cluster" --include-logs
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import shlex
import subprocess
import sys
import tarfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


_SAFE_RE = re.compile(r"[^A-Za-z0-9_.=-]+")

_SPECIAL_OPERATOR_RESOURCES = [
    (
        "NicClusterPolicy",
        ["nicclusterpolicies.mellanox.com", "nicclusterpolicies", "nicclusterpolicy", "NicClusterPolicy"],
        ["nicclusterpolicies.mellanox.com"],
    ),
    (
        "SriovNetwork",
        ["sriovnetworks.sriovnetwork.openshift.io", "sriovnetworks", "sriovnetwork", "SriovNetwork"],
        ["sriovnetworks.sriovnetwork.openshift.io"],
    ),
    (
        "SriovIBNetwork",
        ["sriovibnetworks.sriovnetwork.openshift.io", "sriovibnetworks", "sriovibnetwork", "SriovIBNetwork"],
        ["sriovibnetworks.sriovnetwork.openshift.io"],
    ),
    (
        "SriovNetworkNodePolicy",
        [
            "sriovnetworknodepolicies.sriovnetwork.openshift.io",
            "sriovnetworknodepolicies",
            "sriovnetworknodepolicy",
            "SriovNetworkNodePolicy",
        ],
        ["sriovnetworknodepolicies.sriovnetwork.openshift.io"],
    ),
    (
        "SriovNetworkPoolConfig",
        [
            "sriovnetworkpoolconfigs.sriovnetwork.openshift.io",
            "sriovnetworkpoolconfigs",
            "sriovnetworkpoolconfig",
            "SriovNetworkPoolConfig",
        ],
        ["sriovnetworkpoolconfigs.sriovnetwork.openshift.io"],
    ),
    (
        "SriovNetworkNodeState",
        [
            "sriovnetworknodestates.sriovnetwork.openshift.io",
            "sriovnetworknodestates",
            "sriovnetworknodestate",
            "SriovNetworkNodeState",
        ],
        ["sriovnetworknodestates.sriovnetwork.openshift.io"],
    ),
]

_NETWORK_MUST_GATHER_RESOURCES = _SPECIAL_OPERATOR_RESOURCES + [
    (
        "SriovOperatorConfig",
        ["sriovoperatorconfigs.sriovnetwork.openshift.io", "sriovoperatorconfigs", "sriovoperatorconfig"],
        ["sriovoperatorconfigs.sriovnetwork.openshift.io"],
    ),
    (
        "NetworkAttachmentDefinition",
        [
            "network-attachment-definitions.k8s.cni.cncf.io",
            "network-attachment-definitions",
            "network-attachment-definition",
            "net-attach-def",
        ],
        ["network-attachment-definitions.k8s.cni.cncf.io"],
    ),
    (
        "HostDeviceNetwork",
        ["hostdevicenetworks.mellanox.com", "hostdevicenetworks", "hostdevicenetwork"],
        ["hostdevicenetworks.mellanox.com"],
    ),
    (
        "MacvlanNetwork",
        ["macvlannetworks.mellanox.com", "macvlannetworks", "macvlannetwork"],
        ["macvlannetworks.mellanox.com"],
    ),
    (
        "IPoIBNetwork",
        ["ipoibnetworks.mellanox.com", "ipoibnetworks", "ipoibnetwork"],
        ["ipoibnetworks.mellanox.com"],
    ),
    (
        "NodeNetworkState",
        ["nodenetworkstates.nmstate.io", "nodenetworkstates", "nodenetworkstate"],
        ["nodenetworkstates.nmstate.io"],
    ),
    (
        "NodeNetworkConfigurationPolicy",
        [
            "nodenetworkconfigurationpolicies.nmstate.io",
            "nodenetworkconfigurationpolicies",
            "nodenetworkconfigurationpolicy",
        ],
        ["nodenetworkconfigurationpolicies.nmstate.io"],
    ),
    (
        "OpenShiftNetworkConfig",
        ["networks.config.openshift.io", "networks.operator.openshift.io", "network.config.openshift.io"],
        ["networks.config.openshift.io", "networks.operator.openshift.io"],
    ),
    (
        "ClusterNetwork",
        ["clusternetworks.network.openshift.io", "clusternetworks", "clusternetwork"],
        ["clusternetworks.network.openshift.io"],
    ),
    (
        "OVNEgressNetworkPolicy",
        [
            "egressfirewalls.k8s.ovn.org",
            "egressips.k8s.ovn.org",
            "egressqoses.k8s.ovn.org",
            "egressservices.k8s.ovn.org",
        ],
        [
            "egressfirewalls.k8s.ovn.org",
            "egressips.k8s.ovn.org",
            "egressqoses.k8s.ovn.org",
            "egressservices.k8s.ovn.org",
        ],
    ),
]

_NETWORK_MUST_GATHER_NAMESPACES = [
    "openshift-sriov-network-operator",
    "openshift-network-operator",
    "openshift-multus",
    "openshift-ovn-kubernetes",
    "openshift-sdn",
    "openshift-network-diagnostics",
    "openshift-nmstate",
    "nvidia-network-operator",
    "network-operator",
    "metallb-system",
    "whereabouts",
    "multus",
    "kube-system",
]

_NETWORK_MUST_GATHER_NAMESPACE_RESOURCES = [
    "all",
    "pods",
    "deployments.apps",
    "daemonsets.apps",
    "replicasets.apps",
    "statefulsets.apps",
    "jobs.batch",
    "cronjobs.batch",
    "services",
    "endpoints",
    "endpointslices.discovery.k8s.io",
    "configmaps",
    "secrets",
    "serviceaccounts",
    "roles.rbac.authorization.k8s.io",
    "rolebindings.rbac.authorization.k8s.io",
    "events",
    "events.events.k8s.io",
    "network-attachment-definitions.k8s.cni.cncf.io",
]

_NETWORK_CRD_KEYWORDS = [
    "sriov",
    "mellanox",
    "nvidia",
    "k8s.cni.cncf.io",
    "nmstate",
    "whereabouts",
    "multus",
    "ovn",
    "egress",
    "network.openshift.io",
    "operator.openshift.io",
]


@dataclass
class CmdResult:
    argv: list[str]
    rc: int
    stdout: str
    stderr: str


@dataclass
class GlobalOpsCommands:
    k8cl: str | None
    helmcl: str | None
    source: str
    warning: str | None = None


def text_or_empty(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)


def find_default_global_ops() -> Path | None:
    script_dir = Path(__file__).resolve().parent
    candidates = [
        script_dir / "global_ops.cfg",
        script_dir.parent / "global_ops.cfg",
        Path.cwd() / "global_ops.cfg",
    ]
    seen: set[Path] = set()
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        if resolved.is_file():
            return resolved
    return None


def load_global_ops_commands(global_ops_path: Path | None) -> GlobalOpsCommands:
    env_k8cl = os.environ.get("K8CL")
    env_helmcl = os.environ.get("HELMCL")
    if global_ops_path is None:
        return GlobalOpsCommands(
            env_k8cl,
            env_helmcl,
            "environment",
            "global_ops.cfg not found; using environment/default commands",
        )

    script = r'''
global_ops=$1
netop_root=$2
if [ -z "${NETOP_ROOT_DIR:-}" ]; then
    export NETOP_ROOT_DIR="$netop_root"
fi
source "$global_ops" >/dev/null || exit $?
printf '%s\0%s\0' "${K8CL:-}" "${HELMCL:-}"
'''
    try:
        proc = subprocess.run(
            ["bash", "-c", script, "bash", str(global_ops_path), str(global_ops_path.parent)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
    except FileNotFoundError:
        return GlobalOpsCommands(env_k8cl, env_helmcl, "environment", "bash not found; using environment/default commands")
    except subprocess.TimeoutExpired:
        return GlobalOpsCommands(
            env_k8cl,
            env_helmcl,
            "environment",
            f"timed out sourcing {global_ops_path}; using environment/default commands",
        )

    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip().splitlines()
        message = detail[-1] if detail else f"exit code {proc.returncode}"
        return GlobalOpsCommands(
            env_k8cl,
            env_helmcl,
            "environment",
            f"could not source {global_ops_path}: {message}; using environment/default commands",
        )

    values = proc.stdout.split("\0")
    if len(values) < 2:
        return GlobalOpsCommands(
            env_k8cl,
            env_helmcl,
            "environment",
            f"could not read K8CL/HELMCL from {global_ops_path}; using environment/default commands",
        )
    return GlobalOpsCommands(values[0] or env_k8cl, values[1] or env_helmcl, str(global_ops_path))


def split_command(command: str, label: str) -> list[str] | None:
    try:
        argv = shlex.split(command)
    except ValueError as exc:
        print(f"error: {label} is not valid shell syntax: {exc}", file=sys.stderr)
        return None
    if not argv:
        print(f"error: {label} must not be empty", file=sys.stderr)
        return None
    return argv


def missing_executable(command: list[str]) -> str | None:
    executable = command[0]
    if Path(executable).is_absolute() or "/" in executable:
        return None if Path(executable).exists() else executable
    return None if shutil.which(executable) else executable


class Collector:
    def __init__(
        self,
        kubectl: list[str],
        helm: list[str],
        namespace: str,
        out_dir: Path,
        timeout: int,
        command_source: str,
    ) -> None:
        self.kubectl = kubectl
        self.helm = helm
        self.namespace = namespace
        self.out_dir = out_dir
        self.timeout = timeout
        self.commands_log = out_dir / "commands.jsonl"
        self.summary: dict[str, object] = {
            "namespace": namespace,
            "kubectl": kubectl,
            "helm": helm,
            "command_source": command_source,
            "started_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "warnings": [],
            "files": [],
        }

    def run_argv(self, argv: list[str], *, timeout: int | None = None) -> CmdResult:
        try:
            proc = subprocess.run(
                argv,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout or self.timeout,
                check=False,
            )
            result = CmdResult(argv=argv, rc=proc.returncode, stdout=proc.stdout, stderr=proc.stderr)
        except FileNotFoundError as exc:
            missing = exc.filename or argv[0]
            result = CmdResult(argv=argv, rc=127, stdout="", stderr=f"{missing}: command not found")
        except subprocess.TimeoutExpired as exc:
            result = CmdResult(
                argv=argv,
                rc=124,
                stdout=text_or_empty(exc.stdout),
                stderr=text_or_empty(exc.stderr) + f"\nTIMEOUT after {timeout or self.timeout}s",
            )
        with self.commands_log.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps({
                "argv": argv,
                "rc": result.rc,
                "stderr": result.stderr[-2000:],
            }) + "\n")
        return result

    def run(self, args: Iterable[str], *, timeout: int | None = None) -> CmdResult:
        return self.run_argv([*self.kubectl, *args], timeout=timeout)

    def run_helm(self, args: Iterable[str], *, timeout: int | None = None) -> CmdResult:
        return self.run_argv([*self.helm, *args], timeout=timeout)

    def save_text(self, relpath: str, text: str) -> Path:
        path = self.out_dir / relpath
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", errors="replace")
        self.summary["files"].append(relpath)
        return path

    def capture(self, relpath: str, args: Iterable[str], *, timeout: int | None = None) -> CmdResult:
        result = self.run(args, timeout=timeout)
        body = result.stdout
        if result.rc != 0:
            body = (
                f"# command failed rc={result.rc}\n"
                f"# argv: {shlex.join(result.argv)}\n"
                f"# stderr:\n{result.stderr}\n"
                f"# stdout:\n{result.stdout}"
            )
            self.warn(f"{relpath}: rc={result.rc}")
        self.save_text(relpath, body)
        if result.stderr.strip():
            self.save_text(relpath + ".stderr", result.stderr)
        return result

    def warn(self, message: str) -> None:
        print(f"warning: {message}", file=sys.stderr)
        self.summary["warnings"].append(message)


def capture_optional(
    c: Collector,
    relpath: str,
    args: Iterable[str],
    *,
    timeout: int | None = None,
    save_failure: bool = True,
    warn_on_failure: bool = False,
) -> CmdResult:
    result = c.run(args, timeout=timeout)
    if result.rc == 0:
        c.save_text(relpath, result.stdout)
        if result.stderr.strip():
            c.save_text(relpath + ".stderr", result.stderr)
    elif save_failure:
        c.save_text(
            relpath + ".failed.txt",
            f"# command failed rc={result.rc}\n"
            f"# argv: {shlex.join(result.argv)}\n"
            f"# stderr:\n{result.stderr}\n"
            f"# stdout:\n{result.stdout}",
        )
        if warn_on_failure:
            c.warn(f"{relpath}: rc={result.rc}")
    return result


def capture_helm_optional(
    c: Collector,
    relpath: str,
    args: Iterable[str],
    *,
    timeout: int | None = None,
    save_failure: bool = True,
) -> CmdResult:
    result = c.run_helm(args, timeout=timeout)
    if result.rc == 0:
        c.save_text(relpath, result.stdout)
        if result.stderr.strip():
            c.save_text(relpath + ".stderr", result.stderr)
    elif save_failure:
        c.save_text(
            relpath + ".failed.txt",
            f"# command failed rc={result.rc}\n"
            f"# argv: {shlex.join(result.argv)}\n"
            f"# stderr:\n{result.stderr}\n"
            f"# stdout:\n{result.stdout}",
        )
    return result


def capture_first_success(
    c: Collector,
    relpath: str,
    attempts: Iterable[Iterable[str]],
    *,
    timeout: int | None = None,
    warn_on_failure: bool = False,
) -> CmdResult | None:
    failures: list[CmdResult] = []
    seen: set[tuple[str, ...]] = set()
    for args_iter in attempts:
        args = tuple(args_iter)
        if args in seen:
            continue
        seen.add(args)
        result = c.run(args, timeout=timeout)
        if result.rc == 0:
            c.save_text(relpath, result.stdout)
            if result.stderr.strip():
                c.save_text(relpath + ".stderr", result.stderr)
            return result
        failures.append(result)

    body = ["# every attempted command failed"]
    for result in failures:
        body.extend([
            "",
            f"# rc={result.rc}",
            f"# argv: {shlex.join(result.argv)}",
            "# stderr:",
            result.stderr,
            "# stdout:",
            result.stdout,
        ])
    c.save_text(relpath + ".failed.txt", "\n".join(body))
    if warn_on_failure:
        c.warn(f"{relpath}: all attempted forms failed")
    return failures[-1] if failures else None


def safe_name(value: str) -> str:
    cleaned = _SAFE_RE.sub("_", value.strip())
    return cleaned.strip("._") or "unnamed"


def load_json(result: CmdResult) -> dict:
    if result.rc != 0 or not result.stdout.strip():
        return {}
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def list_lines(result: CmdResult) -> list[str]:
    if result.rc != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def json_items(data: dict) -> list[dict]:
    items = data.get("items", [])
    return [item for item in items if isinstance(item, dict)]


def meta_name(obj: dict) -> str:
    meta = obj.get("metadata", {})
    return str(meta.get("name", "")) if isinstance(meta, dict) else ""


def collect_pod_references(pods: list[dict]) -> dict[str, set[str]]:
    refs: dict[str, set[str]] = {
        "nodes": set(),
        "pvcs": set(),
        "serviceaccounts": set(),
        "configmaps": set(),
        "secrets": set(),
        "runtimeclasses": set(),
        "priorityclasses": set(),
    }
    for pod in pods:
        spec = pod.get("spec", {})
        if not isinstance(spec, dict):
            continue
        for field, key in [
            ("nodeName", "nodes"),
            ("serviceAccountName", "serviceaccounts"),
            ("runtimeClassName", "runtimeclasses"),
            ("priorityClassName", "priorityclasses"),
        ]:
            value = spec.get(field)
            if value:
                refs[key].add(str(value))

        for pull_secret in spec.get("imagePullSecrets", []) or []:
            if isinstance(pull_secret, dict) and pull_secret.get("name"):
                refs["secrets"].add(str(pull_secret["name"]))

        for volume in spec.get("volumes", []) or []:
            if not isinstance(volume, dict):
                continue
            if isinstance(volume.get("persistentVolumeClaim"), dict):
                name = volume["persistentVolumeClaim"].get("claimName")
                if name:
                    refs["pvcs"].add(str(name))
            if isinstance(volume.get("configMap"), dict):
                name = volume["configMap"].get("name")
                if name:
                    refs["configmaps"].add(str(name))
            if isinstance(volume.get("secret"), dict):
                name = volume["secret"].get("secretName")
                if name:
                    refs["secrets"].add(str(name))
            if isinstance(volume.get("projected"), dict):
                for source in volume["projected"].get("sources", []) or []:
                    if not isinstance(source, dict):
                        continue
                    if isinstance(source.get("configMap"), dict) and source["configMap"].get("name"):
                        refs["configmaps"].add(str(source["configMap"]["name"]))
                    if isinstance(source.get("secret"), dict) and source["secret"].get("name"):
                        refs["secrets"].add(str(source["secret"]["name"]))

        for container in [*(spec.get("initContainers", []) or []), *(spec.get("containers", []) or [])]:
            if not isinstance(container, dict):
                continue
            for env_from in container.get("envFrom", []) or []:
                if not isinstance(env_from, dict):
                    continue
                if isinstance(env_from.get("configMapRef"), dict) and env_from["configMapRef"].get("name"):
                    refs["configmaps"].add(str(env_from["configMapRef"]["name"]))
                if isinstance(env_from.get("secretRef"), dict) and env_from["secretRef"].get("name"):
                    refs["secrets"].add(str(env_from["secretRef"]["name"]))
            for env in container.get("env", []) or []:
                if not isinstance(env, dict):
                    continue
                value_from = env.get("valueFrom")
                if not isinstance(value_from, dict):
                    continue
                if isinstance(value_from.get("configMapKeyRef"), dict) and value_from["configMapKeyRef"].get("name"):
                    refs["configmaps"].add(str(value_from["configMapKeyRef"]["name"]))
                if isinstance(value_from.get("secretKeyRef"), dict) and value_from["secretKeyRef"].get("name"):
                    refs["secrets"].add(str(value_from["secretKeyRef"]["name"]))
    return refs


def collect_pvc_references(pvcs: list[dict]) -> dict[str, set[str]]:
    refs: dict[str, set[str]] = {"pvs": set(), "storageclasses": set()}
    for pvc in pvcs:
        spec = pvc.get("spec", {})
        if not isinstance(spec, dict):
            continue
        if spec.get("volumeName"):
            refs["pvs"].add(str(spec["volumeName"]))
        if spec.get("storageClassName"):
            refs["storageclasses"].add(str(spec["storageClassName"]))
    return refs


def get_attempts_for_resource(resource: str, namespace: str | None = None) -> list[list[str]]:
    attempts = [
        ["get", resource, "-A", "-o", "yaml"],
        ["get", resource, "-o", "yaml"],
    ]
    if namespace:
        attempts.append(["get", resource, "-n", namespace, "-o", "yaml"])
    return attempts


def describe_attempts_for_resource(resource: str, namespace: str | None = None) -> list[list[str]]:
    attempts = [
        ["describe", resource, "-A"],
        ["describe", resource],
    ]
    if namespace:
        attempts.append(["describe", resource, "-n", namespace])
    return attempts


def dump_cluster_baseline(c: Collector) -> None:
    c.capture("cluster/version.txt", ["version", "-o", "yaml"])
    c.capture("cluster/cluster-info.txt", ["cluster-info"])
    c.capture("cluster/api-resources.namespaced.txt", ["api-resources", "--verbs=list", "--namespaced=true", "-o", "name"])
    c.capture("cluster/api-resources.cluster-scoped.txt", ["api-resources", "--verbs=list", "--namespaced=false", "-o", "name"])
    c.capture("cluster/api-versions.txt", ["api-versions"])
    c.capture("cluster/nodes.yaml", ["get", "nodes", "-o", "yaml"])
    c.capture("cluster/storageclasses.yaml", ["get", "storageclasses", "-o", "yaml"])
    c.capture("cluster/crds.yaml", ["get", "crds", "-o", "yaml"])


def dump_helm_state(c: Collector) -> None:
    capture_helm_optional(c, "helm/version.txt", ["version"])
    capture_helm_optional(c, "helm/releases.namespace.yaml", ["list", "-n", c.namespace, "-o", "yaml"])
    capture_helm_optional(c, "helm/releases.all-namespaces.yaml", ["list", "-A", "-o", "yaml"])


def dump_namespace_resources(c: Collector) -> tuple[list[dict], list[dict], set[str]]:
    c.capture("namespace/namespace.yaml", ["get", "namespace", c.namespace, "-o", "yaml"])
    c.capture("namespace/describe.txt", ["describe", "namespace", c.namespace])
    c.capture("namespace/all-wide.txt", ["get", "all", "-n", c.namespace, "-o", "wide"])
    c.capture("namespace/events.core.yaml", ["get", "events", "-n", c.namespace, "-o", "yaml"])
    c.capture("namespace/events.events.k8s.io.yaml", ["get", "events.events.k8s.io", "-n", c.namespace, "-o", "yaml"])

    resources_result = c.run(["api-resources", "--verbs=list", "--namespaced=true", "-o", "name"])
    resources = list_lines(resources_result)
    if not resources:
        c.warn("could not discover namespaced API resources; falling back to common resource list")
        resources = [
            "pods", "services", "endpoints", "endpointslices.discovery.k8s.io",
            "configmaps", "secrets", "serviceaccounts", "persistentvolumeclaims",
            "deployments.apps", "daemonsets.apps", "statefulsets.apps", "replicasets.apps",
            "jobs.batch", "cronjobs.batch",
            "network-attachment-definitions.k8s.cni.cncf.io",
        ]

    seen_crd_resources: set[str] = set()
    for resource in resources:
        rel = f"namespaced/{safe_name(resource)}.yaml"
        result = c.capture(rel, ["get", resource, "-n", c.namespace, "-o", "yaml"], timeout=max(c.timeout, 120))
        if result.rc == 0 and "." in resource:
            seen_crd_resources.add(resource)

    pods_data = load_json(c.run(["get", "pods", "-n", c.namespace, "-o", "json"]))
    pvc_data = load_json(c.run(["get", "persistentvolumeclaims", "-n", c.namespace, "-o", "json"]))
    return json_items(pods_data), json_items(pvc_data), seen_crd_resources


def dump_describes(c: Collector, pods: list[dict]) -> None:
    c.capture("describe/all.txt", ["describe", "all", "-n", c.namespace], timeout=max(c.timeout, 120))
    for pod in pods:
        name = meta_name(pod)
        if name:
            c.capture(f"describe/pods/{safe_name(name)}.txt", ["describe", "pod", name, "-n", c.namespace])


def dump_pod_logs(
    c: Collector,
    pods: list[dict],
    *,
    namespace: str,
    rel_prefix: str,
    previous: bool,
    tail: int,
    warn_on_failure: bool,
) -> None:
    for pod in pods:
        pod_name = meta_name(pod)
        spec = pod.get("spec", {})
        if not pod_name or not isinstance(spec, dict):
            continue
        containers = []
        for container in [*(spec.get("initContainers", []) or []), *(spec.get("containers", []) or [])]:
            if isinstance(container, dict) and container.get("name"):
                containers.append(str(container["name"]))
        for container in containers:
            base = f"{rel_prefix}/{safe_name(pod_name)}/{safe_name(container)}"
            capture_optional(
                c,
                base + ".log",
                ["logs", pod_name, "-n", namespace, "-c", container, "--tail", str(tail), "--timestamps"],
                timeout=max(c.timeout, 120),
                save_failure=warn_on_failure,
                warn_on_failure=warn_on_failure,
            )
            if previous:
                capture_optional(
                    c,
                    base + ".previous.log",
                    ["logs", pod_name, "-n", namespace, "-c", container, "--previous", "--tail", str(tail), "--timestamps"],
                    timeout=max(c.timeout, 120),
                    save_failure=warn_on_failure,
                    warn_on_failure=warn_on_failure,
                )


def dump_logs(c: Collector, pods: list[dict], *, previous: bool, tail: int) -> None:
    dump_pod_logs(
        c,
        pods,
        namespace=c.namespace,
        rel_prefix="logs",
        previous=previous,
        tail=tail,
        warn_on_failure=True,
    )


def dump_network_must_gather(c: Collector, *, log_tail: int) -> set[str]:
    """Collect a Network Operator/SR-IOV must-gather style bundle."""
    crd_resources: set[str] = set()

    for label, candidates, crd_names in _NETWORK_MUST_GATHER_RESOURCES:
        rel_base = f"network-must-gather/resources/{safe_name(label)}"
        attempts: list[list[str]] = []
        describe_attempts: list[list[str]] = []
        for candidate in candidates:
            attempts.extend(get_attempts_for_resource(candidate, c.namespace))
            describe_attempts.extend(describe_attempts_for_resource(candidate, c.namespace))
        result = capture_first_success(c, rel_base + ".yaml", attempts, timeout=max(c.timeout, 120))
        capture_first_success(c, rel_base + ".describe.txt", describe_attempts, timeout=max(c.timeout, 120))
        if result and result.rc == 0:
            for candidate in candidates:
                if "." in candidate:
                    crd_resources.add(candidate)
                    break
        for crd_name in crd_names:
            capture_optional(
                c,
                f"network-must-gather/crds/{safe_name(crd_name)}.yaml",
                ["get", "crd", crd_name, "-o", "yaml"],
                timeout=max(c.timeout, 120),
            )

    crd_data = load_json(c.run(["get", "crds", "-o", "json"], timeout=max(c.timeout, 120)))
    for crd in json_items(crd_data):
        name = meta_name(crd)
        spec = crd.get("spec", {})
        if not name or not isinstance(spec, dict):
            continue
        group = str(spec.get("group", ""))
        names = spec.get("names", {})
        plural = str(names.get("plural", "")) if isinstance(names, dict) else ""
        haystack = " ".join([name, group, plural]).lower()
        if not any(keyword in haystack for keyword in _NETWORK_CRD_KEYWORDS):
            continue
        if plural and group:
            resource = f"{plural}.{group}"
            crd_resources.add(resource)
            capture_first_success(
                c,
                f"network-must-gather/custom-resources/{safe_name(resource)}.yaml",
                get_attempts_for_resource(resource, c.namespace),
                timeout=max(c.timeout, 120),
            )
        capture_optional(
            c,
            f"network-must-gather/crds/{safe_name(name)}.yaml",
            ["get", "crd", name, "-o", "yaml"],
            timeout=max(c.timeout, 120),
        )

    for namespace in _NETWORK_MUST_GATHER_NAMESPACES:
        ns_result = c.run(["get", "namespace", namespace, "-o", "json"])
        if ns_result.rc != 0:
            continue
        ns_dir = f"network-must-gather/namespaces/{safe_name(namespace)}"
        c.save_text(f"{ns_dir}/namespace.json", ns_result.stdout)
        c.capture(f"{ns_dir}/namespace.yaml", ["get", "namespace", namespace, "-o", "yaml"])
        c.capture(f"{ns_dir}/describe.txt", ["describe", "namespace", namespace])
        for resource in _NETWORK_MUST_GATHER_NAMESPACE_RESOURCES:
            capture_optional(
                c,
                f"{ns_dir}/resources/{safe_name(resource)}.yaml",
                ["get", resource, "-n", namespace, "-o", "yaml"],
                timeout=max(c.timeout, 120),
            )
        pods = json_items(load_json(c.run(["get", "pods", "-n", namespace, "-o", "json"])))
        dump_pod_logs(
            c,
            pods,
            namespace=namespace,
            rel_prefix=f"{ns_dir}/logs",
            previous=True,
            tail=log_tail,
            warn_on_failure=False,
        )

    return crd_resources


def dump_connected_objects(c: Collector, pods: list[dict], pvcs: list[dict], crd_resources: set[str]) -> None:
    pod_refs = collect_pod_references(pods)
    pvc_refs = collect_pvc_references(pvcs)

    for name in sorted(pod_refs["nodes"]):
        c.capture(f"connected/nodes/{safe_name(name)}.yaml", ["get", "node", name, "-o", "yaml"])
        c.capture(f"connected/nodes/{safe_name(name)}.describe.txt", ["describe", "node", name])

    for name in sorted(pod_refs["runtimeclasses"]):
        c.capture(f"connected/runtimeclasses/{safe_name(name)}.yaml", ["get", "runtimeclass", name, "-o", "yaml"])

    for name in sorted(pod_refs["priorityclasses"]):
        c.capture(f"connected/priorityclasses/{safe_name(name)}.yaml", ["get", "priorityclass", name, "-o", "yaml"])

    for name in sorted(pvc_refs["pvs"]):
        c.capture(f"connected/persistentvolumes/{safe_name(name)}.yaml", ["get", "persistentvolume", name, "-o", "yaml"])
        c.capture(f"connected/persistentvolumes/{safe_name(name)}.describe.txt", ["describe", "persistentvolume", name])

    for name in sorted(pvc_refs["storageclasses"]):
        c.capture(f"connected/storageclasses/{safe_name(name)}.yaml", ["get", "storageclass", name, "-o", "yaml"])

    for kind, names in [
        ("serviceaccount", pod_refs["serviceaccounts"]),
        ("configmap", pod_refs["configmaps"]),
        ("secret", pod_refs["secrets"]),
        ("persistentvolumeclaim", pod_refs["pvcs"]),
    ]:
        for name in sorted(names):
            c.capture(
                f"connected/{kind}s/{safe_name(name)}.yaml",
                ["get", kind, name, "-n", c.namespace, "-o", "yaml"],
            )

    crd_result = c.run(["get", "crds", "-o", "json"])
    crd_data = load_json(crd_result)
    crds_by_resource = {}
    for crd in json_items(crd_data):
        spec = crd.get("spec", {})
        if not isinstance(spec, dict):
            continue
        names = spec.get("names", {})
        group = spec.get("group", "")
        plural = names.get("plural", "") if isinstance(names, dict) else ""
        if plural and group:
            crds_by_resource[f"{plural}.{group}"] = meta_name(crd)

    for resource in sorted(crd_resources):
        crd_name = crds_by_resource.get(resource)
        if crd_name:
            c.capture(f"connected/crds/{safe_name(crd_name)}.yaml", ["get", "crd", crd_name, "-o", "yaml"])


def make_archive(out_dir: Path) -> Path:
    archive = out_dir.with_suffix(".tar.gz")
    with tarfile.open(archive, "w:gz") as tf:
        tf.add(out_dir, arcname=out_dir.name)
    return archive


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Save a namespace-focused Kubernetes state bundle.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("-n", "--namespace", required=True, help="Namespace to collect")
    parser.add_argument(
        "--cmd",
        default=None,
        help='Kubernetes command override, e.g. "kubectl" or "microk8s kubectl". Default: K8CL from global_ops.cfg, then kubectl.',
    )
    parser.add_argument(
        "--helm-cmd",
        default=None,
        help='Helm command override, e.g. "helm" or "microk8s helm". Default: HELMCL from global_ops.cfg, then helm.',
    )
    parser.add_argument(
        "--global-ops",
        default="",
        help="Path to global_ops.cfg. Default: discover beside this script or in the current directory.",
    )
    parser.add_argument(
        "-o", "--out-dir",
        default="",
        help="Output directory. Default: ./k8s-state-<namespace>-<timestamp>",
    )
    parser.add_argument("--timeout", type=int, default=60, help="Per-command timeout in seconds")
    parser.add_argument("--include-logs", action="store_true", help="Collect pod logs")
    parser.add_argument("--previous-logs", action="store_true", help="Also collect previous container logs")
    parser.add_argument("--log-tail", type=int, default=500, help="Lines per container log")
    parser.add_argument("--archive", action="store_true", help="Create a .tar.gz archive beside the output directory")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    global_ops_path = Path(args.global_ops).resolve() if args.global_ops else find_default_global_ops()
    global_ops_commands = load_global_ops_commands(global_ops_path)
    if global_ops_commands.warning:
        print(f"warning: {global_ops_commands.warning}", file=sys.stderr)

    kubectl_command = args.cmd or global_ops_commands.k8cl or "kubectl"
    helm_command = args.helm_cmd or global_ops_commands.helmcl or "helm"
    kubectl = split_command(kubectl_command, "K8CL/--cmd")
    helm = split_command(helm_command, "HELMCL/--helm-cmd")
    if kubectl is None or helm is None:
        return 2
    missing_kubectl = missing_executable(kubectl)
    if missing_kubectl:
        print(
            f"error: Kubernetes command executable not found: {missing_kubectl}\n"
            f"resolved command: {shlex.join(kubectl)}\n"
            f"command source: {global_ops_commands.source}\n"
            "Set K8CL in global_ops_user.cfg/global_ops.cfg or pass --cmd.",
            file=sys.stderr,
        )
        return 127

    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir = Path(args.out_dir or f"k8s-state-{safe_name(args.namespace)}-{stamp}").resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    collector = Collector(kubectl, helm, args.namespace, out_dir, args.timeout, global_ops_commands.source)
    print(f"writing namespace state to {out_dir}")

    dump_cluster_baseline(collector)
    dump_helm_state(collector)
    pods, pvcs, crd_resources = dump_namespace_resources(collector)
    network_crd_resources = dump_network_must_gather(collector, log_tail=args.log_tail)
    crd_resources.update(network_crd_resources)
    dump_describes(collector, pods)
    dump_connected_objects(collector, pods, pvcs, crd_resources)
    if args.include_logs:
        dump_logs(collector, pods, previous=args.previous_logs, tail=args.log_tail)

    collector.summary["finished_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
    collector.summary["pod_count"] = len(pods)
    collector.summary["pvc_count"] = len(pvcs)
    collector.summary["network_crd_resource_count"] = len(network_crd_resources)
    collector.save_text("summary.json", json.dumps(collector.summary, indent=2, sort_keys=True) + "\n")

    if args.archive:
        archive = make_archive(out_dir)
        print(f"archive written to {archive}")
    print(f"done: {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
