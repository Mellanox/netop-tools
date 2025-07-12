#!/bin/bash
#
#
#
nerdctl --namespace=k8s.io image load <${1}
#nerdctl --namespace=k8s.io tag docker.io/library/my-perftest-image:latest my-perftest-image:latest
