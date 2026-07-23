#!/usr/bin/env python3
"""
Merge operator-scoped artifacts from multiple already-rendered usecases.

This script intentionally leaves per-usecase network/IPAM manifests alone and
only merges the shared/operator-scoped outputs:
  - values.yaml
  - NicClusterPolicy.yaml
  - nic-config-crd-*.yaml (copied with de-duplication)

Input arguments may be usecase names (resolved under NETOP_ROOT_DIR/usecase/)
or explicit paths to already rendered usecase directories.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import pathlib
import shutil
import sys
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Sequence, Tuple

try:
    import yaml
except ImportError as exc:  # pragma: no cover - environment issue
    print("ERROR: PyYAML is required for ops/merge-usecases.py", file=sys.stderr)
    raise SystemExit(1) from exc


class MergeConflict(RuntimeError):
    """Raised when two rendered usecases disagree on a shared setting."""


class BlockStyleDumper(yaml.SafeDumper):
    """Emit multiline strings using YAML block style."""


def _str_presenter(dumper: yaml.SafeDumper, data: str) -> yaml.ScalarNode:
    if "\n" in data:
        return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="|")
    return dumper.represent_scalar("tag:yaml.org,2002:str", data)


BlockStyleDumper.add_representer(str, _str_presenter)


@dataclass(frozen=True)
class RenderedUsecase:
    name: str
    path: pathlib.Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Merge shared operator artifacts from rendered usecase directories."
    )
    parser.add_argument(
        "usecases",
        nargs="+",
        help="Rendered usecase names or explicit rendered usecase directories",
    )
    parser.add_argument(
        "--root-dir",
        default=os.environ.get("NETOP_ROOT_DIR", os.getcwd()),
        help="Repository root used when resolving usecase names (default: NETOP_ROOT_DIR or cwd)",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Directory for merged outputs (default: <root>/usecase/merged)",
    )
    parser.add_argument(
        "--values-file",
        default=os.environ.get("NETOP_VALUES_FILE", "values.yaml"),
        help="Per-usecase Helm values filename (default: values.yaml)",
    )
    parser.add_argument(
        "--niccluster-file",
        default=os.environ.get("NETOP_NICCLUSTER_FILE", "NicClusterPolicy.yaml"),
        help="Per-usecase NicClusterPolicy filename (default: NicClusterPolicy.yaml)",
    )
    return parser.parse_args()


def resolve_usecases(items: Sequence[str], root_dir: pathlib.Path) -> List[RenderedUsecase]:
    resolved: List[RenderedUsecase] = []
    seen: set[pathlib.Path] = set()
    for item in items:
        path = pathlib.Path(item)
        if path.exists():
            render_dir = path.resolve()
            name = render_dir.name
        else:
            render_dir = (root_dir / "usecase" / item).resolve()
            name = item
        if not render_dir.is_dir():
            raise FileNotFoundError(f"Rendered usecase directory not found: {render_dir}")
        if render_dir in seen:
            continue
        seen.add(render_dir)
        resolved.append(RenderedUsecase(name=name, path=render_dir))
    return resolved


def load_yaml(path: pathlib.Path) -> Dict[str, Any]:
    try:
        data = yaml.safe_load(path.read_text())
    except Exception as exc:
        raise RuntimeError(f"Failed to parse YAML file {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise RuntimeError(f"Expected a YAML mapping in {path}")
    return data


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def merge_named_items(
    left: List[Dict[str, Any]],
    right: List[Dict[str, Any]],
    key_field: str,
    path: Tuple[str, ...],
) -> List[Dict[str, Any]]:
    merged: List[Dict[str, Any]] = [copy.deepcopy(item) for item in left]
    index: Dict[str, int] = {}
    for idx, item in enumerate(merged):
        key = item.get(key_field)
        if key is not None:
            index[str(key)] = idx
    for item in right:
        item_copy = copy.deepcopy(item)
        key = item_copy.get(key_field)
        if key is None:
            if item_copy not in merged:
                merged.append(item_copy)
            continue
        key_str = str(key)
        if key_str in index:
            merged[index[key_str]] = deep_merge(
                merged[index[key_str]], item_copy, path + (f"{key_field}={key_str}",)
            )
        else:
            index[key_str] = len(merged)
            merged.append(item_copy)
    return merged


def merge_list(left: List[Any], right: List[Any], path: Tuple[str, ...]) -> List[Any]:
    if path[-2:] in (("sriovDevicePlugin", "resources"), ("rdmaSharedDevicePlugin", "resources")):
        return merge_named_items(left, right, "name", path)

    merged: List[Any] = [copy.deepcopy(item) for item in left]
    seen = {json.dumps(item, sort_keys=True, default=str) for item in merged}
    for item in right:
        marker = json.dumps(item, sort_keys=True, default=str)
        if marker not in seen:
            merged.append(copy.deepcopy(item))
            seen.add(marker)
    return merged


def deep_merge(left: Any, right: Any, path: Tuple[str, ...] = ()) -> Any:
    if left is None:
        return copy.deepcopy(right)
    if right is None:
        return copy.deepcopy(left)

    if isinstance(left, dict) and isinstance(right, dict):
        merged = copy.deepcopy(left)
        for key, value in right.items():
            if key in merged:
                merged[key] = deep_merge(merged[key], value, path + (str(key),))
            else:
                merged[key] = copy.deepcopy(value)
        return merged

    if isinstance(left, list) and isinstance(right, list):
        return merge_list(left, right, path)

    if isinstance(left, bool) and isinstance(right, bool):
        return left or right

    if left == right:
        return copy.deepcopy(left)

    dotted = ".".join(path) if path else "<root>"
    raise MergeConflict(f"Conflicting values at {dotted}: {left!r} != {right!r}")


def parse_plugin_config(raw_config: str, key_name: str, source: pathlib.Path) -> Dict[str, Any]:
    try:
        config = json.loads(raw_config)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON in {source}: {exc}") from exc
    if not isinstance(config, dict):
        raise RuntimeError(f"Expected JSON object in {source}")
    config.setdefault(key_name, [])
    if not isinstance(config[key_name], list):
        raise RuntimeError(f"Expected {key_name} list in {source}")
    return config


def merge_plugin_block(
    left: Dict[str, Any],
    right: Dict[str, Any],
    list_key: str,
    path: Tuple[str, ...],
    source: pathlib.Path,
) -> Dict[str, Any]:
    left_meta = {key: value for key, value in left.items() if key != "config"}
    right_meta = {key: value for key, value in right.items() if key != "config"}
    merged = deep_merge(left_meta, right_meta, path)

    left_cfg = parse_plugin_config(left.get("config", "{}"), list_key, source)
    right_cfg = parse_plugin_config(right.get("config", "{}"), list_key, source)

    merged_cfg = copy.deepcopy(left_cfg)
    merged_cfg[list_key] = merge_named_items(
        left_cfg.get(list_key, []),
        right_cfg.get(list_key, []),
        "resourceName",
        path + (list_key,),
    )

    for key, value in right_cfg.items():
        if key == list_key:
            continue
        if key in merged_cfg:
            merged_cfg[key] = deep_merge(merged_cfg[key], value, path + (key,))
        else:
            merged_cfg[key] = copy.deepcopy(value)

    merged["config"] = json.dumps(merged_cfg, indent=2)
    return merged


def merge_values(values_docs: Sequence[Tuple[RenderedUsecase, pathlib.Path]]) -> Dict[str, Any]:
    merged: Dict[str, Any] | None = None
    for usecase, path in values_docs:
        current = load_yaml(path)
        if merged is None:
            merged = current
            continue
        merged = deep_merge(merged, current, path=(usecase.name, "values"))
    return merged or {}


def merge_niccluster(
    ncp_docs: Sequence[Tuple[RenderedUsecase, pathlib.Path]]
) -> Dict[str, Any]:
    merged: Dict[str, Any] | None = None
    for usecase, path in ncp_docs:
        current = load_yaml(path)
        if merged is None:
            merged = current
            continue

        for field in ("apiVersion", "kind"):
            if merged.get(field) != current.get(field):
                raise MergeConflict(
                    f"Conflicting {field} between merged NicClusterPolicy and {path}"
                )
        merged["metadata"] = deep_merge(
            merged.get("metadata", {}),
            current.get("metadata", {}),
            path=("metadata",),
        )

        merged_spec = merged.setdefault("spec", {})
        current_spec = current.get("spec", {})
        for key, value in current_spec.items():
            if key not in merged_spec:
                merged_spec[key] = copy.deepcopy(value)
                continue

            if key == "sriovDevicePlugin":
                merged_spec[key] = merge_plugin_block(
                    merged_spec[key], value, "resourceList", ("spec", key), path
                )
            elif key == "rdmaSharedDevicePlugin":
                merged_spec[key] = merge_plugin_block(
                    merged_spec[key], value, "configList", ("spec", key), path
                )
            else:
                merged_spec[key] = deep_merge(
                    merged_spec[key], value, ("spec", str(key))
                )
    return merged or {}


def copy_nic_config_crds(usecases: Sequence[RenderedUsecase], output_dir: pathlib.Path) -> List[str]:
    copied: Dict[str, str] = {}
    output_names: List[str] = []
    for usecase in usecases:
        for crd_path in sorted(usecase.path.glob("nic-config-crd-*.yaml")):
            filename = crd_path.name
            digest = sha256_file(crd_path)
            dst = output_dir / filename
            if filename in copied:
                if copied[filename] != digest:
                    raise MergeConflict(
                        f"Conflicting nic-config CRD contents for {filename}: {usecase.path}"
                    )
                continue
            shutil.copy2(crd_path, dst)
            copied[filename] = digest
            output_names.append(filename)
    return output_names


def dump_yaml(path: pathlib.Path, data: Dict[str, Any]) -> None:
    rendered = yaml.dump(
        data,
        Dumper=BlockStyleDumper,
        default_flow_style=False,
        sort_keys=False,
        explicit_start=True,
    )
    path.write_text(rendered)


def main() -> int:
    args = parse_args()
    root_dir = pathlib.Path(args.root_dir).resolve()
    output_dir = (
        pathlib.Path(args.output_dir).resolve()
        if args.output_dir
        else (root_dir / "usecase" / "merged")
    )
    usecases = resolve_usecases(args.usecases, root_dir)

    output_dir.mkdir(parents=True, exist_ok=True)

    values_inputs: List[Tuple[RenderedUsecase, pathlib.Path]] = []
    ncp_inputs: List[Tuple[RenderedUsecase, pathlib.Path]] = []
    for usecase in usecases:
        values_path = usecase.path / args.values_file
        ncp_path = usecase.path / args.niccluster_file
        if not values_path.is_file():
            raise FileNotFoundError(f"Missing rendered values file: {values_path}")
        if not ncp_path.is_file():
            raise FileNotFoundError(f"Missing rendered NicClusterPolicy file: {ncp_path}")
        values_inputs.append((usecase, values_path))
        ncp_inputs.append((usecase, ncp_path))

    merged_values = merge_values(values_inputs)
    merged_ncp = merge_niccluster(ncp_inputs)
    copied_crds = copy_nic_config_crds(usecases, output_dir)

    dump_yaml(output_dir / args.values_file, merged_values)
    dump_yaml(output_dir / args.niccluster_file, merged_ncp)

    (output_dir / "merged-usecases.txt").write_text(
        "".join(f"{usecase.name}\n" for usecase in usecases)
    )

    print(f"Merged {len(usecases)} rendered usecases into {output_dir}")
    print(f"  values: {output_dir / args.values_file}")
    print(f"  niccluster: {output_dir / args.niccluster_file}")
    if copied_crds:
        print("  nic-config CRDs:")
        for filename in copied_crds:
            print(f"    {output_dir / filename}")
    print("Per-usecase network and IPAM manifests remain in their original usecase directories.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, MergeConflict, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
