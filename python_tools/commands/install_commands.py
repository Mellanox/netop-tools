#!/usr/bin/env python3
"""
NVIDIA Network Operator Tools - Installation Commands
Python implementation of install/ directory bash scripts
"""
import os
import sys
import argparse
import logging
import json
import tempfile
from pathlib import Path
from typing import List, Dict, Optional, Any

try:
    from ..config import get_config, validate_environment
    from ..utils import (
        run_command, kubectl, helm, setup_logging,
        wait_for_pods_ready, wait_for_nodes_ready, ensure_directory
    )
except ImportError:
    # Handle both direct execution and module import
    try:
        from config import get_config, validate_environment
        from utils import (
            run_command, kubectl, helm, setup_logging,
            wait_for_pods_ready, wait_for_nodes_ready, ensure_directory
        )
    except ImportError:
        import sys
        sys.path.append('..')
        from config import get_config, validate_environment
        from utils import (
            run_command, kubectl, helm, setup_logging,
            wait_for_pods_ready, wait_for_nodes_ready, ensure_directory
        )

logger = logging.getLogger(__name__)

class NetworkOperatorInstaller:
    """Network Operator installation commands"""
    
    def __init__(self):
        self.config = get_config()
    
    def install_helm(self) -> bool:
        """Install Helm - equivalent to install/ins-helm.sh"""
        logger.info("Installing Helm...")
        
        # Check if helm is already installed
        result = run_command(["helm", "version"], capture_output=True)
        if result.success:
            logger.info("Helm is already installed")
            return True
        
        # Download and install helm
        helm_install_script = "https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"
        
        # Download the installation script
        result = run_command(["curl", "-fsSL", helm_install_script], capture_output=True)
        if not result.success:
            logger.error("Failed to download Helm installation script")
            return False
        
        # Execute the installation script
        with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
            f.write(result.stdout)
            script_path = f.name
        
        try:
            os.chmod(script_path, 0o755)
            result = run_command(["/bin/bash", script_path])
            
            if result.success:
                logger.info("Helm installed successfully")
                return True
            else:
                logger.error(f"Failed to install Helm: {result.stderr}")
                return False
        finally:
            os.unlink(script_path)
    
    def install_network_operator_chart(self) -> bool:
        """Install Network Operator chart - equivalent to install/ins-netop-chart.sh"""
        logger.info(f"Installing Network Operator chart version {self.config.netop_version}")
        
        # Create chart directory
        chart_dir = Path(self.config.netop_root_dir) / "release" / self.config.netop_version / "netop-chart"
        ensure_directory(str(chart_dir))
        
        original_dir = os.getcwd()

        try:
            try:
                os.chdir(chart_dir)
            except OSError as e:
                logger.error(f"Failed to change to chart directory {chart_dir}: {e}")
                return False
            
            # Remove existing nvidia repo if present
            result = helm("repo", "list")
            if result.success and "nvidia" in result.stdout:
                helm("repo", "remove", "nvidia")
            
            # Add nvidia helm repo
            if self.config.prod_version:
                logger.info("Adding production Helm repository")
                result = helm("repo", "add", "nvidia", self.config.helm_nvidia_repo)
            else:
                logger.info("Adding staging Helm repository")
                ngc_api_key = os.environ.get('NGC_API_KEY', '')
                if not ngc_api_key:
                    logger.error("NGC_API_KEY not set for staging repository")
                    return False
                
                result = helm("repo", "add", "nvidia", self.config.helm_nvidia_repo,
                            "--username", "$oauthtoken", "--password", ngc_api_key)
            
            if not result.success:
                logger.error(f"Failed to add Helm repository: {result.stderr}")
                return False
            
            # Update repos
            result = helm("repo", "update")
            if not result.success:
                logger.error(f"Failed to update Helm repositories: {result.stderr}")
                return False
            
            # Download chart if not exists
            chart_file = f"network-operator-{self.config.netop_version}.tgz"
            if not os.path.exists(chart_file):
                logger.info(f"Downloading chart: {chart_file}")
                
                if self.config.prod_version:
                    result = helm("fetch", self.config.netop_helm_url)
                else:
                    result = helm("fetch", self.config.netop_helm_url,
                                "--username", "$oauthtoken", "--password", ngc_api_key)
                
                if not result.success:
                    logger.error(f"Failed to fetch chart: {result.stderr}")
                    return False
                
                # Extract chart
                result = run_command(["tar", "-xvf", f"network-operator-{self.config.netop_version}.tgz"])
                if not result.success:
                    logger.error(f"Failed to extract chart: {result.stderr}")
                    return False
            
            logger.info("Network Operator chart prepared successfully")
            return True
            
        finally:
            os.chdir(original_dir)
    
    def install_network_operator(self, values_file: Optional[str] = None) -> bool:
        """Install Network Operator - equivalent to install/ins-network-operator.sh"""
        logger.info("Installing NVIDIA Network Operator")
        
        # Create namespace
        result = kubectl("create", "namespace", self.config.netop_namespace)
        if not result.success and "AlreadyExists" not in result.stderr:
            logger.error(f"Failed to create namespace: {result.stderr}")
            return False
        
        # Create image pull secret if needed
        if not self.config.prod_version:
            if not self._create_image_pull_secret():
                logger.error("Failed to create image pull secret")
                return False
        
        # Generate values.yaml if not provided
        if values_file is None:
            values_file = "values.yaml"
            if not self._generate_values_file(values_file):
                logger.error("Failed to generate values.yaml")
                return False
        
        # Install using Helm
        helm_args = [
            "install", "network-operator", "nvidia/network-operator",
            "--namespace", self.config.netop_namespace,
            "--values", values_file,
            "--version", self.config.netop_version,
            "--wait", "--timeout", "600s"
        ]
        
        result = helm(*helm_args)
        
        if result.success:
            logger.info("Network Operator installed successfully")
            # Wait for pods to be ready
            return wait_for_pods_ready(self.config.netop_namespace, timeout=600)
        else:
            logger.error(f"Failed to install Network Operator: {result.stderr}")
            return False
    
    def _create_image_pull_secret(self) -> bool:
        """Create NGC image pull secret"""
        logger.info("Creating NGC image pull secret")
        
        ngc_api_key = os.environ.get('NGC_API_KEY', '')
        if not ngc_api_key:
            logger.error("NGC_API_KEY not set")
            return False
        
        # Create docker config
        docker_config = {
            "auths": {
                "nvcr.io": {
                    "username": "$oauthtoken",
                    "password": ngc_api_key,
                    "auth": ""  # Base64 encoded username:password
                }
            }
        }
        
        import base64
        auth_string = f"$oauthtoken:{ngc_api_key}"
        docker_config["auths"]["nvcr.io"]["auth"] = base64.b64encode(auth_string.encode()).decode()
        
        # Create secret
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump(docker_config, f)
            config_file = f.name
        
        try:
            result = kubectl("create", "secret", "generic", "ngc-image-secret",
                           f"--from-file=.dockerconfigjson={config_file}",
                           "--type=kubernetes.io/dockerconfigjson",
                           namespace=self.config.netop_namespace)
            
            if result.success or "AlreadyExists" in result.stderr:
                logger.info("Image pull secret created successfully")
                return True
            else:
                logger.error(f"Failed to create image pull secret: {result.stderr}")
                return False
        finally:
            os.unlink(config_file)
    
    def _generate_values_file(self, output_file: str) -> bool:
        """Generate values.yaml file"""
        logger.info(f"Generating values file: {output_file}")
        
        # Import ops module to use values generation
        from .ops_commands import NetworkOperatorOps
        
        ops = NetworkOperatorOps()
        values_yaml = ops.create_values_yaml()
        
        try:
            with open(output_file, 'w') as f:
                f.write(values_yaml)
            logger.info(f"Values file generated: {output_file}")
            return True
        except Exception as e:
            logger.error(f"Failed to write values file: {e}")
            return False
    
    def install_calico(self) -> bool:
        """Install Calico CNI - equivalent to install/ins-calico.sh"""
        logger.info(f"Installing Calico {self.config.calico_version}")
        
        # Download Calico manifest
        calico_url = f"https://raw.githubusercontent.com/projectcalico/calico/{self.config.calico_version}/manifests/tigera-operator.yaml"
        
        result = run_command(["curl", "-O", calico_url], capture_output=True)
        if not result.success:
            logger.error(f"Failed to download Calico manifest: {result.stderr}")
            return False
        
        # Apply Calico operator
        result = kubectl("apply", "-f", "tigera-operator.yaml")
        if not result.success:
            logger.error(f"Failed to apply Calico operator: {result.stderr}")
            return False
        
        # Create Calico installation CR
        calico_installation = f"""
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: {self.config.k8_cidr}
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
"""
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(calico_installation)
            installation_file = f.name
        
        try:
            result = kubectl("apply", "-f", installation_file)
            if result.success:
                logger.info("Calico installed successfully")
                return wait_for_pods_ready("calico-system", timeout=300)
            else:
                logger.error(f"Failed to install Calico: {result.stderr}")
                return False
        finally:
            os.unlink(installation_file)
    
    def apply_crds(self) -> bool:
        """Apply CRDs - equivalent to install/applycrds.sh"""
        logger.info("Applying Network Operator CRDs")
        
        # Get CRDs from the chart
        chart_dir = Path(self.config.netop_root_dir) / "release" / self.config.netop_version / "netop-chart"
        crds_dir = chart_dir / "network-operator" / "crds"
        
        if not crds_dir.exists():
            logger.error(f"CRDs directory not found: {crds_dir}")
            return False
        
        # Apply all CRD files
        success = True
        for crd_file in crds_dir.glob("*.yaml"):
            logger.info(f"Applying CRD: {crd_file.name}")
            result = kubectl("apply", "-f", str(crd_file))
            if not result.success:
                logger.error(f"Failed to apply CRD {crd_file.name}: {result.stderr}")
                success = False
        
        return success
    
    def wait_k8s_ready(self) -> bool:
        """Wait for Kubernetes to be ready - equivalent to install/wait-k8sready.sh"""
        logger.info("Waiting for Kubernetes to be ready...")
        return wait_for_nodes_ready(timeout=300)
    
    def wait_calico_ready(self) -> bool:
        """Wait for Calico to be ready - equivalent to install/wait-calicoready.sh"""
        logger.info("Waiting for Calico to be ready...")
        return wait_for_pods_ready("calico-system", timeout=300)

