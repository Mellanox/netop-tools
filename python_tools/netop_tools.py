#!/usr/bin/env python3
"""
NVIDIA Network Operator Tools - Main Entry Point
Unified interface to all network operator tools with hierarchical commands
"""
import sys
import argparse
import logging
from pathlib import Path

# Import all tool modules
try:
    # Try relative imports first (when run as package)
    from . import (
        subnet_generator, device_tools, k8s_tools, must_gather,
        config, utils
    )
    
    # Import hierarchical command modules
    from .commands import (
        arp_commands, harbor_commands, install_commands,
        nerdctl_commands, ngc_commands, ops_commands,
        rdma_commands, repo_commands, restart_commands,
        test_commands, uninstall_commands, upgrade_commands
    )
except ImportError:
    # Fall back to absolute imports (when run as script)
    import subnet_generator
    import device_tools
    import k8s_tools
    import must_gather
    import config
    import utils
    
    # Import hierarchical command modules
    from commands import (
        arp_commands, harbor_commands, install_commands,
        nerdctl_commands, ngc_commands, ops_commands,
        rdma_commands, repo_commands, restart_commands,
        test_commands, uninstall_commands, upgrade_commands
    )

def create_main_parser():
    """Create the main argument parser with subcommands"""
    parser = argparse.ArgumentParser(
        prog="netop-tools",
        description="NVIDIA Network Operator Tools - Python Edition",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Available Commands:
  
  Legacy Commands (backward compatibility):
  subnet       Generate IPv4 subnet sequences with gateway IPs
  setvfs       Configure SR-IOV Virtual Functions
  finddev      Find device files in netop directories
  setuc        Setup Network Operator use case
  ins-k8       Install Kubernetes master components
  start-k8     Restart Kubernetes master
  rundev       Setup development environment
  must-gather  Collect Network Operator diagnostics
  config       Manage configuration settings

  Hierarchical Commands (organized by function):
  arp          ARP table management
  harbor       Harbor registry operations
  install      Installation operations
  nerdctl      Nerdctl container operations
  ngc          NGC operations
  ops          Network Operator operations
  rdma         RDMA testing and tools
  repo         Repository management
  restart      Restart operations
  test         Testing operations
  uninstall    Uninstallation operations
  upgrade      Upgrade operations

Examples:
  # Legacy format (backward compatible)
  netop-tools subnet 192.168.0.0/24 3
  netop-tools must-gather --output-dir /tmp/diagnostics
  
  # New hierarchical format
  netop-tools ops network status
  netop-tools ops config values --output values.yaml
  netop-tools install network-operator --values custom-values.yaml
  netop-tools uninstall network-operator
  netop-tools arp flush --interface eth0
        """
    )
    
    parser.add_argument(
        "--version",
        action="version",
        version="NVIDIA Network Operator Tools v1.0.0"
    )
    
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose output"
    )
    
    parser.add_argument(
        "--config-file",
        help="Path to configuration file"
    )
    
    # Create subparsers
    subparsers = parser.add_subparsers(
        dest="command",
        title="Available Commands",
        description="Network Operator management commands",
        help="Command to execute"
    )
    
    # === Legacy Commands (backward compatibility) ===
    
    # Subnet generator
    subnet_parser = subparsers.add_parser(
        "subnet",
        help="Generate IPv4 subnet sequences",
        parents=[create_subnet_parser()],
        add_help=False
    )
    
    # Device tools
    setvfs_parser = subparsers.add_parser(
        "setvfs",
        help="Configure SR-IOV Virtual Functions",
        parents=[create_setvfs_parser()],
        add_help=False
    )
    
    finddev_parser = subparsers.add_parser(
        "finddev",
        help="Find device files",
        parents=[create_finddev_parser()],
        add_help=False
    )
    
    # Kubernetes tools
    setuc_parser = subparsers.add_parser(
        "setuc",
        help="Setup use case",
        parents=[create_setuc_parser()],
        add_help=False
    )
    
    ins_k8_parser = subparsers.add_parser(
        "ins-k8",
        help="Install Kubernetes",
        parents=[create_ins_k8_parser()],
        add_help=False
    )
    
    start_k8_parser = subparsers.add_parser(
        "start-k8",
        help="Restart Kubernetes",
        parents=[create_start_k8_parser()],
        add_help=False
    )
    
    rundev_parser = subparsers.add_parser(
        "rundev",
        help="Setup development environment",
        parents=[create_rundev_parser()],
        add_help=False
    )
    
    # Must-gather
    must_gather_parser = subparsers.add_parser(
        "must-gather",
        help="Collect diagnostics",
        parents=[create_must_gather_parser()],
        add_help=False
    )
    
    # Configuration
    config_parser = subparsers.add_parser(
        "config",
        help="Manage configuration"
    )
    
    config_subparsers = config_parser.add_subparsers(
        dest="config_action",
        help="Configuration actions"
    )
    
    config_subparsers.add_parser("show", help="Show current configuration")
    config_subparsers.add_parser("validate", help="Validate configuration")
    
    export_parser = config_subparsers.add_parser("export", help="Export configuration")
    export_parser.add_argument("--format", choices=["json", "yaml"], default="json", help="Export format")
    export_parser.add_argument("--output", help="Output file")
    
    # === Hierarchical Commands ===
    
    # Create hierarchical command parsers
    arp_commands.create_arp_parser(subparsers)
    harbor_commands.create_harbor_parser(subparsers)
    install_commands.create_install_parser(subparsers)
    nerdctl_commands.create_nerdctl_parser(subparsers)
    ngc_commands.create_ngc_parser(subparsers)
    ops_commands.create_ops_parser(subparsers)
    rdma_commands.create_rdma_parser(subparsers)
    repo_commands.create_repo_parser(subparsers)
    restart_commands.create_restart_parser(subparsers)
    test_commands.create_test_parser(subparsers)
    uninstall_commands.create_uninstall_parser(subparsers)
    upgrade_commands.create_upgrade_parser(subparsers)
    
    return parser

# Legacy parser creation functions (backward compatibility)

def create_subnet_parser():
    """Create subnet generator parser"""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("cidr", help="Starting IP/CIDR (e.g., 192.168.0.0/24)")
    parser.add_argument("count", type=int, help="Number of subnets")
    parser.add_argument("--gateway-pattern", help="Gateway IP pattern")
    parser.add_argument("--format", choices=["standard", "json", "csv"], default="standard", help="Output format")
    return parser

def create_setvfs_parser():
    """Create setvfs parser"""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("num_vfs", type=int, help="Number of VFs")
    parser.add_argument("device_bdfs", nargs="+", help="Device BDF identifiers")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be done")
    return parser

def create_finddev_parser():
    """Create finddev parser"""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--directories", nargs="+", help="Directories to search")
    parser.add_argument("--extensions", nargs="+", default=["sh", "cfg", "yaml"], help="File extensions")
    parser.add_argument("--output-dir", help="Output directory")
    parser.add_argument("--save", action="store_true", help="Save results to files")
    return parser

def create_setuc_parser():
    """Create setuc parser"""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--usecase", help="Use case name")
    return parser

def create_ins_k8_parser():
    """Create ins-k8 parser"""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--stage", choices=["master", "init", "calico", "netop", "all"], default="all", help="Installation stage")
    return parser

def create_start_k8_parser():
    """Create start-k8 parser"""
    parser = argparse.ArgumentParser(add_help=False)
    return parser

def create_rundev_parser():
    """Create rundev parser"""
    parser = argparse.ArgumentParser(add_help=False)
    return parser

def create_must_gather_parser():
    """Create must-gather parser"""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--output-dir", help="Output directory")
    return parser

def handle_config_command(args):
    """Handle configuration commands"""
    if args.config_action == "show":
        cfg = config.get_config()
        import json
        print(json.dumps(cfg.to_dict(), indent=2))
        return 0
    
    elif args.config_action == "validate":
        if config.validate_environment():
            print("Configuration is valid")
            return 0
        else:
            print("Configuration validation failed")
            return 1
    
    elif args.config_action == "export":
        cfg = config.get_config()
        data = cfg.to_dict()
        
        if args.format == "yaml":
            try:
                import yaml
            except ImportError:
                print("pyyaml is required for YAML export. Install with: pip install pyyaml",
                      file=sys.stderr)
                return 1
            output = yaml.dump(data, default_flow_style=False)
        else:
            import json
            output = json.dumps(data, indent=2)
        
        if args.output:
            with open(args.output, 'w') as f:
                f.write(output)
            print(f"Configuration exported to {args.output}")
        else:
            print(output)
        
        return 0
    
    else:
        print("Unknown config action")
        return 1

def main():
    """Main entry point"""
    parser = create_main_parser()
    args = parser.parse_args()
    
    # Setup logging
    if args.verbose:
        utils.setup_logging("DEBUG")
    else:
        utils.setup_logging("INFO")
    
    # Handle no command
    if not args.command:
        parser.print_help()
        return 1
    
    try:
        # === Legacy Command Handlers (backward compatibility) ===
        
        if args.command == "subnet":
            subnets = subnet_generator.generate_subnets(
                args.cidr, args.count, args.gateway_pattern
            )
            
            if args.format == "json":
                import json
                output = [{"subnet": s, "gateway": g} for s, g in subnets]
                print(json.dumps(output, indent=2))
            elif args.format == "csv":
                print("subnet,gateway")
                for subnet, gateway in subnets:
                    print(f"{subnet},{gateway}")
            else:
                for subnet, gateway in subnets:
                    print(f"{subnet} Gateway: {gateway}")
            return 0
        
        elif args.command == "setvfs":
            success = device_tools.set_sriov_vfs(args.num_vfs, args.device_bdfs)
            return 0 if success else 1
        
        elif args.command == "finddev":
            found_files = device_tools.find_device_files(args.directories)
            filtered_files = {ext: files for ext, files in found_files.items() 
                             if ext in args.extensions}
            
            for ext, files in filtered_files.items():
                print(f"\n{ext.upper()} files ({len(files)}):")
                for file_path in files:
                    print(f"  {file_path}")
            
            if args.save:
                success = device_tools.save_device_files(filtered_files, args.output_dir)
                return 0 if success else 1
            return 0
        
        elif args.command == "setuc":
            success = k8s_tools.setup_usecase(args.usecase)
            return 0 if success else 1
        
        elif args.command == "ins-k8":
            success = k8s_tools.install_k8s_master(args.stage)
            return 0 if success else 1
        
        elif args.command == "start-k8":
            success = k8s_tools.restart_k8s_master()
            return 0 if success else 1
        
        elif args.command == "rundev":
            success = k8s_tools.run_development_environment()
            return 0 if success else 1
        
        elif args.command == "must-gather":
            must_gather_tool = must_gather.NetworkOperatorMustGather(args.output_dir)
            success = must_gather_tool.run_must_gather()
            if success:
                print(f"Must-gather completed successfully!")
                print(f"Artifacts saved to: {must_gather_tool.artifact_dir}")
            return 0 if success else 1
        
        elif args.command == "config":
            return handle_config_command(args)
        
        # === Hierarchical Command Handlers ===
        
        elif args.command == "arp":
            return arp_commands.handle_arp_command(args)
        
        elif args.command == "harbor":
            return harbor_commands.handle_harbor_command(args)
        
        elif args.command == "install":
            return install_commands.handle_install_command(args)
        
        elif args.command == "nerdctl":
            return nerdctl_commands.handle_nerdctl_command(args)
        
        elif args.command == "ngc":
            return ngc_commands.handle_ngc_command(args)
        
        elif args.command == "ops":
            return ops_commands.handle_ops_command(args)
        
        elif args.command == "rdma":
            return rdma_commands.handle_rdma_command(args)
        
        elif args.command == "repo":
            return repo_commands.handle_repo_command(args)
        
        elif args.command == "restart":
            return restart_commands.handle_restart_command(args)
        
        elif args.command == "test":
            return test_commands.handle_test_command(args)
        
        elif args.command == "uninstall":
            return uninstall_commands.handle_uninstall_command(args)
        
        elif args.command == "upgrade":
            return upgrade_commands.handle_upgrade_command(args)
        
        else:
            print(f"Unknown command: {args.command}")
            return 1
    
    except KeyboardInterrupt:
        print("\nOperation cancelled by user")
        return 130
    except Exception as e:
        logging.error(f"Error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main()) 