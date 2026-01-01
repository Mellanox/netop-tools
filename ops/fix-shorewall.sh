#!/bin/bash
#
#
#
#
# Check Shorewall rules
cat /etc/shorewall/rules

# Add Kubernetes ports
tee -a /etc/shorewall/rules << 'EOF'
# Kubernetes API
ACCEPT net fw tcp 6443
ACCEPT net fw tcp 10250
ACCEPT net fw tcp 2379:2380
EOF

# Restart Shorewall
shorewall restart
