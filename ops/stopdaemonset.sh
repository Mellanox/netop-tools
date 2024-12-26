#!/bin/bash
#
#
kubectl -n ${1} patch daemonset ${2} -p '{"spec": {"template": {"spec": {"nodeSelector": {"non-existing": "true"}}}}}'
