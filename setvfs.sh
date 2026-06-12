#!/bin/bash
#
# run on the worker nodes
#
# Usage: setvfs.sh [--autoprobe] <NUMVFS> <BDF> [<BDF> ...]
#
# Default behavior: sriov_drivers_autoprobe is disabled on each PF
# BEFORE writing sriov_numvfs. VF creation becomes a pure PCI bus
# rescan — sub-second per PF — without the synchronous mlx5_core
# probe of every VF (which takes 1-3s per VF on ConnectX-8 and is
# what makes the unflagged write appear to "hang").
#
# After this script returns, the VFs exist but have no driver bound;
# bind selectively via /sys/bus/pci/devices/<VF_BDF>/driver_override
# + /sys/bus/pci/drivers_probe.
#
# Pass --autoprobe to keep autoprobe enabled (matches stock kernel
# behavior — mlx5_core auto-binds each VF as it's created).
#
set -u

AUTOPROBE=0
if [ "${1:-}" = "--autoprobe" ];then
  AUTOPROBE=1
  shift
fi

NUMVFS=${1}
shift

rc=0
for BDF in ${*};do
  VFPATH="/sys/bus/pci/devices/${BDF}/sriov_numvfs"
  MAXPATH="/sys/bus/pci/devices/${BDF}/sriov_totalvfs"
  PROBEPATH="/sys/bus/pci/devices/${BDF}/sriov_drivers_autoprobe"
  echo "VFPATH:${VFPATH}"
  if [ ! -w "${VFPATH}" ];then
    echo "WARNING:Not Found:${BDF}"
    rc=1
    continue
  fi
  # Bounds check — exceeding sriov_totalvfs gives a cryptic EINVAL from
  # the kernel; explicit message + skip is friendlier.
  MAX=$(cat "${MAXPATH}" 2>/dev/null || echo 0)
  if [ "${NUMVFS}" -gt "${MAX}" ];then
    echo "WARNING:${BDF}: NUMVFS=${NUMVFS} exceeds sriov_totalvfs=${MAX} — skip"
    rc=1
    continue
  fi
  # Autoprobe control — must be set BEFORE sriov_numvfs is written.
  # Once a VF PCI device is created, autoprobe state is locked in for
  # that VF; flipping autoprobe later only affects subsequently-created
  # VFs.
  if [ -w "${PROBEPATH}" ];then
    if ! echo "${AUTOPROBE}" | tee "${PROBEPATH}" >/dev/null;then
      echo "WARNING:${BDF}: failed to set sriov_drivers_autoprobe=${AUTOPROBE} — continuing"
    fi
  fi
  # Zero-first reset — kernel rejects writes of N when current count != 0
  # with "Device or resource busy". Needed after a host reboot leaves a
  # stale count, and on any re-run. `tee` surfaces the write's exit code
  # (sysfs failures via `>` redirection are swallowed by bash).
  if ! echo 0 | tee "${VFPATH}" >/dev/null;then
    echo "ERROR:${BDF}: failed to zero sriov_numvfs"
    rc=1
    continue
  fi
  if ! echo "${NUMVFS}" | tee "${VFPATH}" >/dev/null;then
    echo "ERROR:${BDF}: failed to set sriov_numvfs=${NUMVFS}"
    rc=1
    continue
  fi
done
exit ${rc}
