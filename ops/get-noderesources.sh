#!/bin/bash
#
# get the node resources
#kubectl get no -o json | jq -r '[.items[] | {name:.metadata.name, allocable:.status.allocatable}]'
kubectl get no -o json | jq -r '[.items[] | {name:.metadata.name, allocable:.status}]'

