#!/bin/bash
#
# Kubernetes readiness testing functions
#
set -euo pipefail

function nsReady()
{
    local READY=0
    local MAX_WAIT_TIME=600  # 10 minutes maximum wait
    local START_TIME=$(date +%s)
    local CURRENT_TIME
    
    echo "Checking pod readiness (timeout: ${MAX_WAIT_TIME}s)..."
    
    while [ "${READY}" = "0" ]; do
        READY=1
        
        # Check timeout
        CURRENT_TIME=$(date +%s)
        if [ $((CURRENT_TIME - START_TIME)) -gt ${MAX_WAIT_TIME} ]; then
            echo "ERROR: Timeout waiting for pods to be ready (${MAX_WAIT_TIME}s)"
            return 1
        fi
        
        # Check each required pod
        for POD in "${PODLIST[@]}"; do
            # Parse pod specification: count,namespace,name-pattern
            IFS=',' read -r CNT NS NAME <<< "${POD}"
            
            # Validate inputs
            if [ -z "$CNT" ] || [ -z "$NS" ] || [ -z "$NAME" ]; then
                echo "ERROR: Invalid pod specification: $POD"
                return 1
            fi
            
            # Count running pods matching pattern
            local RCNT
            if ! RCNT=$("${K8CL}" get pods -n "$NS" --no-headers 2>/dev/null | \
                       awk -v pattern="$NAME" '$1 ~ pattern && $3 == "Running" {count++} END {print count+0}'); then
                echo "ERROR: Failed to query pods in namespace $NS"
                return 1
            fi
            
            # Check if we have enough running pods
            if [ "${RCNT}" -lt "${CNT}" ]; then
                READY=0
                echo "Waiting for $CNT instances of pod '$NAME' in '$NS' namespace. Currently ready: $RCNT"
                break
            fi
        done
        
        # Wait before next check
        if [ "${READY}" = "0" ]; then
            sleep 10
        fi
    done
    
    echo "All required pods are ready!"
    return 0
}
