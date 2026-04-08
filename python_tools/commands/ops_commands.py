#!/usr/bin/env python3
"""
NVIDIA Network Operator Tools - Operations Commands
Python implementation of ops/ directory bash scripts
"""
import os
import sys
import argparse
import logging
import json

try:
    import yaml
    _YAML_AVAILABLE = True
except ImportError:
    _YAML_AVAILABLE = False
from pathlib import Path
from typing import List, Dict, Optional, Any

try:
    from ..config import get_config, validate_environment
    from ..utils import (
        run_command, kubectl, helm, setup_logging,
        get_nodes, cordon_nodes, uncordon_nodes, wait_for_pods_ready
    )
    from .. import device_tools
except ImportError:
    # Handle both direct execution and module import
    try:
        from config import get_config, validate_environment
        from utils import (
            run_command, kubectl, helm, setup_logging,
            get_nodes, cordon_nodes, uncordon_nodes, wait_for_pods_ready
        )
        import device_tools
    except ImportError:
        import sys
        sys.path.append('..')
        from config import get_config, validate_environment
        from utils import (
            run_command, kubectl, helm, setup_logging,
            get_nodes, cordon_nodes, uncordon_nodes, wait_for_pods_ready
        )
        import device_tools

logger = logging.getLogger(__name__)

