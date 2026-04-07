#!/usr/bin/env python3
"""
NVIDIA Network Operator Tools - Kubernetes Management
Python conversion of Kubernetes-related bash scripts
"""
import os
import sys
import argparse
import json
import logging
from pathlib import Path
from typing import List, Dict, Optional, Tuple

try:
    from .config import get_config, validate_environment
    from .utils import (
        run_command, kubectl, setup_logging, create_symlink,
        wait_for_pods_ready, cordon_nodes, uncordon_nodes
    )
except ImportError:
    from config import get_config, validate_environment
    from utils import (
        run_command, kubectl, setup_logging, create_symlink,
        wait_for_pods_ready, cordon_nodes, uncordon_nodes
    )

logger = logging.getLogger(__name__)

def setup_usecase(usecase: Optional[str] = None) -> bool:
    """
    Setup use case configuration
    Python conversion of setuc.sh
    
    Args:
        usecase: Use case name (default: from config)
        
    Returns:
        True if successful
    """
    config = get_config()
    
    if not validate_environment():
        return False
    
    if usecase is None:
        usecase = config.usecase
    
    logger.info(f"Setting up use case: {usecase}")
    
    # Remove existing symlink
    uc_link = Path(config.netop_root_dir) / "uc"
    if uc_link.exists():
        uc_link.unlink()
        logger.debug("Removed existing uc symlink")
    
    # Create new symlink to use case directory
    usecase_path = Path(config.netop_root_dir) / "usecase" / usecase
    
    if not usecase_path.exists():
        logger.error(f"Use case directory not found: {usecase_path}")
        return False
    
    success = create_symlink(str(usecase_path), str(uc_link))
    
    if success:
        logger.info(f"Successfully linked use case: {usecase}")
    
    return success

def install_k8s_master(stage: str = "all") -> bool:
    """
    Install Kubernetes master
    Python conversion of ins-k8.sh
    
    Args:
        stage: Installation stage (master, init, calico, netop, all)
        
    Returns:
        True if successful
    """
    config = get_config()
    
    if not validate_environment():
        return False
    
    logger.info(f"Installing Kubernetes master - stage: {stage}")
    
    # Setup use case first
    if not setup_usecase():
        logger.error("Failed to setup use case")
        return False
    
    success = True
    
    if stage in ["master", "all"]:
        logger.info("Installing Kubernetes master...")
        script_path = Path(config.netop_root_dir) / "install" / "ins-k8master.sh"
        if script_path.exists():
            result = run_command([str(script_path), "master"])
            if not result.success:
                logger.error("Failed to install Kubernetes master")
                success = False
        else:
            logger.error(f"Script not found: {script_path}")
            success = False
    
    if stage in ["init", "all"] and success:
        logger.info("Initializing Kubernetes...")
        script_path = Path(config.netop_root_dir) / "install" / "ins-k8master.sh"
        if script_path.exists():
            result = run_command([str(script_path), "init"])
            if not result.success:
                logger.error("Failed to initialize Kubernetes")
                success = False
        else:
            logger.error(f"Script not found: {script_path}")
            success = False
    
    if stage in ["calico", "all"] and success:
        logger.info("Installing Calico...")
        script_path = Path(config.netop_root_dir) / "install" / "ins-k8master.sh"
        if script_path.exists():
            result = run_command([str(script_path), "calico"])
            if not result.success:
                logger.error("Failed to install Calico")
                success = False
        else:
            logger.error(f"Script not found: {script_path}")
            success = False
    
    if stage in ["netop", "all"] and success:
        logger.info("Installing Network Operator...")
        script_path = Path(config.netop_root_dir) / "install" / "ins-k8master.sh"
        if script_path.exists():
            result = run_command([str(script_path), "netop"])
            if not result.success:
                logger.error("Failed to install Network Operator")
                success = False
        else:
            logger.error(f"Script not found: {script_path}")
            success = False
    
    # Show nodes status
    if success:
        logger.info("Checking nodes status...")
        result = kubectl("get", "nodes")
        if result.success:
            print(result.stdout)
        else:
            logger.warning("Failed to get nodes status")
    
    return success

