# Change History

Track significant changes to netop-tools. Add entries here when making notable changes.

## [Unreleased]

- Added 26.4.0 support: NicNodePolicy, Spectrum-X Operator, DRA SR-IOV driver, ib-kubernetes, NCP global config, UNLOAD_THIRD_PARTY_RDMA, ConnectX-9
- Added 6 new unit tests for 26.4.0 features (basic, globalconfig, nic_config_cx9, nic_node_policy, spectrumx, unload_rdma)
- Code review fixes: IB_PKEY_RANGE renamed to IB_GUID_RANGE (backward-compat), NCP_GLOBAL_REPO/VER overrides, NicNodePolicy CRD file-existence guard, explicit sriovnet_rdma cases in mk-nic-node-policy.sh
- CI fix: removed cleanup_temp_files from mk-network-cr.sh (was deleting pointer files that apply-network-cr.sh needs); corrected 26_4_* test baselines (removed 48 stale BCM-mode artifacts from tests that don't use BCM)
- Added SR-IOV cross-node and fabric debug scripts for pod network-status, ARP/ICMP tcpdump, VF/PF mapping, LLDP, mlxlink, switch MAC/FDB, FRR/BGP, SR-IOV operator state, and RDMA GUID/GID diagnostics
- Added optional `ops/debug-switch-fabric.yaml` support for cluster-specific worker SSH settings plus switch SSH targets, usernames, ports, and password fields; worker SSH uses Kubernetes node InternalIPs when node names are not DNS-resolvable; switch checks include LLDP-derived port VLAN/bridge membership
- Added Calico debug/fix helper for Tigera/Calico pod state, Project Calico CRDs, RBAC, APIService, kube-proxy, host CNI config, and nodeAddressAutodetectionV4 remediation
- Added dry-run stale pool network cleanup helper for removing old pool-suffixed SriovNetwork and NetworkAttachmentDefinition objects after shared network name migration

---

## 2026-03-24

- Added `CLAUDE.md` for Claude Code guidance and project documentation
- Merged gb300 branch into master (PR #373)

## 2026-03-06

- Updated configs to Network Operator 26.1.0 (PR #372)

## 2026-03-04

- Updated tooling for Network Operator 26.1.0 (PRs #370, #371)

## 2026-02-27

- Added DOCA install script for bare-metal network operator deployments (PR #369)

## 2026-02-25

- Fixed server pod IP retrieval — now pulled directly from server pod (PR #368)

## 2026-02-24

- Added NetworkPolicy for Calico (PR #367)
- Added sample lab configuration (PR #366)
- Cleaned up `script_lab.sh`

## 2026-02-09

- Added aarch64 test image support (PR #365)
- Fixed `DEBUG_SLEEP_SEC_ON_EXIT` quoting (PR #364)

## 2026-02-06

- Added IGX Trinity platform support (PR #361)
- Fixed `NETOP_NETLIST` processing for multiple devices in a network (PR #359)
- Consistent error handling and parameter checking across scripts (PR #358)
- First pass Cursor-driven cleanup: unquoted variables and shellcheck fixes (PR #357)

## 2026-01-27

- Made `nvip` git pull use `NETOP_VERSION` from `global_ops.cfg` (PR #356)

## 2026-01-22

- Disabled raw Ethernet frames on SR-IOV VFs
- Added test VM config for tutorial (PR #354)

## 2026-01-13

- Runtime detection and K8s version handling improvements (PR #353)

## 2026-01-12

- GB300: required nic-configurator to complete startup (PR #352)

## 2026-01-09

- Added Lenovo B200 server config (PR #351)
