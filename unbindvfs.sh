#!/bin/bash
#
# run on the worker nodes
#
# Unbinds all VFs of the given PF BDF(s) from their current drivers,
# then zeros sriov_numvfs. Companion to setvfs.sh — scoped to specific
# PFs, not host-wide.
#
# Usage: unbindvfs.sh <BDF> [<BDF> ...]
#
set -u

rc=0
for BDF in ${*};do
  PFPATH="/sys/bus/pci/devices/${BDF}"
  NUMVFS_F="${PFPATH}/sriov_numvfs"
  echo "PF:${BDF}"
  if [ ! -w "${NUMVFS_F}" ];then
    echo "WARNING:Not Found or not writable:${BDF}"
    rc=1
    continue
  fi
  NUMVFS=$(cat "${NUMVFS_F}" 2>/dev/null || echo 0)
  if ! [ "${NUMVFS}" -gt 0 ] 2>/dev/null;then
    echo "  ${BDF}: no VFs currently configured (sriov_numvfs=${NUMVFS}) — skip"
    continue
  fi
  echo "  ${BDF}: unbinding ${NUMVFS} VF(s)"
  for i in $(seq 0 $((NUMVFS-1)));do
    VF_LINK="${PFPATH}/virtfn${i}"
    [ -L "${VF_LINK}" ] || continue
    VF=$(basename $(readlink -f "${VF_LINK}"))
    DRV=$(basename $(readlink "/sys/bus/pci/devices/${VF}/driver" 2>/dev/null) 2>/dev/null || true)
    if [ -n "${DRV}" ] && [ "${DRV}" != "." ];then
      if ! echo "${VF}" | tee "/sys/bus/pci/drivers/${DRV}/unbind" >/dev/null;then
        echo "  ERROR:${VF}: failed to unbind from ${DRV}"
        rc=1
      else
        echo "    ${VF}: unbound from ${DRV}"
      fi
    fi
  done
  if ! echo 0 | tee "${NUMVFS_F}" >/dev/null;then
    echo "  ERROR:${BDF}: failed to zero sriov_numvfs"
    rc=1
  fi
done
exit ${rc}