class NetworkOperatorOps:
    """Network Operator operational commands"""
    
    def __init__(self):
        self.config = get_config()
    
    # Network Resource Management
    def get_network_status(self) -> Dict[str, Any]:
        """Get comprehensive network status - equivalent to getnetwork.sh"""
        status = {
            "network_attachments": [],
            "nic_cluster_policy": {},
            "node_resources": {},
            "pods_network_status": []
        }
        
        logger.info("Getting Network Attachment Definitions...")
        result = kubectl("get", "network-attachment-definitions", "-A", output="json")
        if result.success:
            try:
                data = json.loads(result.stdout)
                status["network_attachments"] = data.get("items", [])
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse network-attachment-definitions output: {e}")

        logger.info("Getting NicClusterPolicy...")
        result = kubectl("get", "NicClusterPolicy", "nic-cluster-policy", output="json")
        if result.success:
            try:
                status["nic_cluster_policy"] = json.loads(result.stdout)
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse NicClusterPolicy output: {e}")
        
        # Get worker nodes (excluding cordoned nodes)
        all_worker_nodes = get_nodes("worker")
        result = kubectl("get", "nodes", "--no-headers")
        if result.success:
            worker_nodes = [
                n for n in all_worker_nodes
                if not any(n in line and "SchedulingDisabled" in line
                           for line in result.stdout.strip().split('\n'))
            ]
            
            # Get node resources and network status
            for node in worker_nodes:
                logger.info(f"Checking node: {node}")
                
                # Get node description
                result = kubectl("describe", "node", node)
                if result.success:
                    status["node_resources"][node] = result.stdout
                
                # Get pods network status on this node
                result = kubectl("get", "pods", "-A", 
                               f"--field-selector=spec.nodeName={node}",
                               output="custom-columns=NAME:metadata.name,NODE:spec.nodeName,NETWORK-STATUS:metadata.annotations.k8s\\.v1\\.cni\\.cncf\\.io/network-status")
                if result.success:
                    status["pods_network_status"].append({
                        "node": node,
                        "pods": result.stdout
                    })
        
        return status
    
    def create_values_yaml(self, version: Optional[str] = None) -> str:
        """Generate Helm values.yaml - equivalent to mk-values.sh"""
        if version is None:
            version = self.config.netop_version
        
        logger.info(f"Generating values.yaml for version {version}")
        
        # Determine IPAM type
        nv_ipam_enabled = self.config.ipam_type == "nv-ipam"
        
        values = {
            "nfd": {
                "enabled": self.config.nfd_enable,
                "NodeFeatureRule": self.config.nfd_enable
            },
            "nicConfigurationOperator": {
                "enabled": self.config.nic_config_enable
            },
            "maintenanceOperator": {
                "enabled": self.config.nic_config_enable
            },
            "deployCR": True,
            "nvIpam": {
                "deploy": nv_ipam_enabled
            }
        }
        
        # Add SR-IOV Network Operator settings
        if self.config.usecase in ["sriovnet_rdma", "sriovibnet_rdma"]:
            values["sriovNetworkOperator"] = {
                "enabled": True
            }
            values["sriov-network-operator"] = {
                "sriovOperatorConfig": {
                    "configDaemonNodeSelector": {
                        f"node-role.kubernetes.io/{self.config.worker_node}": ""
                    },
                    "featureGates": {
                        "parallelNicConfig": True,
                        "mellanoxFirmwareReset": False
                    }
                }
            }
        
        # Add OFED driver settings
        if self.config.ofed_enable:
            values["ofedDriver"] = {
                "deploy": True,
                "env": [
                    {"name": "RESTORE_DRIVER_ON_POD_TERMINATION", "value": "true"},
                    {"name": "UNLOAD_STORAGE_MODULES", "value": "true"},
                    {"name": "CREATE_IFNAMES_UDEV", "value": "true"}
                ]
            }
        
        # Add device plugin settings based on use case
        if self.config.usecase in ["ipoib_rdma_shared_device", "macvlan_rdma_shared_device"]:
            values["rdmaSharedDevicePlugin"] = {
                "deploy": True,
                "resources": self._get_device_resources(include_link_types=True)
            }
        elif self.config.usecase == "hostdev_rdma_sriov":
            values["sriovDevicePlugin"] = {
                "deploy": True,
                "resources": self._get_device_resources()
            }
        
        # Add secondary network settings
        values["secondaryNetwork"] = {
            "deploy": True,
            "multus": {"deploy": True},
            "cniPlugins": {"deploy": True},
            "ipamPlugin": {"deploy": not nv_ipam_enabled}
        }
        
        # Add image pull secrets for staging
        if not self.config.prod_version:
            values["imagePullSecrets"] = ["ngc-image-secret"]
        
        if not _YAML_AVAILABLE:
            raise ImportError("pyyaml is required for YAML output. Install with: pip install pyyaml")
        return yaml.dump(values, default_flow_style=False)
    
    def _get_device_resources(self, include_link_types: bool = False) -> List[Dict[str, Any]]:
        """Get device plugin resource list, optionally including linkTypes for RDMA shared device"""
        resources = []
        for i, _device_type in enumerate(self.config.device_types):
            resource: Dict[str, Any] = {
                "name": f"{self.config.netop_vendor}_{i}",
                "vendors": [self.config.netop_vendor]
            }
            if include_link_types:
                if self.config.usecase == "ipoib_rdma_shared_device":
                    resource["linkTypes"] = ["IB"]
                elif self.config.usecase == "macvlan_rdma_shared_device":
                    resource["linkTypes"] = ["ether"]
            resources.append(resource)
        return resources
    
    def apply_network_cr(self, cr_file: Optional[str] = None) -> bool:
        """Apply network custom resource - equivalent to apply-network-cr.sh"""
        if cr_file is None:
            cr_file = "network-cr.yaml"
        
        if not os.path.exists(cr_file):
            logger.error(f"Network CR file not found: {cr_file}")
            return False
        
        logger.info(f"Applying network CR: {cr_file}")
        result = kubectl("apply", "-f", cr_file)
        
        if result.success:
            logger.info("Network CR applied successfully")
            # Wait for pods to be ready
            return wait_for_pods_ready(self.config.netop_namespace)
        else:
            logger.error(f"Failed to apply network CR: {result.stderr}")
            return False
    
    def delete_network_cr(self, cr_file: Optional[str] = None) -> bool:
        """Delete network custom resource - equivalent to delete-network-cr.sh"""
        if cr_file is None:
            cr_file = "network-cr.yaml"
        
        if not os.path.exists(cr_file):
            logger.warning(f"Network CR file not found: {cr_file}")
        
        logger.info(f"Deleting network CR: {cr_file}")
        result = kubectl("delete", "-f", cr_file)
        
        if result.success:
            logger.info("Network CR deleted successfully")
            return True
        else:
            logger.error(f"Failed to delete network CR: {result.stderr}")
            return False
    
    # Node Management
    def label_worker_nodes(self, label: str, value: str = "") -> bool:
        """Label worker nodes - equivalent to labelworker.sh"""
        worker_nodes = get_nodes("worker")
        if not worker_nodes:
            logger.warning("No worker nodes found")
            return False

        success = True
        for node in worker_nodes:
            logger.info(f"Labeling node {node} with {label}={value}")
            label_str = f"{label}={value}" if value else label
            result = kubectl("label", "node", node, label_str)
            if not result.success:
                logger.error(f"Failed to label node {node}")
                success = False
        
        return success
    
    def annotate_node(self, node: str, annotation: str, value: str) -> bool:
        """Annotate a node - equivalent to annotatenode.sh"""
        logger.info(f"Annotating node {node} with {annotation}={value}")
        result = kubectl("annotate", "node", node, f"{annotation}={value}")
        
        if result.success:
            logger.info(f"Node {node} annotated successfully")
            return True
        else:
            logger.error(f"Failed to annotate node {node}: {result.stderr}")
            return False
    
    # Device Management
    def set_num_vfs(self, num_vfs: int, devices: Optional[List[str]] = None) -> bool:
        """Set number of VFs - equivalent to setnumvfs.sh"""
        if devices is None:
            devices = self._detect_sriov_devices()
        logger.info(f"Setting {num_vfs} VFs for devices: {devices}")
        return device_tools.set_sriov_vfs(num_vfs, devices)

    def get_num_vfs(self, devices: Optional[List[str]] = None) -> Dict[str, int]:
        """Get number of VFs - equivalent to getnumvfs.sh"""
        if devices is None:
            devices = self._detect_sriov_devices()

        vf_counts = {}
        for device in devices:
            vf_paths = [p for p in Path("/sys").rglob("sriov_numvfs") if device in str(p)]
            if not vf_paths:
                logger.warning(f"VF path not found for device: {device}")
                vf_counts[device] = -1
                continue
            for vf_path in vf_paths:
                try:
                    with open(vf_path, 'r') as f:
                        vf_counts[device] = int(f.read().strip())
                except Exception as e:
                    logger.error(f"Failed to read VF count for {device}: {e}")
                    vf_counts[device] = -1

        return vf_counts

    def _detect_sriov_devices(self) -> List[str]:
        """Detect SR-IOV capable devices"""
        devices = []
        for sriov_path in Path("/sys").rglob("sriov_numvfs"):
            for part in str(sriov_path).split('/'):
                if ':' in part and len(part.split(':')) >= 3:
                    if part not in devices:
                        devices.append(part)
                    break
        return devices
    
    # Resource Checking
    def check_ipam(self) -> Dict[str, Any]:
        """Check IPAM status - equivalent to checkipam.sh"""
        ipam_status = {
            "type": self.config.ipam_type,
            "pools": [],
            "claims": []
        }
        
        if self.config.ipam_type == "nv-ipam":
            # Check IPPools
            result = kubectl("get", "ippools", "-A", output="json")
            if result.success:
                try:
                    data = json.loads(result.stdout)
                    ipam_status["pools"] = data.get("items", [])
                except json.JSONDecodeError as e:
                    logger.error(f"Failed to parse ippools output: {e}")

            # Check IPAMClaims
            result = kubectl("get", "ipamclaims", "-A", output="json")
            if result.success:
                try:
                    data = json.loads(result.stdout)
                    ipam_status["claims"] = data.get("items", [])
                except json.JSONDecodeError as e:
                    logger.error(f"Failed to parse ipamclaims output: {e}")
        
        return ipam_status
    
    def check_sriov_state(self) -> Dict[str, Any]:
        """Check SR-IOV node state - equivalent to checksriovstate.sh"""
        sriov_state = {
            "node_policies": [],
            "node_states": [],
            "networks": []
        }
        
        # Get SR-IOV Network Node Policies
        result = kubectl("get", "sriovnetworknodepolicies", "-A", output="json")
        if result.success:
            try:
                data = json.loads(result.stdout)
                sriov_state["node_policies"] = data.get("items", [])
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse sriovnetworknodepolicies output: {e}")

        # Get SR-IOV Network Node States
        result = kubectl("get", "sriovnetworknodestates", "-A", output="json")
        if result.success:
            try:
                data = json.loads(result.stdout)
                sriov_state["node_states"] = data.get("items", [])
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse sriovnetworknodestates output: {e}")

        # Get SR-IOV Networks
        result = kubectl("get", "sriovnetworks", "-A", output="json")
        if result.success:
            try:
                data = json.loads(result.stdout)
                sriov_state["networks"] = data.get("items", [])
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse sriovnetworks output: {e}")
        
        return sriov_state