def restart_k8s_master() -> bool:
    """
    Restart Kubernetes master
    Python conversion of startk8master.sh
    
    Returns:
        True if successful
    """
    config = get_config()
    
    if not validate_environment():
        return False
    
    logger.info("Restarting Kubernetes master...")
    
    # Run restart script
    restart_script = Path(config.netop_root_dir) / "restart" / "restartk8master.sh"
    if restart_script.exists():
        result = run_command([str(restart_script)])
        if not result.success:
            logger.error("Failed to run restart script")
            return False
    else:
        logger.warning(f"Restart script not found: {restart_script}")
    
    # Restart services
    services = ["docker", "containerd"]
    for service in services:
        logger.info(f"Restarting {service} service...")
        result = run_command(["systemctl", "restart", service])
        if not result.success:
            logger.warning(f"Failed to restart {service} service")
    
    # Reinitialize Kubernetes components
    install_stages = ["init", "calico", "netop"]
    for stage in install_stages:
        logger.info(f"Running install stage: {stage}")
        if not install_k8s_master(stage):
            logger.error(f"Failed to run install stage: {stage}")
            return False
    
    # Show final status
    logger.info("Checking final nodes status...")
    result = kubectl("get", "nodes")
    if result.success:
        print(result.stdout)
    
    return True

def run_development_environment() -> bool:
    """
    Setup development environment
    Python conversion of rundev.sh
    
    Returns:
        True if successful
    """
    config = get_config()
    
    if not validate_environment():
        return False
    
    logger.info("Setting up development environment...")
    
    dev_policy_file = "nic-cluster-policy.yaml"
    dev_policy_path = Path(dev_policy_file)
    
    # Get current policy if not defined
    if not dev_policy_path.exists():
        logger.info("Getting current NicClusterPolicy...")
        result = kubectl("get", "NicClusterPolicy", "nic-cluster-policy", output="yaml")
        
        if result.success:
            try:
                with open(dev_policy_file, 'w') as f:
                    f.write(result.stdout)
            except OSError as e:
                logger.error(f"Failed to write policy file {dev_policy_file}: {e}")
                return False
            logger.info(f"Saved policy to {dev_policy_file}")
        else:
            logger.error("Failed to get NicClusterPolicy")
            return False
        
        # Uninstall network operator
        uninstall_script = Path(config.netop_root_dir) / "uninstall-network-operator.sh"
        if uninstall_script.exists():
            result = run_command([str(uninstall_script)])
            if not result.success:
                logger.warning("Failed to uninstall network operator")
        else:
            logger.warning(f"Uninstall script not found: {uninstall_script}")
    
    # Process policy file (equivalent to edityaml.py processing)
    dev_policy_output = f"{dev_policy_file}.dev"
    edit_script = Path(config.netop_root_dir) / "edityaml.py"
    
    if edit_script.exists():
        result = run_command(["python3", str(edit_script), dev_policy_file])
        if result.success:
            try:
                with open(dev_policy_output, 'w') as f:
                    f.write(result.stdout)
            except OSError as e:
                logger.error(f"Failed to write processed policy to {dev_policy_output}: {e}")
                return False
            logger.info(f"Processed policy saved to {dev_policy_output}")
        else:
            logger.error("Failed to process policy file")
            return False
    else:
        logger.warning(f"Edit script not found: {edit_script}")
        try:
            with open(dev_policy_file, 'r') as src, open(dev_policy_output, 'w') as dst:
                dst.write(src.read())
        except OSError as e:
            logger.error(f"Failed to copy {dev_policy_file} to {dev_policy_output}: {e}")
            return False
    
    # Create namespace
    logger.info(f"Creating namespace: {config.netop_namespace}")
    result = kubectl("create", "ns", config.netop_namespace)
    if not result.success and "AlreadyExists" not in result.stderr:
        logger.error(f"Failed to create namespace: {config.netop_namespace}")
        return False
    
    # Run make (if Makefile exists)
    makefile = Path(config.netop_root_dir) / "Makefile"
    if makefile.exists():
        logger.info("Running make...")
        result = run_command(["make", "run"], cwd=config.netop_root_dir)
        if not result.success:
            logger.warning("Make run failed")
    
    # Apply policy
    logger.info(f"Applying policy: {dev_policy_output}")
    result = kubectl("apply", "-f", dev_policy_output)
    if not result.success:
        logger.error("Failed to apply policy")
        return False
    
    logger.info("Development environment setup completed")
    return True

