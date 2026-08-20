# Security Policy: netop-tools

NVIDIA is dedicated to the security and trust of our software products and services, including source code repositories managed through our organization.

If you believe you have found a security vulnerability in netop-tools, please report it privately. Do not open a public issue, pull request, or discussion for a suspected vulnerability.

## Reporting a Vulnerability

Use one of the following private reporting channels:

- **NVIDIA Vulnerability Disclosure Program (preferred):** https://www.nvidia.com/en-us/security/
- **Email:** [psirt@nvidia.com](mailto:psirt@nvidia.com)
- **PGP key for secure email:** https://www.nvidia.com/en-us/security/pgp-key
- **GitHub Private Vulnerability Reporting:** Use this repository's **Security** tab and select **Report a vulnerability**

Please include the following information in your report:

- Product or project name: `netop-tools`
- Affected version, branch, tag, or commit
- Type of vulnerability, such as credential exposure, command injection, privilege escalation, insecure Kubernetes manifest generation, or diagnostic data disclosure
- Affected component or path, such as `global_ops.cfg`, `install/`, `ops/`, `python_tools/`, `launchkit.sh`, `must-gather-network.sh`, or generated Kubernetes manifests
- Step-by-step reproduction instructions
- Proof-of-concept code or commands, if available
- Expected and observed behavior
- Potential impact to Kubernetes clusters, worker nodes, registry credentials, RDMA/SR-IOV networking, generated manifests, or diagnostic artifacts

Detailed reports help NVIDIA evaluate and address issues faster.

NVIDIA's Product Security Incident Response Team (PSIRT) will acknowledge receipt, validate the issue, assess severity, coordinate fixes, and publish security bulletins or other advisories as appropriate.

## Security Architecture & Context

`netop-tools` provides configuration automation and operational tooling for NVIDIA Network Operator deployments in Kubernetes and OpenShift environments. The repository is primarily a Bash and Python CLI/tooling codebase. It generates Kubernetes manifests for RDMA networking, SR-IOV virtual functions, IPoIB, Macvlan, HostDevice networks, IPAM resources, Network Operator Helm values, NIC policies, diagnostic bundles, container registry workflows, and test fixtures.

This software operates primarily as a **CLI / infrastructure automation tool**. Its primary security responsibility is to help operators generate and apply correct Kubernetes and network-operator configuration without exposing registry credentials, cluster state, node details, generated secrets, or privileged operational controls.

**Repository Exposure Classification:** Not determined.
Basis: origin remote is on GitHub, but repository visibility was not confirmed during this headless run; this document is written to public-safe detail.

**Service Exposure Classification:** External / Regulated (high confidence).
Basis: user-confirmed externally distributed infrastructure automation for Kubernetes networking, RDMA/SR-IOV configuration, container registry access, and operational diagnostics.

The key trust boundaries are:

- **Operator workstation or automation runner:** Scripts run with the permissions of the local shell, Python process, container runtime client, Kubernetes client, and Helm client.
- **Kubernetes API boundary:** Many tools call `kubectl` or `oc` to create, patch, delete, inspect, and collect cluster resources.
- **Host and node boundary:** Installation, restart, device, and debug scripts can interact with system services, PCI devices, kernel modules, container runtimes, and host paths.
- **Registry credential boundary:** Several workflows use registry credentials from environment variables, local config files, or Kubernetes image-pull secrets.
- **Configuration boundary:** `global_ops.cfg`, user configuration files, use-case configuration, environment variables, and generated YAML control the cluster resources that are created or modified.
- **Diagnostic data boundary:** Must-gather and launch/debug workflows collect pod logs, node descriptions, Kubernetes resources, events, runtime state, and generated archives that can contain sensitive operational data.

The repository does not expose an HTTP API or gRPC service. Its primary interfaces are shell commands, Python `argparse` CLI commands, configuration files, Kubernetes manifests, container registry commands, local files, and Kubernetes API operations.

### Threat Model

The following scenarios represent the primary security concerns for this project, based on the repository structure and code paths.

1. **Registry Credential Exposure Through Install and Export Workflows:** `global_ops.cfg`, `install/mksecret.sh`, `install/ins-helm-repo.sh`, `install/ins-netop-chart.sh`, `ops/export-release-containers.sh`, and `python_tools/commands/install_commands.py` use registry credentials from environment variables, local configuration, temporary files, command arguments, and Kubernetes image-pull secrets. If command tracing, failure output, temporary files, shell history, or diagnostics are mishandled, registry credentials could be exposed.

2. **Privileged Cluster Modification From Local CLI Inputs:** Scripts under `install/`, `ops/`, `uninstall/`, `restart/`, and `upgrade/`, plus the Python CLI in `python_tools/`, call Kubernetes, Helm, container runtime, and system tools to create namespaces, apply CRDs, patch network policies, configure nodes, manage VFs, cordon or uncordon nodes, and delete resources. If an operator runs the tools against the wrong context or with malicious configuration, the tool can modify or disrupt cluster networking and node state.