def create_ops_parser(subparsers):
    """Create ops command parser"""
    ops_parser = subparsers.add_parser(
        "ops",
        help="Network Operator operational commands"
    )
    
    ops_subparsers = ops_parser.add_subparsers(
        dest="ops_action",
        help="Operations commands"
    )
    
    # Network management commands
    net_parser = ops_subparsers.add_parser("network", help="Network management")
    net_subparsers = net_parser.add_subparsers(dest="network_action")
    
    net_subparsers.add_parser("status", help="Get network status")
    
    apply_parser = net_subparsers.add_parser("apply", help="Apply network CR")
    apply_parser.add_argument("--file", help="CR file to apply")
    
    delete_parser = net_subparsers.add_parser("delete", help="Delete network CR")
    delete_parser.add_argument("--file", help="CR file to delete")
    
    # Configuration commands
    config_parser = ops_subparsers.add_parser("config", help="Configuration management")
    config_subparsers = config_parser.add_subparsers(dest="config_action")
    
    values_parser = config_subparsers.add_parser("values", help="Generate values.yaml")
    values_parser.add_argument("--version", help="Network Operator version")
    values_parser.add_argument("--output", help="Output file")
    
    # Node management commands
    node_parser = ops_subparsers.add_parser("node", help="Node management")
    node_subparsers = node_parser.add_subparsers(dest="node_action")
    
    label_parser = node_subparsers.add_parser("label", help="Label worker nodes")
    label_parser.add_argument("label", help="Label name")
    label_parser.add_argument("value", nargs="?", default="", help="Label value")
    
    annotate_parser = node_subparsers.add_parser("annotate", help="Annotate node")
    annotate_parser.add_argument("node", help="Node name")
    annotate_parser.add_argument("annotation", help="Annotation name")
    annotate_parser.add_argument("value", help="Annotation value")
    
    node_subparsers.add_parser("cordon", help="Cordon worker nodes")
    node_subparsers.add_parser("uncordon", help="Uncordon worker nodes")
    
    # Device management commands
    device_parser = ops_subparsers.add_parser("device", help="Device management")
    device_subparsers = device_parser.add_subparsers(dest="device_action")
    
    setvfs_parser = device_subparsers.add_parser("set-vfs", help="Set number of VFs")
    setvfs_parser.add_argument("num_vfs", type=int, help="Number of VFs")
    setvfs_parser.add_argument("--devices", nargs="+", help="Device identifiers")
    
    device_subparsers.add_parser("get-vfs", help="Get VF counts")
    
    # Check commands
    check_parser = ops_subparsers.add_parser("check", help="Status checking")
    check_subparsers = check_parser.add_subparsers(dest="check_action")
    
    check_subparsers.add_parser("ipam", help="Check IPAM status")
    check_subparsers.add_parser("sriov", help="Check SR-IOV state")
    
    return ops_parser