def create_install_parser(subparsers):
    """Create install command parser"""
    install_parser = subparsers.add_parser(
        "install",
        help="Installation commands"
    )
    
    install_subparsers = install_parser.add_subparsers(
        dest="install_action",
        help="Installation commands"
    )
    
    # Helm installation
    install_subparsers.add_parser("helm", help="Install Helm")
    
    # Network Operator installation
    netop_parser = install_subparsers.add_parser("network-operator", help="Install Network Operator")
    netop_parser.add_argument("--values", help="Values file for Helm installation")
    
    # Chart preparation
    install_subparsers.add_parser("chart", help="Prepare Network Operator chart")
    
    # Calico installation
    install_subparsers.add_parser("calico", help="Install Calico CNI")
    
    # CRDs
    install_subparsers.add_parser("crds", help="Apply Network Operator CRDs")
    
    # Wait commands
    wait_parser = install_subparsers.add_parser("wait", help="Wait for components")
    wait_subparsers = wait_parser.add_subparsers(dest="wait_action")
    wait_subparsers.add_parser("k8s", help="Wait for Kubernetes to be ready")
    wait_subparsers.add_parser("calico", help="Wait for Calico to be ready")
    
    return install_parser

def handle_install_command(args):
    """Handle install commands"""
    installer = NetworkOperatorInstaller()
    
    if args.install_action == "helm":
        success = installer.install_helm()
        return 0 if success else 1
    
    elif args.install_action == "network-operator":
        success = installer.install_network_operator(args.values)
        return 0 if success else 1
    
    elif args.install_action == "chart":
        success = installer.install_network_operator_chart()
        return 0 if success else 1
    
    elif args.install_action == "calico":
        success = installer.install_calico()
        return 0 if success else 1
    
    elif args.install_action == "crds":
        success = installer.apply_crds()
        return 0 if success else 1
    
    elif args.install_action == "wait":
        if args.wait_action == "k8s":
            success = installer.wait_k8s_ready()
            return 0 if success else 1
        elif args.wait_action == "calico":
            success = installer.wait_calico_ready()
            return 0 if success else 1
    
    print(f"Unknown install action: {args.install_action}")
    return 1 