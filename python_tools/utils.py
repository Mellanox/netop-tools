#!/usr/bin/env python3
"""
NVIDIA Network Operator Tools - Utility Functions
Common utilities for script operations
"""
import os
import sys
import subprocess
import logging
import json
import time
import shutil
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any, Union
from dataclasses import dataclass
import socket
import ipaddress

try:
    from .config import NetOpConfig, get_config
except ImportError:
    from config import NetOpConfig, get_config

logger = logging.getLogger(__name__)

@dataclass
class CommandResult:
    """Result of a command execution"""
    returncode: int
    stdout: str
    stderr: str
    success: bool

def run_command(
    cmd: Union[str, List[str]], 
    cwd: Optional[str] = None,
    env: Optional[Dict[str, str]] = None,
    capture_output: bool = True,
    timeout: Optional[int] = None,
    dry_run: bool = False
) -> CommandResult:
    """
    Execute a command and return the result
    
    Args:
        cmd: Command to execute (string or list)
        cwd: Working directory
        env: Environment variables
        capture_output: Whether to capture stdout/stderr
        timeout: Command timeout in seconds
        dry_run: If True, only print the command without executing
        
    Returns:
        CommandResult with execution details
    """
    config = get_config()
    
    # Convert string command to list
    if isinstance(cmd, str):
        cmd_list = cmd.split()
    else:
        cmd_list = cmd
    
    # Apply dry run mode based on config
    if config.create_config_only or dry_run:
        logger.info(f"DRY RUN: {' '.join(cmd_list)}")
        return CommandResult(0, "", "", True)
    
    logger.debug(f"Executing: {' '.join(cmd_list)}")
    
    try:
        result = subprocess.run(
            cmd_list,
            cwd=cwd,
            env=env,
            capture_output=capture_output,
            text=True,
            timeout=timeout
        )
        
        success = result.returncode == 0
        if not success:
            logger.error(f"Command failed: {' '.join(cmd_list)}")
            logger.error(f"Exit code: {result.returncode}")
            if result.stderr:
                logger.error(f"Stderr: {result.stderr}")
        
        return CommandResult(
            returncode=result.returncode,
            stdout=result.stdout,
            stderr=result.stderr,
            success=success
        )
        
    except subprocess.TimeoutExpired:
        logger.error(f"Command timed out: {' '.join(cmd_list)}")
        return CommandResult(-1, "", "Command timed out", False)
    except subprocess.CalledProcessError as e:
        logger.error(f"Command failed: {' '.join(cmd_list)}")
        return CommandResult(e.returncode, e.stdout or "", e.stderr or "", False)
    except Exception as e:
        logger.error(f"Unexpected error executing command: {e}")
        return CommandResult(-1, "", str(e), False)

def kubectl(*args, namespace: Optional[str] = None, output: str = "", dry_run: bool = False) -> CommandResult:
    """
    Execute kubectl command with common options
    
    Args:
        *args: kubectl arguments
        namespace: Kubernetes namespace
        output: Output format (json, yaml, etc.)
        dry_run: Dry run mode
        
    Returns:
        CommandResult
    """
    config = get_config()
    cmd = [config.k8_client]
    
    if namespace:
        cmd.extend(["-n", namespace])
    
    cmd.extend(args)
    
    if output:
        cmd.extend(["-o", output])
    
    return run_command(cmd, dry_run=dry_run)

def helm(*args, dry_run: bool = False) -> CommandResult:
    """
    Execute helm command
    
    Args:
        *args: helm arguments
        dry_run: Dry run mode
        
    Returns:
        CommandResult
    """
    cmd = ["helm"] + list(args)
    return run_command(cmd, dry_run=dry_run)

def docker(*args, dry_run: bool = False) -> CommandResult:
    """
    Execute docker command
    
    Args:
        *args: docker arguments
        dry_run: Dry run mode
        
    Returns:
        CommandResult
    """
    cmd = ["docker"] + list(args)
    return run_command(cmd, dry_run=dry_run)

