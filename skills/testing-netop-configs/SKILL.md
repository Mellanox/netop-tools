---
name: testing-netop-configs
description: Run and create tests for netop-tools configuration generation. Use when running unitest.sh, validating YAML generation, creating new test cases, checking test baselines, debugging test failures, or verifying config changes don't break existing tests.
---

# Testing netop-tools Configurations

Tests validate YAML generation by diffing output against baseline files.

## Running Tests

```bash
source NETOP_ROOT_DIR.sh

# Run all tests
./tests/unitest.sh

# Run a specific test
./tests/unitest.sh tests/sriovnet_rdma/1/config
```

## How Tests Work

1. Sets `CREATE_CONFIG_ONLY=1` (generate YAML, don't deploy)
2. Sources test's `config` file as `GLOBAL_OPS_USER`
3. Runs `install/ins-network-operator.sh` to generate YAML
4. Runs `diff -ruN` between generated YAML and baseline `*.yaml` files
5. Non-zero exit if any diffs found

## Available Test Scenarios

| Directory | Scenarios |
|---|---|
| `tests/sriovnet_rdma/` | `1/`, `2/`, `combined/`, `rdmaMode/` |
| `tests/sriovibnet_rdma/` | `basic/`, `combined/` |
| `tests/hostdev/` | `basic/`, `combined/` |
| `tests/macvlan_rdma_shared_device/` | `1/`, `combined/` |
| `tests/25_10/` | `sriovnet_rdma/1/`, `sriovibnet_rdma/1/` |

## Creating a New Test

```bash
# 1. Create test directory
mkdir -p tests/my_test

# 2. Create config file with overrides
cat > tests/my_test/config << 'EOF'
export NETOP_VERSION="26.1.0"
export USECASE="sriovnet_rdma"
export NETOP_NETLIST=( a,,,0000:08:00.0 b,,,0000:86:00.1 )
export DEVICE_TYPES=( "connectx-7" )
export NUM_VFS=8
# ... other overrides
EOF

# 3. Generate baseline YAML
export CREATE_CONFIG_ONLY=1
export GLOBAL_OPS_USER=$(pwd)/tests/my_test/config
source ${GLOBAL_OPS_USER}
${NETOP_ROOT_DIR}/install/ins-network-operator.sh

# 4. Copy generated YAML as baselines
cp usecase/${USECASE}/*.yaml tests/my_test/

# 5. Verify test passes
./tests/unitest.sh tests/my_test/config
```

## Test Directory Structure

```
tests/my_test/
  config              # Sourced as GLOBAL_OPS_USER (required)
  netop.cfg           # Optional use-case overrides
  NicClusterPolicy.yaml    # Baseline YAML files
  values.yaml
  network.yaml
  ippool-*.yaml
  ...
```

## Debugging Test Failures

When a test fails, `unitest.sh` shows the diff. Common causes:

| Symptom | Cause | Fix |
|---|---|---|
| All tests fail | Changed default in `global_ops.cfg` | Regenerate all baselines |
| One test fails | Config override missing | Add missing variable to test's `config` |
| New YAML file not compared | Test dir missing baseline | Copy generated file to test dir |
| Version-specific failures | `NETOP_VERSION` changed behavior | Create version-specific test under `tests/` |

## CI Integration

GitHub Actions (`.github/workflows/main.yml`) runs `tests/unitest.sh` on ubuntu-22.04 on every push. Tests are discovered automatically by finding `config` files via `find`.
