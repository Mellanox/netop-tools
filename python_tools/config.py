#!/usr/bin/env python3
"""
NVIDIA Network Operator Tools - Configuration Management
Replaces bash configuration files like global_ops.cfg
"""
import os
import json
import logging
from pathlib import Path
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field
from configparser import ConfigParser

logger = logging.getLogger(__name__)

@dataclass
class NetOpConfig:
    """Main configuration class for Network Operator tools"""
    
    # Core paths and versions
    netop_root_dir: str = ""
    k8s_version: str = "1.29"
    k8_client: str = "kubectl"
    host_os: str = "ubuntu"
    
    # Network configuration
    k8_cidr: str = "192.168.0.0/16"
    netop_namespace: str = "nvidia-network-operator"
    netop_app_namespaces: List[str] = field(default_factory=lambda: ["default"])
    netop_network_range: str = "192.170.0.0/16"
    netop_network_gw: str = ""
    netop_pernode_blocksize: int = 32
    
    # Network Operator configuration
    netop_version: str = "25.4.0"
    helm_nvidia_repo: str = "https://helm.ngc.nvidia.com/nvidia"
    prod_version: bool = True
    
    # Calico configuration
    calico_root: str = "3.28.2"
    cniplugins_version: str = "v1.5.1"
    
    # Use case configuration
    usecase: str = "sriovnet_rdma"
    num_vfs: int = 8
    device_types: List[str] = field(default_factory=lambda: ["connectx-6"])
    
    # IPAM configuration
    ipam_type: str = "nv-ipam"
    nvipam_pool_type: str = "IPPool"
    
    # Feature flags
    ofed_enable: bool = True
    ofed_blacklist_enable: bool = False
    nfd_enable: bool = True
    create_config_only: bool = True
    nic_config_enable: bool = True
    enable_nfsrdma: bool = False
    
    # Network settings
    netop_mtu: int = 1500
    rdma_shared_mode: bool = True
    sbr_mode: bool = False
    
    # Hardware configuration
    netop_vendor: str = "15b3"
    netop_sulist: List[str] = field(default_factory=lambda: ["su-1"])
    worker_node: str = "worker"
    
    # Additional system configuration
    sysctl_config: str = ""
    
    @classmethod
    def from_env(cls) -> 'NetOpConfig':
        """Create configuration from environment variables"""
        config = cls()
        
        # Set NETOP_ROOT_DIR from environment or auto-detect
        if 'NETOP_ROOT_DIR' in os.environ:
            config.netop_root_dir = os.environ['NETOP_ROOT_DIR']
        else:
            # Auto-detect the netop-tools root directory
            current_dir = Path.cwd()
            
            # If we're in python_tools subdirectory, go up one level
            if current_dir.name == 'python_tools':
                config.netop_root_dir = str(current_dir.parent)
            # If we're running from a script in python_tools, get the parent
            elif (current_dir / 'python_tools').exists():
                config.netop_root_dir = str(current_dir)
            else:
                # Look for netop-tools indicators (allsh file, install directory, etc.)
                search_dir = current_dir
                while search_dir != search_dir.parent:
                    if (search_dir / 'allsh').exists() or (search_dir / 'install').exists():
                        config.netop_root_dir = str(search_dir)
                        break
                    search_dir = search_dir.parent
                else:
                    # Fallback to current directory
                    config.netop_root_dir = str(current_dir)
        
        # First load from global_ops.cfg if it exists
        config._load_global_config()
        
        # Load environment variables with defaults (these override global config)
        config.k8s_version = os.environ.get('K8SVER', config.k8s_version)
        config.k8_client = os.environ.get('K8CL', config.k8_client)
        config.host_os = os.environ.get('HOST_OS', config.host_os)
        config.netop_namespace = os.environ.get('NETOP_NAMESPACE', config.netop_namespace)
        config.netop_network_range = os.environ.get('NETOP_NETWORK_RANGE', config.netop_network_range)
        config.netop_network_gw = os.environ.get('NETOP_NETWORK_GW', config.netop_network_gw)
        try:
            config.netop_pernode_blocksize = int(os.environ.get('NETOP_PERNODE_BLOCKSIZE', str(config.netop_pernode_blocksize)))
        except ValueError:
            logger.warning(f"Invalid NETOP_PERNODE_BLOCKSIZE value: {os.environ.get('NETOP_PERNODE_BLOCKSIZE')}")
        config.netop_version = os.environ.get('NETOP_VERSION', config.netop_version)
        config.usecase = os.environ.get('USECASE', config.usecase)
        try:
            config.num_vfs = int(os.environ.get('NUM_VFS', str(config.num_vfs)))
        except ValueError:
            logger.warning(f"Invalid NUM_VFS value: {os.environ.get('NUM_VFS')}")
        config.ipam_type = os.environ.get('IPAM_TYPE', config.ipam_type)
        config.nvipam_pool_type = os.environ.get('NVIPAM_POOL_TYPE', config.nvipam_pool_type)
        try:
            config.netop_mtu = int(os.environ.get('NETOP_MTU', str(config.netop_mtu)))
        except ValueError:
            logger.warning(f"Invalid NETOP_MTU value: {os.environ.get('NETOP_MTU')}")
        config.worker_node = os.environ.get('WORKERNODE', config.worker_node)
        config.sysctl_config = os.environ.get('SYSCTL_CONFIG', config.sysctl_config)
        
        # Boolean flags
        config.ofed_enable = os.environ.get('OFED_ENABLE', 'true').lower() == 'true'
        config.ofed_blacklist_enable = os.environ.get('OFED_BLACKLIST_ENABLE', 'false').lower() == 'true'
        config.nfd_enable = os.environ.get('NFD_ENABLE', 'true').lower() == 'true'
        config.create_config_only = os.environ.get('CREATE_CONFIG_ONLY', '1') == '1'
        config.nic_config_enable = os.environ.get('NIC_CONFIG_ENABLE', 'true').lower() == 'true'
        config.enable_nfsrdma = os.environ.get('ENABLE_NFSRDMA', 'false').lower() == 'true'
        config.rdma_shared_mode = os.environ.get('RDMASHAREDMODE', 'true').lower() == 'true'
        config.sbr_mode = os.environ.get('SBRMODE', 'false').lower() == 'true'
        config.prod_version = os.environ.get('PROD_VER', '1') == '1'
        
        # Finally load user configuration if available (this overrides everything)
        user_config_path = os.environ.get('GLOBAL_OPS_USER', 
                                          os.path.join(config.netop_root_dir, 'global_ops_user.cfg'))
        config._load_user_config(user_config_path)
        
        return config
    
    def _load_global_config(self) -> None:
        """Load global configuration from global_ops.cfg"""
        global_config_path = os.path.join(self.netop_root_dir, 'global_ops.cfg')
        if os.path.exists(global_config_path):
            logger.info(f"Loading global configuration from: {global_config_path}")
            self._parse_shell_config(global_config_path)
        else:
            logger.debug(f"Global configuration file not found: {global_config_path}")
    
    def _load_user_config(self, config_path: str) -> None:
        """Load user-specific configuration from file and override existing values"""
        if os.path.exists(config_path):
            logger.info(f"Loading user configuration from: {config_path}")
            self._parse_shell_config(config_path)
        else:
            logger.warning(f"User configuration file not found: {config_path}")
    
    def _parse_shell_config(self, config_path: str) -> None:
        """Parse shell-style config file and update configuration values"""
        config_values = {}
        
        with open(config_path, 'r') as f:
            for line_num, line in enumerate(f, 1):
                original_line = line
                line = line.strip()
                
                if line and not line.startswith('#') and '=' in line:
                    # Skip complex bash constructs - be more specific to avoid false positives
                    bash_constructs = ['if [', 'then', 'else', 'fi', 'do', 'done', 'case', 'esac']
                    bash_commands = ['$(', '`', 'cat ', 'grep ', 'cut ']
                    
                    should_skip = False
                    
                    # Check for bash control structures at the beginning of the line
                    for construct in bash_constructs:
                        if line.startswith(construct):
                            should_skip = True
                            break
                    
                    # Check for command substitution anywhere in the line
                    if not should_skip:
                        for cmd in bash_commands:
                            if cmd in line:
                                should_skip = True
                                break
                    
                    if should_skip:
                        continue
                    
                    # Handle export statements
                    if line.startswith('export '):
                        line = line[7:]  # Remove 'export '
                    
                    # Split only on the first equals sign to handle embedded = in values
                    if '=' in line:
                        equals_pos = line.find('=')
                        key = line[:equals_pos].strip()
                        value = line[equals_pos + 1:].strip()
                        
                        # Handle bash variable expansion syntax
                        value = self._expand_bash_variables(value)
                        
                        # Remove inline comments (but be careful with quotes)
                        value = self._remove_inline_comments(value)
                        
                        # Remove quotes
                        if value.startswith('"') and value.endswith('"'):
                            value = value[1:-1]
                        elif value.startswith("'") and value.endswith("'"):
                            value = value[1:-1]
                        
                        # Clean up any remaining escaped quotes
                        value = value.replace('\\"', '"').replace("\\'", "'")
                        
                        config_values[key] = value
        
        # Map shell variables to config attributes and update them
        self._update_from_shell_vars(config_values)
    
    def _expand_bash_variables(self, value: str) -> str:
        """Expand bash variable syntax like ${VAR:-"default"}"""
        import re
        
        # Handle ${VARIABLE:-"default"} syntax
        def replace_default(match):
            var_name = match.group(1)
            default_value = match.group(2)
            
            # Remove quotes from default value
            if default_value.startswith('"') and default_value.endswith('"'):
                default_value = default_value[1:-1]
            elif default_value.startswith("'") and default_value.endswith("'"):
                default_value = default_value[1:-1]
            
            # Check if variable exists in environment
            return os.environ.get(var_name, default_value)
        
        # Pattern for ${VAR:-"default"} or ${VAR:-default}
        value = re.sub(r'\$\{([^}]+):-([^}]+)\}', replace_default, value)
        
        # Handle simple ${VARIABLE} syntax
        def replace_simple(match):
            var_name = match.group(1)
            return os.environ.get(var_name, f"${{{var_name}}}")  # Keep original if not found
        
        # Pattern for ${VAR}
        value = re.sub(r'\$\{([^}]+)\}', replace_simple, value)
        
        # Handle $VARIABLE syntax (without braces)
        def replace_dollar(match):
            var_name = match.group(1)
            return os.environ.get(var_name, f"${var_name}")  # Keep original if not found
        
        # Pattern for $VAR (but not if it's already in braces)
        value = re.sub(r'\$([A-Za-z_][A-Za-z0-9_]*)', replace_dollar, value)
        
        return value
    
    def _remove_inline_comments(self, value: str) -> str:
        """Remove inline comments while preserving quoted strings"""
        # If the value is quoted, find the closing quote first
        if value.startswith('"'):
            # Find the matching closing quote
            quote_end = 1
            while quote_end < len(value):
                if value[quote_end] == '"' and value[quote_end-1] != '\\':
                    break
                quote_end += 1
            
            if quote_end < len(value):
                # Keep everything up to and including the closing quote
                return value[:quote_end + 1]
        elif value.startswith("'"):
            # Find the matching closing quote
            quote_end = 1
            while quote_end < len(value):
                if value[quote_end] == "'" and value[quote_end-1] != '\\':
                    break
                quote_end += 1
            
            if quote_end < len(value):
                # Keep everything up to and including the closing quote
                return value[:quote_end + 1]
        else:
            # No quotes, look for comment marker
            comment_pos = value.find('#')
            if comment_pos > 0:
                # Remove everything from the comment marker onwards
                value = value[:comment_pos].strip()
        
        return value
    
    def _update_from_shell_vars(self, shell_vars: Dict[str, str]) -> None:
        """Update configuration from shell variables dictionary"""
        # Core configuration
        if 'K8SVER' in shell_vars:
            self.k8s_version = shell_vars['K8SVER']
        if 'K8CL' in shell_vars:
            self.k8_client = shell_vars['K8CL']
        if 'HOST_OS' in shell_vars:
            self.host_os = shell_vars['HOST_OS']
        
        # Network configuration
        if 'K8_CIDR' in shell_vars:
            self.k8_cidr = shell_vars['K8_CIDR']
        if 'K8CIDR' in shell_vars:  # Also support the variant without underscore
            self.k8_cidr = shell_vars['K8CIDR']
        if 'NETOP_NAMESPACE' in shell_vars:
            self.netop_namespace = shell_vars['NETOP_NAMESPACE']
        if 'NETOP_NETWORK_RANGE' in shell_vars:
            self.netop_network_range = shell_vars['NETOP_NETWORK_RANGE']
        if 'NETOP_NETWORK_GW' in shell_vars:
            self.netop_network_gw = shell_vars['NETOP_NETWORK_GW']
        if 'NETOP_PERNODE_BLOCKSIZE' in shell_vars:
            try:
                self.netop_pernode_blocksize = int(shell_vars['NETOP_PERNODE_BLOCKSIZE'])
            except ValueError:
                logger.warning(f"Invalid NETOP_PERNODE_BLOCKSIZE value: {shell_vars['NETOP_PERNODE_BLOCKSIZE']}")
        
        # Network Operator configuration
        if 'NETOP_VERSION' in shell_vars:
            self.netop_version = shell_vars['NETOP_VERSION']
        if 'HELM_NVIDIA_REPO' in shell_vars:
            self.helm_nvidia_repo = shell_vars['HELM_NVIDIA_REPO']
        if 'PROD_VER' in shell_vars:
            self.prod_version = shell_vars['PROD_VER'] == '1'
        
        # Calico configuration
        if 'CALICO_ROOT' in shell_vars:
            self.calico_root = shell_vars['CALICO_ROOT']
        if 'CNIPLUGINS_VERSION' in shell_vars:
            self.cniplugins_version = shell_vars['CNIPLUGINS_VERSION']
        
        # Use case configuration
        if 'USECASE' in shell_vars:
            self.usecase = shell_vars['USECASE']
        if 'NUM_VFS' in shell_vars:
            try:
                self.num_vfs = int(shell_vars['NUM_VFS'])
            except ValueError:
                logger.warning(f"Invalid NUM_VFS value: {shell_vars['NUM_VFS']}")
        
        # IPAM configuration
        if 'IPAM_TYPE' in shell_vars:
            self.ipam_type = shell_vars['IPAM_TYPE']
        if 'NVIPAM_POOL_TYPE' in shell_vars:
            self.nvipam_pool_type = shell_vars['NVIPAM_POOL_TYPE']
        
        # Feature flags
        if 'OFED_ENABLE' in shell_vars:
            self.ofed_enable = shell_vars['OFED_ENABLE'].lower() == 'true'
        if 'OFED_BLACKLIST_ENABLE' in shell_vars:
            self.ofed_blacklist_enable = shell_vars['OFED_BLACKLIST_ENABLE'].lower() == 'true'
        if 'NFD_ENABLE' in shell_vars:
            self.nfd_enable = shell_vars['NFD_ENABLE'].lower() == 'true'
        if 'CREATE_CONFIG_ONLY' in shell_vars:
            self.create_config_only = shell_vars['CREATE_CONFIG_ONLY'] == '1'
        if 'NIC_CONFIG_ENABLE' in shell_vars:
            self.nic_config_enable = shell_vars['NIC_CONFIG_ENABLE'].lower() == 'true'
        if 'ENABLE_NFSRDMA' in shell_vars:
            self.enable_nfsrdma = shell_vars['ENABLE_NFSRDMA'].lower() == 'true'
        
        # Network settings
        if 'NETOP_MTU' in shell_vars:
            try:
                self.netop_mtu = int(shell_vars['NETOP_MTU'])
            except ValueError:
                logger.warning(f"Invalid NETOP_MTU value: {shell_vars['NETOP_MTU']}")
        if 'RDMASHAREDMODE' in shell_vars:
            self.rdma_shared_mode = shell_vars['RDMASHAREDMODE'].lower() == 'true'
        if 'SBRMODE' in shell_vars:
            self.sbr_mode = shell_vars['SBRMODE'].lower() == 'true'
        
        # Hardware configuration
        if 'NETOP_VENDOR' in shell_vars:
            self.netop_vendor = shell_vars['NETOP_VENDOR']
        if 'WORKERNODE' in shell_vars:
            self.worker_node = shell_vars['WORKERNODE']
        if 'SYSCTL_CONFIG' in shell_vars:
            self.sysctl_config = shell_vars['SYSCTL_CONFIG']
    
    @property
    def netop_helm_url(self) -> str:
        """Get the Helm chart URL based on production version"""
        if self.prod_version:
            return f"https://helm.ngc.nvidia.com/nvidia/charts/network-operator-{self.netop_version}.tgz"
        else:
            return f"https://helm.ngc.nvidia.com/nvstaging/mellanox/charts/network-operator-{self.netop_version}.tgz"
    
    @property
    def calico_version(self) -> str:
        """Get the full Calico version string"""
        return f"v{self.calico_root}"
    
    def get_usecase_config_path(self) -> str:
        """Get the path to the usecase-specific configuration"""
        return os.path.join(self.netop_root_dir, "usecase", self.usecase, "netop.cfg")
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert configuration to dictionary"""
        return {
            'netop_root_dir': self.netop_root_dir,
            'k8s_version': self.k8s_version,
            'k8_client': self.k8_client,
            'host_os': self.host_os,
            'k8_cidr': self.k8_cidr,
            'netop_namespace': self.netop_namespace,
            'netop_app_namespaces': self.netop_app_namespaces,
            'netop_network_range': self.netop_network_range,
            'netop_network_gw': self.netop_network_gw,
            'netop_pernode_blocksize': self.netop_pernode_blocksize,
            'netop_version': self.netop_version,
            'helm_nvidia_repo': self.helm_nvidia_repo,
            'prod_version': self.prod_version,
            'calico_root': self.calico_root,
            'cniplugins_version': self.cniplugins_version,
            'usecase': self.usecase,
            'num_vfs': self.num_vfs,
            'device_types': self.device_types,
            'ipam_type': self.ipam_type,
            'nvipam_pool_type': self.nvipam_pool_type,
            'ofed_enable': self.ofed_enable,
            'ofed_blacklist_enable': self.ofed_blacklist_enable,
            'nfd_enable': self.nfd_enable,
            'create_config_only': self.create_config_only,
            'nic_config_enable': self.nic_config_enable,
            'enable_nfsrdma': self.enable_nfsrdma,
            'netop_mtu': self.netop_mtu,
            'rdma_shared_mode': self.rdma_shared_mode,
            'sbr_mode': self.sbr_mode,
            'netop_vendor': self.netop_vendor,
            'netop_sulist': self.netop_sulist,
            'worker_node': self.worker_node,
            'sysctl_config': self.sysctl_config,
        }
    
    def save_to_file(self, filepath: str) -> None:
        """Save configuration to JSON file"""
        with open(filepath, 'w') as f:
            json.dump(self.to_dict(), f, indent=2)
    
    @classmethod
    def load_from_file(cls, filepath: str) -> 'NetOpConfig':
        """Load configuration from JSON file"""
        with open(filepath, 'r') as f:
            data = json.load(f)
        
        config = cls()
        for key, value in data.items():
            if hasattr(config, key):
                setattr(config, key, value)
        
        return config

def get_config() -> NetOpConfig:
    """Get the global configuration instance"""
    return NetOpConfig.from_env()

def validate_environment() -> bool:
    """Validate that required environment variables are set"""
    config = get_config()
    
    if not config.netop_root_dir:
        logger.error("NETOP_ROOT_DIR is not set")
        return False
    
    if not os.path.exists(config.netop_root_dir):
        logger.error(f"NETOP_ROOT_DIR does not exist: {config.netop_root_dir}")
        return False
    
    return True 
