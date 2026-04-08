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
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional, Any

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
        
        if artifact_dir is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M")
            artifact_dir = f"/tmp/nvidia-network-operator_{timestamp}"
        
        self.artifact_dir = Path(artifact_dir)
        self.artifact_dir.mkdir(parents=True, exist_ok=True)
        
        # Setup logging to file
        log_file = self.artifact_dir / "must-gather.log"
        self.setup_file_logging(str(log_file))
        
        logger.info(f"Network Operator must-gather started")
        logger.info(f"Artifact directory: {self.artifact_dir}")
    
    def setup_file_logging(self, log_file: str):
        """Setup logging to file in addition to console"""
        root_logger = logging.getLogger()
        # Avoid adding duplicate handlers if called more than once
        if any(isinstance(h, logging.FileHandler) and getattr(h, 'baseFilename', None) == log_file
               for h in root_logger.handlers):
            return

        file_handler = logging.FileHandler(log_file)
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
                    with open(self.artifact_dir / "openshift_version.yaml", 'w') as f:
                        f.write(result.stdout)
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
            with open(self.artifact_dir / "network_operator_pod.status", 'w') as f:
                f.write(result.stdout)
        
        # Get pod YAML
        result = kubectl("get", "pod", operator_pod_name, "-oyaml", namespace=namespace)
        if result.success:
            with open(self.artifact_dir / "network_operator_pod.yaml", 'w') as f:
                f.write(result.stdout)
        
        # Get pod logs
        result = kubectl("logs", operator_pod_name, namespace=namespace)
        if result.success:
            with open(self.artifact_dir / "network_operator_pod.log", 'w') as f:
                f.write(result.stdout)
        
        # Get previous pod logs
        result = kubectl("logs", operator_pod_name, "--previous", namespace=namespace)
        if result.success:
            with open(self.artifact_dir / "network_operator_pod.previous.log", 'w') as f:
                f.write(result.stdout)
        
        return True
    
    def gather_operand_pods_info(self, namespace: str) -> bool:
        """Gather operand pods information"""
        logger.info("Gathering operand pods information...")
        
        # Get all pods in namespace (status)
        result = kubectl("get", "pods", "-owide", namespace=namespace)
        if result.success:
            with open(self.artifact_dir / "network_operand_pods.status", 'w') as f:
                f.write(result.stdout)
        
        # Get all pods in namespace (YAML)
        result = kubectl("get", "pods", "-oyaml", namespace=namespace)
        if result.success:
            with open(self.artifact_dir / "network_operand_pods.yaml", 'w') as f:
                f.write(result.stdout)
        
        # Get pod images
        result = kubectl("get", "pods", namespace=namespace, 
                        output="jsonpath='{range .items[*]}{\"\\n\"}{.metadata.name}{\":\\t\"}{range .spec.containers[*]}{.image}{\" \"}{end}{end}'")
        if result.success:
            with open(self.artifact_dir / "network_operand_pod_images.txt", 'w') as f:
                f.write(result.stdout)
        
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
                    with open(self.artifact_dir / f"network_operand_pod_{pod_name}.log", 'w') as f:
                        f.write(result.stdout)

                # Get previous pod logs
                result = kubectl("logs", pod_name, "--all-containers", "--prefix", "--previous", namespace=namespace)
                if result.success:
                    with open(self.artifact_dir / f"network_operand_pod_{pod_name}.previous.log", 'w') as f:
                        f.write(result.stdout)

                # Get pod description
                result = kubectl("describe", "pod", pod_name, namespace=namespace)
                if result.success:
                    with open(self.artifact_dir / f"network_operand_pod_{pod_name}.descr", 'w') as f:
                        f.write(result.stdout)

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
            with open(self.artifact_dir / "network_operand_ds.status", 'w') as f:
                f.write(result.stdout)
        
        # Get DaemonSets YAML
        result = kubectl("get", "ds", "-oyaml", namespace=namespace)
        if result.success:
            with open(self.artifact_dir / "network_operand_ds.yaml", 'w') as f:
                f.write(result.stdout)
        
        # Get individual DaemonSet descriptions
        result = kubectl("get", "ds", namespace=namespace, output="name")
        if result.success:
            for ds_name in result.stdout.strip().split('\n'):
                if ds_name:
                    ds_short_name = ds_name.replace('daemonset/', '')
                    result = kubectl("describe", "ds", ds_short_name, namespace=namespace)
                    if result.success:
                        with open(self.artifact_dir / f"network_operand_ds_{ds_short_name}.descr", 'w') as f:
                            f.write(result.stdout)
        
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
                with open(self.artifact_dir / f"custom_resource_{crd}.yaml", 'w') as f:
                    f.write(result.stdout)
                logger.debug(f"Gathered {crd} custom resources")
        
        return True
    
    def gather_node_info(self) -> bool:
        """Gather node information"""
        logger.info("Gathering node information...")
        
        # Get nodes
        result = kubectl("get", "nodes", "-owide")
        if result.success:
            with open(self.artifact_dir / "nodes.status", 'w') as f:
                f.write(result.stdout)
        
        # Get nodes YAML
        result = kubectl("get", "nodes", "-oyaml")
        if result.success:
            with open(self.artifact_dir / "nodes.yaml", 'w') as f:
                f.write(result.stdout)
        
        # Get node descriptions
        result = kubectl("get", "nodes", output="name")
        if result.success:
            for node_name in result.stdout.strip().split('\n'):
                if node_name:
                    node_short_name = node_name.replace('node/', '')
                    result = kubectl("describe", "node", node_short_name)
                    if result.success:
                        with open(self.artifact_dir / f"node_{node_short_name}.descr", 'w') as f:
                            f.write(result.stdout)
        
        return True
    
    def gather_events(self, namespace: str) -> bool:
        """Gather events"""
        logger.info("Gathering events...")
        
        # Get events in operator namespace
        result = kubectl("get", "events", namespace=namespace, output="yaml")
        if result.success:
            with open(self.artifact_dir / "events_operator_namespace.yaml", 'w') as f:
                f.write(result.stdout)
        
        # Get cluster-wide events
        result = kubectl("get", "events", "-A", output="yaml")
        if result.success:
            with open(self.artifact_dir / "events_all_namespaces.yaml", 'w') as f:
                f.write(result.stdout)
        
        return True
    
    def create_version_info(self):
        """Create version information file"""
        version_info = {
            "network_operator_version": self.config.netop_version,
            "collection_time": datetime.now().isoformat(),
            "netop_tools_version": "1.0.0"
        }
        try:
            with open(self.artifact_dir / "version", 'w') as f:
                f.write("Network Operator\n")
                f.write(f"{version_info['network_operator_version']}\n")
                f.write(f"Collection time: {version_info['collection_time']}\n")
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
        help="Output directory for collected artifacts"
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