def get_nodes(node_type: str = "") -> List[str]:
    """
    Get list of Kubernetes nodes
    
    Args:
        node_type: Filter by node type (master, worker, etc.)
        
    Returns:
        List of node names
    """
    result = kubectl("get", "nodes", "--no-headers")
    if not result.success:
        return []
    
    nodes = []
    for line in result.stdout.strip().split('\n'):
        if line:
            parts = line.split()
            if parts:
                node_name = parts[0]
                if not node_type or node_type in line:
                    nodes.append(node_name)
    
    return nodes

def cordon_nodes(node_type: str = "worker") -> bool:
    """
    Cordon worker nodes
    
    Args:
        node_type: Type of nodes to cordon
        
    Returns:
        True if successful
    """
    result = kubectl("get", "nodes")
    if not result.success:
        return False
    
    # Find nodes that are not already cordoned
    nodes_to_cordon = []
    for line in result.stdout.strip().split('\n'):
        if node_type in line and "SchedulingDisabled" not in line:
            parts = line.split()
            if parts:
                nodes_to_cordon.append(parts[0])
    
    success = True
    for node in nodes_to_cordon:
        logger.info(f"Cordoning node: {node}")
        result = kubectl("cordon", node)
        if not result.success:
            success = False
    
    return success

def uncordon_nodes(node_type: str = "worker") -> bool:
    """
    Uncordon worker nodes
    
    Args:
        node_type: Type of nodes to uncordon
        
    Returns:
        True if successful
    """
    result = kubectl("get", "nodes")
    if not result.success:
        return False
    
    # Find nodes that are cordoned
    nodes_to_uncordon = []
    for line in result.stdout.strip().split('\n'):
        if node_type in line and "SchedulingDisabled" in line:
            parts = line.split()
            if parts:
                nodes_to_uncordon.append(parts[0])
    
    success = True
    for node in nodes_to_uncordon:
        logger.info(f"Uncordoning node: {node}")
        result = kubectl("uncordon", node)
        if not result.success:
            success = False
    
    return success



def create_symlink(target: str, link_name: str, force: bool = True) -> bool:
    """
    Create a symbolic link
    
    Args:
        target: Target path
        link_name: Link name
        force: Remove existing link if it exists
        
    Returns:
        True if successful
    """
    try:
        if force and os.path.exists(link_name):
            os.remove(link_name)
        
        os.symlink(target, link_name)
        logger.info(f"Created symlink: {link_name} -> {target}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to create symlink {link_name} -> {target}: {e}")
        return False

def wait_for_pods_ready(namespace: str, timeout: int = 300) -> bool:
    """
    Wait for all pods in namespace to be ready
    
    Args:
        namespace: Kubernetes namespace
        timeout: Timeout in seconds
        
    Returns:
        True if all pods are ready
    """
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        result = kubectl("get", "pods", namespace=namespace, output="json")
        
        if result.success:
            try:
                data = json.loads(result.stdout)
                pods = data.get('items', [])
                
                if not pods:
                    logger.info(f"No pods found in namespace {namespace}")
                    return True
                
                all_ready = True
                for pod in pods:
                    pod_name = pod['metadata']['name']
                    status = pod.get('status', {})
                    
                    if status.get('phase') != 'Running':
                        all_ready = False
                        continue
                    
                    conditions = status.get('conditions', [])
                    ready_condition = next((c for c in conditions if c['type'] == 'Ready'), None)
                    
                    if not ready_condition or ready_condition['status'] != 'True':
                        all_ready = False
                        continue
                
                if all_ready:
                    logger.info(f"All pods in namespace {namespace} are ready")
                    return True
                
            except json.JSONDecodeError:
                logger.error("Failed to parse kubectl output")
        
        logger.info(f"Waiting for pods in {namespace} to be ready...")
        time.sleep(10)
    
    logger.error(f"Timeout waiting for pods in {namespace} to be ready")
    return False

