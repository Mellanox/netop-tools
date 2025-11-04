#!/bin/bash
#
#
cat << HEREDOC >> nic-fw-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nic-fw-storage-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs-csi
  hostPath:
    path: /cm/shared/nic-fw-storage-pv
HEREDOC
