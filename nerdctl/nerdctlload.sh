#!/bin/bash
#
#
nerdctl --namespace=k8s.io image load < ${1}