def wait_for_nodes_ready(timeout: int = 300) -> bool:
    """
    Wait for all nodes to report Ready

    Args:
        timeout: Timeout in seconds

    Returns:
        True if all nodes are ready within the timeout
    """
    start_time = time.time()

    while time.time() - start_time < timeout:
        result = kubectl("get", "nodes", output="json")
        if result.success:
            try:
                data = json.loads(result.stdout)
                nodes = data.get('items', [])

                if not nodes:
                    logger.info("No nodes found yet, waiting...")
                    time.sleep(10)
                    continue

                all_ready = True
                for node in nodes:
                    conditions = node.get('status', {}).get('conditions', [])
                    ready_condition = next((c for c in conditions if c['type'] == 'Ready'), None)
                    if not ready_condition or ready_condition['status'] != 'True':
                        all_ready = False
                        break

                if all_ready:
                    logger.info("All nodes are ready")
                    return True

            except json.JSONDecodeError:
                logger.error("Failed to parse kubectl nodes output")

        logger.info("Waiting for nodes to be ready...")
        time.sleep(10)

    logger.error("Timeout waiting for nodes to be ready")
    return False


def get_pod_logs(pod_name: str, namespace: str, container: str = "") -> str:
    """
    Get logs from a pod
    
    Args:
        pod_name: Pod name
        namespace: Kubernetes namespace
        container: Container name (optional)
        
    Returns:
        Pod logs as string
    """
    args = ["logs", pod_name]
    if container:
        args.extend(["-c", container])
    
    result = kubectl(*args, namespace=namespace)
    return result.stdout if result.success else ""

def validate_ip_range(ip_range: str) -> bool:
    """
    Validate IP range in CIDR format
    
    Args:
        ip_range: IP range in CIDR format
        
    Returns:
        True if valid
    """
    try:
        ipaddress.ip_network(ip_range, strict=False)
        return True
    except ValueError:
        return False

def check_port_availability(port: int, host: str = "localhost") -> bool:
    """
    Check if a port is available
    
    Args:
        port: Port number
        host: Host to check
        
    Returns:
        True if port is available
    """
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(1)
            result = sock.connect_ex((host, port))
            return result != 0  # Port is available if connection fails
    except Exception:
        return False

def ensure_directory(path: str, mode: int = 0o755) -> bool:
    """
    Ensure directory exists with proper permissions
    
    Args:
        path: Directory path
        mode: Directory permissions
        
    Returns:
        True if successful
    """
    try:
        os.makedirs(path, mode=mode, exist_ok=True)
        return True
    except Exception as e:
        logger.error(f"Failed to create directory {path}: {e}")
        return False

def file_exists(path: str) -> bool:
    """Check if file exists"""
    return os.path.isfile(path)

def copy_file(src: str, dst: str, preserve_permissions: bool = True) -> bool:
    """
    Copy file with optional permission preservation
    
    Args:
        src: Source file
        dst: Destination file
        preserve_permissions: Whether to preserve file permissions
        
    Returns:
        True if successful
    """
    try:
        if preserve_permissions:
            shutil.copy2(src, dst)
        else:
            shutil.copy(src, dst)
        return True
    except Exception as e:
        logger.error(f"Failed to copy {src} to {dst}: {e}")
        return False

def setup_logging(level: str = "INFO", log_file: Optional[str] = None) -> None:
    """
    Setup logging configuration
    
    Args:
        level: Log level
        log_file: Optional log file path
    """
    log_format = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    
    handlers = [logging.StreamHandler(sys.stdout)]
    if log_file:
        handlers.append(logging.FileHandler(log_file))
    
    logging.basicConfig(
        level=getattr(logging, level.upper()),
        format=log_format,
        handlers=handlers
    )

def get_environment_info() -> Dict[str, str]:
    """Get environment information for debugging"""
    config = get_config()
    
    return {
        "netop_root_dir": config.netop_root_dir,
        "k8s_version": config.k8s_version,
        "netop_version": config.netop_version,
        "usecase": config.usecase,
        "host_os": config.host_os,
        "python_version": sys.version,
        "current_dir": os.getcwd(),
    } 