def handle_ops_command(args):
    """Handle ops commands"""
    ops = NetworkOperatorOps()
    
    if args.ops_action == "network":
        if args.network_action == "status":
            status = ops.get_network_status()
            print(json.dumps(status, indent=2))
            return 0
        elif args.network_action == "apply":
            success = ops.apply_network_cr(args.file)
            return 0 if success else 1
        elif args.network_action == "delete":
            success = ops.delete_network_cr(args.file)
            return 0 if success else 1
    
    elif args.ops_action == "config":
        if args.config_action == "values":
            values_yaml = ops.create_values_yaml(args.version)
            if args.output:
                with open(args.output, 'w') as f:
                    f.write(values_yaml)
                print(f"Values.yaml written to {args.output}")
            else:
                print(values_yaml)
            return 0
    
    elif args.ops_action == "node":
        if args.node_action == "label":
            success = ops.label_worker_nodes(args.label, args.value)
            return 0 if success else 1
        elif args.node_action == "annotate":
            success = ops.annotate_node(args.node, args.annotation, args.value)
            return 0 if success else 1
        elif args.node_action == "cordon":
            success = cordon_nodes()
            return 0 if success else 1
        elif args.node_action == "uncordon":
            success = uncordon_nodes()
            return 0 if success else 1
    
    elif args.ops_action == "device":
        if args.device_action == "set-vfs":
            success = ops.set_num_vfs(args.num_vfs, args.devices)
            return 0 if success else 1
        elif args.device_action == "get-vfs":
            vf_counts = ops.get_num_vfs()
            for device, count in vf_counts.items():
                print(f"{device}: {count}")
            return 0
    
    elif args.ops_action == "check":
        if args.check_action == "ipam":
            status = ops.check_ipam()
            print(json.dumps(status, indent=2))
            return 0
        elif args.check_action == "sriov":
            status = ops.check_sriov_state()
            print(json.dumps(status, indent=2))
            return 0
    
    print(f"Unknown ops action: {args.ops_action}")
    return 1 