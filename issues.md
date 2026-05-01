# Known Issues

Track open bugs and pending work. Add entries as issues are discovered; remove or move to HISTORY.md when resolved.

---

## Bugs

### subnet: `--gateway-pattern` rejects bare host offset
**File**: `python_tools/subnet_generator.py:102-105`
**Symptom**: `netop-tools subnet 10.0.0.0/24 2 --gateway-pattern 254` fails with `ERROR - Invalid gateway pattern: 254`
**Root cause**: `gateway_pattern` is passed directly to `ipaddress.IPv4Address()`, which requires a full dotted-quad. The original bash script accepted a bare last-octet offset (e.g., `254` meaning `.254`).
**Fix**: Detect bare integer patterns and construct the full gateway IP from the subnet's network address + offset.

---

## Stub Commands (Not Yet Implemented)

These command groups exist in `python_tools/commands/` as stubs — they parse args but do not execute. Corresponding bash scripts in the repo are still the only working implementation.

| Command | Bash directory | Module |
|---------|---------------|--------|
| `netop-tools rdma` | `rdmatest/`, `rdmatools/` | `rdma_commands.py` |
| `netop-tools repo` | `repotools/` | `repo_commands.py` |
| `netop-tools restart` | `restart/` | `restart_commands.py` |
| `netop-tools test` | `tests/` | `test_commands.py` |
| `netop-tools upgrade` | `upgrade/` | `upgrade_commands.py` |
| `netop-tools nerdctl` | `nerdctl/` | `nerdctl_commands.py` |
| `netop-tools ngc` | `ngc/` | `ngc_commands.py` |

---

## Open Items

- **HISTORY.md `[Unreleased]` section is empty** — changes on the current `v26.4.0-beta3` branch have not been logged yet.
- **`run_tests.sh` / `test_netop_tools.py` not integrated into CI** — `.github/workflows/main.yml` runs `tests/unitest.sh` (bash YAML diff tests) but not the Python test suite.
