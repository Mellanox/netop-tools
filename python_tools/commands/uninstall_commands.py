#!/usr/bin/env python3
"""
NVIDIA Network Operator Tools - Uninstallation Commands
Python implementation of uninstall/ directory bash scripts
"""
import os
import sys
import argparse
import logging
import json
import time
from pathlib import Path
from typing import List, Dict, Optional, Any

try:
    from ..config import get_config, validate_environment
    from ..utils import (
        run_command, kubectl, helm, setup_logging
    )
except ImportError:
    # Handle both direct execution and module import
    try:
        from config import get_config, validate_environment
        from utils import (
            run_command, kubectl, helm, setup_logging
        )
    except ImportError:
        import sys
        sys.path.append('..')
        from config import get_config, validate_environment
        from utils import (
            run_command, kubectl, helm, setup_logging
        )

logger = logging.getLogger(__name__)

class NetworkOperatorUninstaller:
    """Network Operator uninstallation commands"""
    
    def __init__(self):
        self.config = get_config()
    
    def uninstall_network_operator(self) -> bool:
        """Uninstall Network Operator - equivalent to uninstall/unins-network-operator.sh"""
        logger.info("Uninstalling NVIDIA Network Operator")
        
        success = True
        
        # Delete CRDs first
        if not self._delete_crds():
            success = False
        
        # Delete network attachment definitions
        if not self._delete_network_attachment_definitions():
            success = False
        
        # Delete Network Operator specific resources
        if not self._delete_nic_resources():
            success = False
        
        # Delete NicClusterPolicy
        if not self._delete_nic_cluster_policy():
            success = False
        
        # Uninstall Helm chart
        if not self._uninstall_helm_chart():
            success = False
        
        # Force delete namespace
        if not self._delete_namespace():
            success = False
        
        return success
    
    def _delete_crds(self) -> bool:
        """Delete Network Operator CRDs"""
        logger.info("Deleting Network Operator CRDs...")
        
        # Get list of CRDs to delete
        crd_patterns = [
            "sriov", "mellanox.com", "nodefeature", "nvidia.com",
            "configuration.net.nvidia.com", "maintenance.nvidia.com"
        ]
        
        # Get all CRDs
        result = kubectl("get", "crd", "--no-headers")
        if not result.success:
            logger.error("Failed to get CRDs")
            return False
        
        crds_to_delete = []
        for line in result.stdout.strip().split('\n'):
            if line:
                crd_name = line.split()[0]
                for pattern in crd_patterns:
                    if pattern in crd_name:
                        crds_to_delete.append(crd_name)
                        break
        
        success = True
        for crd in crds_to_delete:
            logger.info(f"Deleting CRD: {crd}")
            result = kubectl("delete", "crd", crd, "--ignore-not-found=true")
            if not result.success:
                logger.error(f"Failed to delete CRD {crd}: {result.stderr}")
                success = False
        
        return success
    
    def _delete_network_attachment_definitions(self) -> bool:
        """Delete Network Attachment Definitions"""
        logger.info("Deleting Network Attachment Definitions...")
        
        # Get all network attachment definitions
        result = kubectl("get", "network-attachment-definitions", "-A", "--no-headers")
        if not result.success:
            logger.warning("Failed to get network attachment definitions")
            return True  # Not critical if they don't exist
        
        success = True
        for line in result.stdout.strip().split('\n'):
            if line:
                parts = line.split()
                if len(parts) >= 2:
                    namespace = parts[0]
                    name = parts[1]
                    
                    logger.info(f"Deleting network attachment definition: {namespace}/{name}")
                    result = kubectl("delete", "network-attachment-definitions", name, 
                                   "--ignore-not-found=true", namespace=namespace)
                    if not result.success:
                        logger.error(f"Failed to delete network attachment definition {namespace}/{name}")
                        success = False
        
        return success
    
    def _delete_nic_resources(self) -> bool:
        """Delete NIC-specific resources"""
        logger.info("Deleting NIC-specific resources...")
        
        nic_resources = [
            "nicdevices.configuration.net.nvidia.com",
            "nicconfigurationtemplates.configuration.net.nvidia.com",
            "nodemaintenances.maintenance.nvidia.com",
            "maintenanceoperatorconfigs.maintenance.nvidia.com"
        ]
        
        success = True
        for resource in nic_resources:
            logger.info(f"Deleting {resource} resources...")
            
            # Get all instances of this resource
            result = kubectl("get", resource, "-A", "--no-headers")
            if result.success:
                for line in result.stdout.strip().split('\n'):
                    if line:
                        parts = line.split()
                        if len(parts) >= 2:
                            namespace = parts[0]
                            name = parts[1]
                            
                            logger.info(f"Deleting {resource}: {namespace}/{name}")
                            del_result = kubectl("delete", resource, name, "--ignore-not-found=true", namespace=namespace)
                            if not del_result.success:
                                logger.error(f"Failed to delete {resource} {namespace}/{name}: {del_result.stderr}")
                                success = False
            
            # Delete the CRD
            result = kubectl("delete", "crd", resource, "--ignore-not-found=true")
            if not result.success:
                logger.warning(f"Failed to delete CRD {resource}")
                success = False
        
        return success
    
    def _delete_nic_cluster_policy(self) -> bool:
        """Delete NicClusterPolicy"""
        logger.info("Deleting NicClusterPolicy...")
        
        result = kubectl("delete", "NicClusterPolicy", "nic-cluster-policy", "--ignore-not-found=true")
        if result.success:
            logger.info("NicClusterPolicy deleted successfully")
            return True
        else:
            logger.error(f"Failed to delete NicClusterPolicy: {result.stderr}")
            return False
    
    def _uninstall_helm_chart(self) -> bool:
        """Uninstall Helm chart"""
        logger.info("Uninstalling Network Operator Helm chart...")
        
        result = helm("uninstall", "network-operator", "--namespace", self.config.netop_namespace, "--no-hooks")
        
        if result.success:
            logger.info("Helm chart uninstalled successfully")
            return True
        else:
            logger.warning(f"Failed to uninstall Helm chart: {result.stderr}")
            return False  # Continue even if helm uninstall fails
    
    def _delete_namespace(self) -> bool:
        """Force delete namespace"""
        logger.info(f"Deleting namespace: {self.config.netop_namespace}")
        
        # First try normal delete
        result = kubectl("delete", "namespace", self.config.netop_namespace, "--ignore-not-found=true")
        
        if result.success:
            logger.info("Namespace deleted successfully")
            return True
        
        # If normal delete fails, try to force delete stuck namespace
        logger.warning("Normal namespace deletion failed, attempting to force delete...")
        return self._delete_stuck_namespace()
    
    def _delete_stuck_namespace(self) -> bool:
        """Delete stuck namespace - equivalent to uninstall/delstucknamespace.sh"""
        logger.info(f"Force deleting stuck namespace: {self.config.netop_namespace}")
        
        # Get namespace as JSON
        result = kubectl("get", "namespace", self.config.netop_namespace, output="json")
        if not result.success:
            logger.info("Namespace already deleted")
            return True
        
        try:
            import tempfile
            namespace_data = json.loads(result.stdout)
            
            # Remove finalizers
            if 'finalizers' in namespace_data.get('spec', {}):
                namespace_data['spec']['finalizers'] = []
            
            # Save modified namespace to temp file
            with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
                json.dump(namespace_data, f)
                temp_file = f.name
            
            try:
                # Apply the modified namespace to remove finalizers
                result = kubectl("replace", "--raw", f"/api/v1/namespaces/{self.config.netop_namespace}/finalize",
                               "-f", temp_file)
                
                if result.success:
                    logger.info("Namespace finalizers removed")
                    return True
                else:
                    logger.error(f"Failed to remove namespace finalizers: {result.stderr}")
                    return False
            finally:
                os.unlink(temp_file)
                
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse namespace JSON: {e}")
            return False
    
    def delete_evicted_pods(self) -> bool:
        """Delete evicted pods - equivalent to uninstall/delevictedpods.sh"""
        logger.info("Deleting evicted pods...")
        
        # Get all evicted pods
        result = kubectl("get", "pods", "-A", "--field-selector=status.phase=Failed")
        if not result.success:
            logger.error("Failed to get evicted pods")
            return False
        
        success = True
        evicted_count = 0
        
        for line in result.stdout.strip().split('\n')[1:]:  # Skip header
            if line and 'Evicted' in line:
                parts = line.split()
                if len(parts) >= 2:
                    namespace = parts[0]
                    pod_name = parts[1]
                    
                    logger.info(f"Deleting evicted pod: {namespace}/{pod_name}")
                    result = kubectl("delete", "pod", pod_name, namespace=namespace)
                    if result.success:
                        evicted_count += 1
                    else:
                        logger.error(f"Failed to delete pod {namespace}/{pod_name}")
                        success = False
        
        logger.info(f"Deleted {evicted_count} evicted pods")
        return success
    
    def delete_secret(self, secret_name: str = "ngc-image-secret") -> bool:
        """Delete secret - equivalent to uninstall/delsecret.sh"""
        logger.info(f"Deleting secret: {secret_name}")
        
        result = kubectl("delete", "secret", secret_name, 
                        "--ignore-not-found=true", namespace=self.config.netop_namespace)
        
        if result.success:
            logger.info(f"Secret {secret_name} deleted successfully")
            return True
        else:
            logger.error(f"Failed to delete secret {secret_name}: {result.stderr}")
            return False
    
    def uninstall_calico(self) -> bool:
        """Uninstall Calico - equivalent to uninstall/unins-calico.sh"""
        logger.info("Uninstalling Calico...")
        
        success = True
        
        # Delete Calico installation
        result = kubectl("delete", "installation", "default", "--ignore-not-found=true")
        if not result.success:
            logger.warning("Failed to delete Calico installation")
            success = False
        
        # Delete Calico operator
        result = kubectl("delete", "-f", 
                        "https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml",
                        "--ignore-not-found=true")
        if not result.success:
            logger.warning("Failed to delete Calico operator")
            success = False
        
        # Delete Calico namespaces
        calico_namespaces = ["calico-system", "calico-apiserver", "tigera-operator"]
        for namespace in calico_namespaces:
            result = kubectl("delete", "namespace", namespace, "--ignore-not-found=true")
            if not result.success:
                logger.warning(f"Failed to delete namespace {namespace}")
        
        return success