def get_cluster_status() -> Dict[str, any]:
    """
    Get comprehensive cluster status
    
    Returns:
        Dictionary containing cluster status information
    """
    config = get_config()
    status = {
        "nodes": [],
        "namespaces": [],
        "network_operator_pods": [],
        "cluster_info": {}
    }
    
    # Get nodes
    result = kubectl("get", "nodes", output="json")
    if result.success:
        try:
            data = json.loads(result.stdout)
            status["nodes"] = [item["metadata"]["name"] for item in data.get("items", [])]
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse nodes output: {e}")

    # Get namespaces
    result = kubectl("get", "namespaces", output="json")
    if result.success:
        try:
            data = json.loads(result.stdout)
            status["namespaces"] = [item["metadata"]["name"] for item in data.get("items", [])]
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse namespaces output: {e}")

    # Get network operator pods
    result = kubectl("get", "pods", namespace=config.netop_namespace, output="json")
    if result.success:
        try:
            data = json.loads(result.stdout)
            for item in data.get("items", []):
                pod_info = {
                    "name": item["metadata"]["name"],
                    "phase": item["status"].get("phase", "Unknown"),
                    "ready": "False"
                }

                conditions = item["status"].get("conditions", [])
                for condition in conditions:
                    if condition["type"] == "Ready":
                        pod_info["ready"] = condition["status"]
                        break

                status["network_operator_pods"].append(pod_info)
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse pods output: {e}")

    # Get cluster info
    result = kubectl("cluster-info")
    if result.success:
        status["cluster_info"]["raw"] = result.stdout
    
    return status

def main_ins_k8():
    """Main function for Kubernetes installation (ins-k8.sh equivalent)"""
    parser = argparse.ArgumentParser(
        description="Install Kubernetes master components",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s
    # Install all Kubernetes components
    
  %(prog)s --stage init
    # Install only initialization stage
        """
    )
    
    parser.add_argument(
        "--stage",
        choices=["master", "init", "calico", "netop", "all"],
        default="all",
        help="Installation stage (default: all)"
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
        success = install_k8s_master(args.stage)
        
        if success:
            logger.info("Kubernetes installation completed successfully")
            return 0
        else:
            logger.error("Kubernetes installation failed")
            return 1
            
    except Exception as e:
        logger.error(f"Error: {e}")
        return 1

def main_setuc():
    """Main function for use case setup (setuc.sh equivalent)"""
    parser = argparse.ArgumentParser(
        description="Setup Network Operator use case",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s
    # Setup default use case from configuration
    
  %(prog)s --usecase sriovnet_rdma
    # Setup specific use case
        """
    )
    
    parser.add_argument(
        "--usecase",
        help="Use case name (default: from configuration)"
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
        success = setup_usecase(args.usecase)
        
        if success:
            logger.info("Use case setup completed successfully")
            return 0
        else:
            logger.error("Use case setup failed")
            return 1
            
    except Exception as e:
        logger.error(f"Error: {e}")
        return 1

def main_start_k8():
    """Main function for Kubernetes restart (startk8master.sh equivalent)"""
    parser = argparse.ArgumentParser(
        description="Restart Kubernetes master",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s
    # Restart Kubernetes master and all components
        """
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
        success = restart_k8s_master()
        
        if success:
            logger.info("Kubernetes restart completed successfully")
            return 0
        else:
            logger.error("Kubernetes restart failed")
            return 1
            
    except Exception as e:
        logger.error(f"Error: {e}")
        return 1

def main_rundev():
    """Main function for development environment (rundev.sh equivalent)"""
    parser = argparse.ArgumentParser(
        description="Setup development environment",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s
    # Setup complete development environment
        """
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
        success = run_development_environment()
        
        if success:
            logger.info("Development environment setup completed successfully")
            return 0
        else:
            logger.error("Development environment setup failed")
            return 1
            
    except Exception as e:
        logger.error(f"Error: {e}")
        return 1

if __name__ == "__main__":
    # Determine which function to run based on script name
    script_name = Path(sys.argv[0]).stem
    
    if "ins-k8" in script_name or "ins_k8" in script_name:
        sys.exit(main_ins_k8())
    elif "setuc" in script_name:
        sys.exit(main_setuc())
    elif "startk8" in script_name or "start_k8" in script_name:
        sys.exit(main_start_k8())
    elif "rundev" in script_name:
        sys.exit(main_rundev())
    else:
        print("Usage: Run as ins_k8.py, setuc.py, start_k8.py, or rundev.py", file=sys.stderr)
        sys.exit(1) 