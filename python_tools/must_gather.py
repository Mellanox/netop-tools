#!/usr/bin/env python3
"""
NVIDIA Network Operator Tools - Must Gather
Python conversion of must-gather-network.sh for network operator diagnostics
"""
import os
import sys
import argparse
import logging
import json
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional, TextIO

try:
    from .config import get_config
    from .utils import run_command, kubectl, setup_logging
except ImportError:
    from config import get_config
    from utils import run_command, kubectl, setup_logging

logger = logging.getLogger(__name__)

class NetworkOperatorMustGather:
    """Network Operator must-gather functionality"""
    
    def __init__(self, artifact_dir: Optional[str] = None):
        """
        Initialize must-gather tool
        
        Args:
            artifact_dir: Directory to store artifacts (default: auto-generated)
        """
        self.config = get_config()
        
        self.artifact_dir = self.create_artifact_dir(artifact_dir)
        
        # Setup logging to file
        self.setup_file_logging("must-gather.log")
        
        logger.info(f"Network Operator must-gather started")
        logger.info(f"Artifact directory: {self.artifact_dir}")

    @staticmethod
    def create_artifact_dir(artifact_dir: Optional[str]) -> Path:
        """Create a private artifact directory that cannot be pre-planted."""
        if artifact_dir is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            path = Path(tempfile.mkdtemp(prefix=f"nvidia-network-operator_{timestamp}_", dir="/tmp"))
        else:
            path = Path(artifact_dir)
            if path.exists() or path.is_symlink():
                raise FileExistsError(f"refusing to use existing artifact directory: {path}")
            path.mkdir(mode=0o700, parents=True, exist_ok=False)

        os.chmod(path, 0o700)
        return path

    def artifact_path(self, relpath: str) -> Path:
        """Return an artifact path for a simple relative output name."""
        path = Path(relpath)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError(f"artifact path must stay inside output directory: {relpath}")
        return self.artifact_dir / path

    def open_artifact(self, relpath: str) -> TextIO:
        """Create a new artifact file without following a pre-existing path."""
        path = self.artifact_path(relpath)
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(path, flags, 0o600)
        return os.fdopen(fd, "w", encoding="utf-8")

    def write_artifact(self, relpath: str, text: str) -> None:
        with self.open_artifact(relpath) as f:
            f.write(text)
    
    def setup_file_logging(self, log_name: str):
        """Setup logging to file in addition to console"""
        log_file = self.artifact_path(log_name)
        root_logger = logging.getLogger()
        # Avoid adding duplicate handlers if called more than once
        if any(getattr(h, 'baseFilename', None) == str(log_file) for h in root_logger.handlers):
            return

        stream = self.open_artifact(log_name)
        file_handler = logging.StreamHandler(stream)
        file_handler.baseFilename = str(log_file)
        file_handler.setLevel(logging.DEBUG)
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        file_handler.setFormatter(formatter)
        root_logger.addHandler(file_handler)
    
    def detect_platform(self) -> Dict[str, str]:
        """Detect platform (OpenShift vs standard Kubernetes)"""
        platform_info = {
            "type": "kubernetes",
            "version": "unknown"
        }
        
        # Check for OpenShift cluster version
        result = kubectl("get", "clusterversion/version", "--ignore-not-found", output="name")
        
        if result.success and result.stdout.strip():
            platform_info["type"] = "openshift"
            logger.info("Detected OpenShift platform")
            
            # Get OpenShift version details
            result = kubectl("get", "clusterversion/version", output="yaml")
            if result.success:
                try:
                    self.write_artifact("openshift_version.yaml", result.stdout)
                except OSError as e:
                    logger.warning(f"Failed to write openshift_version.yaml: {e}")
        else:
            logger.info("Detected standard Kubernetes platform")
        
        return platform_info
    
    def find_operator_namespace(self) -> Optional[str]:
        """Find the Network Operator namespace"""
        result = kubectl("get", "pods", "-l", "app.kubernetes.io/name=network-operator", "-A", output="json")
        
        if not result.success:
            logger.error("Failed to find Network Operator pods")
            return None
        
        try:
            data = json.loads(result.stdout)
            pods = data.get('items', [])
            
            if not pods:
                logger.error("No Network Operator pods found")
                return None
            
            # Get namespace from first pod
            namespace = pods[0]['metadata']['namespace']
            logger.info(f"Found Network Operator in namespace: {namespace}")
            return namespace
            
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse kubectl output: {e}")
            return None
    
    def gather_operator_pod_info(self, namespace: str) -> bool:
        """Gather Network Operator pod information"""
        logger.info("Gathering Network Operator pod information...")
        
        # Find operator pod
        result = kubectl("get", "pods", "-l", "app.kubernetes.io/name=network-operator", 
                        namespace=namespace, output="name")
        
        if not result.success or not result.stdout.strip():
            logger.error("Could not find Network Operator pod")
            return False
        
        operator_pod_name = result.stdout.strip().replace('pod/', '')
        logger.info(f"Found operator pod: {operator_pod_name}")
        
        # Get pod status
        result = kubectl("get", "pod", operator_pod_name, "-owide", namespace=namespace)
        if result.success:
            self.write_artifact("network_operator_pod.status", result.stdout)
        
        # Get pod YAML
        result = kubectl("get", "pod", operator_pod_name, "-oyaml", namespace=namespace)
        if result.success:
            self.write_artifact("network_operator_pod.yaml", result.stdout)
        
        # Get pod logs
        result = kubectl("logs", operator_pod_name, namespace=namespace)
        if result.success:
            self.write_artifact("network_operator_pod.log", result.stdout)
        
        # Get previous pod logs
        result = kubectl("logs", operator_pod_name, "--previous", namespace=namespace)
        if result.success:
            self.write_artifact("network_operator_pod.previous.log", result.stdout)
        
        return True
    
    def gather_operand_pods_info(self, namespace: str) -> bool:
        """Gather operand pods information"""
        logger.info("Gathering operand pods information...")
        
        # Get all pods in namespace (status)
        result = kubectl("get", "pods", "-owide", namespace=namespace)
        if result.success:
            self.write_artifact("network_operand_pods.status", result.stdout)
        
        # Get all pods in namespace (YAML)
        result = kubectl("get", "pods", "-oyaml", namespace=namespace)
        if result.success:
            self.write_artifact("network_operand_pods.yaml", result.stdout)
        
        # Get pod images
        result = kubectl("get", "pods", namespace=namespace, 
                        output="jsonpath='{range .items[*]}{\"\\n\"}{.metadata.name}{\":\\t\"}{range .spec.containers[*]}{.image}{\" \"}{end}{end}'")
        if result.success:
            self.write_artifact("network_operand_pod_images.txt", result.stdout)
        
        # Get individual pod logs and descriptions
        result = kubectl("get", "pods", namespace=namespace, output="json")
        if not result.success:
            logger.error("Failed to get pods JSON for detailed collection")
            return False

        try:
            data = json.loads(result.stdout)
            pods = data.get('items', [])

            for pod in pods:
                pod_name = pod['metadata']['name']

                # Skip operator pod (already handled) — check labels dict directly
                labels = pod.get('metadata', {}).get('labels', {})
                if labels.get('app.kubernetes.io/name') == 'network-operator':
                    continue

                # Get pod logs
                result = kubectl("logs", pod_name, "--all-containers", "--prefix", namespace=namespace)
                if result.success:
                    self.write_artifact(f"network_operand_pod_{pod_name}.log", result.stdout)

                # Get previous pod logs
                result = kubectl("logs", pod_name, "--all-containers", "--prefix", "--previous", namespace=namespace)
                if result.success:
                    self.write_artifact(f"network_operand_pod_{pod_name}.previous.log", result.stdout)

                # Get pod description
                result = kubectl("describe", "pod", pod_name, namespace=namespace)
                if result.success:
                    self.write_artifact(f"network_operand_pod_{pod_name}.descr", result.stdout)

        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse pods JSON: {e}")
            return False

        return True
    
    def gather_daemonsets_info(self, namespace: str) -> bool:
        """Gather DaemonSets information"""
        logger.info("Gathering DaemonSets information...")
        
        # Get DaemonSets status
        result = kubectl("get", "ds", namespace=namespace)
        if result.success:
            self.write_artifact("network_operand_ds.status", result.stdout)
        
        # Get DaemonSets YAML
        result = kubectl("get", "ds", "-oyaml", namespace=namespace)
        if result.success:
            self.write_artifact("network_operand_ds.yaml", result.stdout)
        
        # Get individual DaemonSet descriptions
        result = kubectl("get", "ds", namespace=namespace, output="name")
        if result.success:
            for ds_name in result.stdout.strip().split('\n'):
                if ds_name:
                    ds_short_name = ds_name.replace('daemonset/', '')
                    result = kubectl("describe", "ds", ds_short_name, namespace=namespace)
                    if result.success:
                        self.write_artifact(f"network_operand_ds_{ds_short_name}.descr", result.stdout)
        
        return True
    
    def gather_custom_resources(self, namespace: str) -> bool:
        """Gather custom resources related to Network Operator"""
        logger.info("Gathering custom resources...")
        
        # Common Network Operator CRDs
        crds = [
            "nicclusterpolicies",
            "sriovnetworknodepolicies", 
            "sriovnetworks",
            "sriovnetworknodestates",
            "network-attachment-definitions",
            "ipamclaims",
            "ippools",
            "cidrpools"
        ]
        
        for crd in crds:
            # Get CRD instances
            result = kubectl("get", crd, "-A", output="yaml")
            if result.success and result.stdout.strip():
                self.write_artifact(f"custom_resource_{crd}.yaml", result.stdout)
                logger.debug(f"Gathered {crd} custom resources")
        
        return True
    
    def gather_node_info(self) -> bool:
        """Gather node information"""
        logger.info("Gathering node information...")
        
        # Get nodes
        result = kubectl("get", "nodes", "-owide")
        if result.success:
            self.write_artifact("nodes.status", result.stdout)
        
        # Get nodes YAML
        result = kubectl("get", "nodes", "-oyaml")
        if result.success:
            self.write_artifact("nodes.yaml", result.stdout)
        
        # Get node descriptions
        result = kubectl("get", "nodes", output="name")
        if result.success:
            for node_name in result.stdout.strip().split('\n'):
                if node_name:
                    node_short_name = node_name.replace('node/', '')
                    result = kubectl("describe", "node", node_short_name)
                    if result.success:
                        self.write_artifact(f"node_{node_short_name}.descr", result.stdout)
        
        return True
    
    def gather_events(self, namespace: str) -> bool:
        """Gather events"""
        logger.info("Gathering events...")
        
        # Get events in operator namespace
        result = kubectl("get", "events", namespace=namespace, output="yaml")
        if result.success:
            self.write_artifact("events_operator_namespace.yaml", result.stdout)
        
        # Get cluster-wide events
        result = kubectl("get", "events", "-A", output="yaml")
        if result.success:
            self.write_artifact("events_all_namespaces.yaml", result.stdout)
        
        return True
    
    def create_version_info(self):
        """Create version information file"""
        version_info = {
            "network_operator_version": self.config.netop_version,
            "collection_time": datetime.now().isoformat(),
            "netop_tools_version": "1.0.0"
        }
        try:
            self.write_artifact(
                "version",
                "Network Operator\n"
                f"{version_info['network_operator_version']}\n"
                f"Collection time: {version_info['collection_time']}\n",
            )
        except OSError as e:
            logger.warning(f"Failed to write version file: {e}")
    
    def run_must_gather(self) -> bool:
        """Run complete must-gather collection"""
        logger.info("Starting Network Operator must-gather collection...")
        
        try:
            # Create version info
            self.create_version_info()
            
            # Detect platform
            platform_info = self.detect_platform()
            
            # Find operator namespace
            operator_namespace = self.find_operator_namespace()
            if not operator_namespace:
                logger.error("Could not find Network Operator namespace")
                return False
            
            # Gather information
            success = True
            
            if not self.gather_operator_pod_info(operator_namespace):
                success = False
            
            if not self.gather_operand_pods_info(operator_namespace):
                success = False
            
            if not self.gather_daemonsets_info(operator_namespace):
                success = False
            
            if not self.gather_custom_resources(operator_namespace):
                success = False
            
            if not self.gather_node_info():
                success = False
            
            if not self.gather_events(operator_namespace):
                success = False
            
            if success:
                logger.info("Must-gather collection completed successfully")
                logger.info(f"Artifacts saved to: {self.artifact_dir}")
            else:
                logger.warning("Must-gather collection completed with some errors")
            
            return success
            
        except Exception as e:
            logger.error(f"Must-gather collection failed: {e}")
            return False

def main():
    """Main function for must-gather tool"""
    parser = argparse.ArgumentParser(
        description="Collect Network Operator diagnostics",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s
    # Collect diagnostics to auto-generated directory
    
  %(prog)s --output-dir /tmp/my-must-gather
    # Collect diagnostics to specific directory
        """
    )
    
    parser.add_argument(
        "--output-dir",
        help="New output directory for collected artifacts; must not already exist"
    )
    
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose output"
    )
    
    args = parser.parse_args()
    
    # Setup logging
    setup_logging("DEBUG" if args.verbose else "INFO")
    
    try:
        # Create must-gather instance
        must_gather = NetworkOperatorMustGather(args.output_dir)
        
        # Run collection
        success = must_gather.run_must_gather()
        
        if success:
            print(f"\nMust-gather collection completed successfully!")
            print(f"Artifacts saved to: {must_gather.artifact_dir}")
            return 0
        else:
            print(f"\nMust-gather collection failed!")
            print(f"Check logs in: {must_gather.artifact_dir}/must-gather.log")
            return 1
            
    except Exception as e:
        logger.error(f"Error: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