def create_uninstall_parser(subparsers):
    """Create uninstall command parser"""
    uninstall_parser = subparsers.add_parser(
        "uninstall",
        help="Uninstallation commands"
    )
    
    uninstall_subparsers = uninstall_parser.add_subparsers(
        dest="uninstall_action",
        help="Uninstallation commands"
    )
    
    # Network Operator uninstallation
    uninstall_subparsers.add_parser("network-operator", help="Uninstall Network Operator")
    
    # Calico uninstallation
    uninstall_subparsers.add_parser("calico", help="Uninstall Calico")
    
    # Cleanup commands
    uninstall_subparsers.add_parser("evicted-pods", help="Delete evicted pods")
    
    secret_parser = uninstall_subparsers.add_parser("secret", help="Delete secret")
    secret_parser.add_argument("--name", default="ngc-image-secret", help="Secret name to delete")
    
    return uninstall_parser

def handle_uninstall_command(args):
    """Handle uninstall commands"""
    uninstaller = NetworkOperatorUninstaller()
    
    if args.uninstall_action == "network-operator":
        success = uninstaller.uninstall_network_operator()
        return 0 if success else 1
    
    elif args.uninstall_action == "calico":
        success = uninstaller.uninstall_calico()
        return 0 if success else 1
    
    elif args.uninstall_action == "evicted-pods":
        success = uninstaller.delete_evicted_pods()
        return 0 if success else 1
    
    elif args.uninstall_action == "secret":
        success = uninstaller.delete_secret(args.name)
        return 0 if success else 1
    
    print(f"Unknown uninstall action: {args.uninstall_action}")
    return 1 