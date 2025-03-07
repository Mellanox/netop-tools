#!/bin/bash

#Delete stale (not used) resource from the node
# Input:
#   $1: node name
#   $2: resource name (Example: nvidia.com/sriov_resouce_a)

# '/' symbol is a special character in JSON, so we need to escape it
# and replace it with '~1'

node=$1
res=$2
res=${res/\//~1}

curl --header "Content-Type: application/json-patch+json" \
  --request PATCH \
  --data '[{"op": "remove", "path": "/status/capacity/'${res}'"}]' \
  http://localhost:8001/api/v1/nodes/${node}/status

# Print the result
echo "Resource '${res}' deleted from node '${node}'"