3. **Execution of Untrusted Shell Configuration:** `global_ops.cfg` sources a user configuration file and a use-case configuration file, and many Bash scripts inherit environment-controlled paths and variables. Because sourced shell files execute code, a malicious or unreviewed configuration file can execute commands with the operator's privileges before any generated manifest is reviewed.

4. **Sensitive Diagnostic Artifact Disclosure:** `python_tools/must_gather.py`, `must-gather-network.sh`, and `launchkit.sh` collect Kubernetes resource YAML, pod logs, node details, events, runtime state, live and backup policy objects, and debug archives. These artifacts can contain cluster metadata, image references, workload names, node names, secret references, or failure context that should be handled as sensitive operational data.

5. **Over-Privileged Generated Kubernetes Workloads and Manifests:** The tool generates and applies manifests for Network Operator resources, SR-IOV policies, network attachments, IPAM resources, diagnostic jobs, and test pods. Some generated workloads intentionally require elevated networking or node-level access, such as host networking, host paths, RDMA devices, or privileged pod settings. Incorrect namespace, node selector, use-case, or feature-flag configuration can broaden the impact of a mistake.

6. **Supply Chain Exposure From Downloaded Tools and Container Images:** Installer and registry workflows download Helm charts, manifests, container images, and supporting tools. `install/get_helm.sh` includes checksum and signature verification paths, while Python installation code can download and execute an installation script. Operators rely on trusted upstream sources, TLS, checksums or signatures where available, and registry access controls.

7. **Public-Safe Documentation and Configuration Hygiene:** The repository contains platform configuration examples, generated configuration patterns, and extensive operational documentation. Accidentally committing local credentials, customer-specific logs, generated manifests, debug bundles, or environment-specific configuration would expose information beyond the intended public content.

### Critical Security Assumptions

- The operator runs `netop-tools` only from a trusted checkout and reviews configuration files before sourcing or executing them.
- `global_ops_user.cfg`, use-case configuration files, environment variables, and command-line arguments are trusted inputs; the Bash workflow does not sandbox sourced configuration.
- The active Kubernetes context, Helm configuration, container runtime configuration, and kubeconfig are controlled by the intended operator and point to the intended cluster.
- Registry credentials such as API keys and image-pull secrets are protected by the host OS, shell environment hygiene, Kubernetes RBAC, and secret-management practices outside this repository.
- Generated manifests are reviewed before applying them to production clusters, especially when `CREATE_CONFIG_ONLY=0`, `NETOP_BCM_CONFIG`, NIC configuration, maintenance, DRA, SR-IOV, HostDevice, or diagnostic job features are enabled.
- Kubernetes RBAC, namespace controls, admission policy, Pod Security controls, and cluster network policy are enforced by the deployment environment.
- Diagnostic bundles, logs, generated YAML, node dumps, and runtime archives are treated as sensitive and are not committed or shared publicly without review and redaction.
- TLS, certificate validation, registry trust, package verification, and network egress controls are provided by the underlying OS, Kubernetes tools, Helm, container runtime, and deployment environment.
- The tool assumes Network Operator, Kubernetes, CNI, SR-IOV, RDMA, and NIC firmware components enforce their own runtime security boundaries after generated resources are applied.

## Scope

Security issues in scope include vulnerabilities in repository code, scripts, generated manifest logic, Python CLI behavior, credential handling, diagnostic collection, installation workflows, and documentation that could lead to credential disclosure, unauthorized cluster modification, privilege escalation, data exposure, or insecure default deployment behavior.

Issues in third-party components such as Kubernetes, Helm, container runtimes, CNI plugins, Network Operator operands, firmware, drivers, or external registries should be reported to the appropriate upstream or product security channel unless the issue is caused by netop-tools configuration or automation.

## Dependency and Supply Chain Security

`netop-tools` is primarily Bash and Python using the Python standard library. It invokes external tools such as Kubernetes clients, Helm, container runtime CLIs, OpenSSL, GPG, curl, wget, jq, and system service managers depending on the workflow.

Operators should:

- Use supported versions of Kubernetes, Helm, container runtimes, and Network Operator components.
- Keep host packages and CLI tools updated.
- Verify downloaded tools and charts where checksums or signatures are available.
- Avoid running scripts from untrusted branches or unreviewed local modifications.
- Prefer dry-run or config-only generation before applying changes to shared clusters.

## Operational Guidance

- Start with `CREATE_CONFIG_ONLY=1` and review generated YAML before applying it.
- Keep registry tokens, kubeconfigs, debug bundles, generated manifests, and local configuration files out of source control unless they are intentionally public examples.
- Run tooling from a least-privileged environment where practical, and use Kubernetes RBAC appropriate for the operation.
- Verify the active Kubernetes context before running install, uninstall, restart, upgrade, or diagnostic commands.
- Treat must-gather and launch/debug archives as sensitive operational artifacts.
- Rotate registry credentials if they may have appeared in logs, shell history, diagnostic archives, or command output.
