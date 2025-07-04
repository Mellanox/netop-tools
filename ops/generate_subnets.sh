#!/bin/bash

# Function to convert IP to decimal
ip_to_decimal() {
    local ip=$1
    local a b c d
    IFS='.' read -r a b c d <<< "$ip"
    echo $((a * 256**3 + b * 256**2 + c * 256 + d))
}

# Function to convert decimal to IP
decimal_to_ip() {
    local num=$1
    local a=$((num / 256**3))
    local b=$(((num % 256**3) / 256**2))
    local c=$(((num % 256**2) / 256))
    local d=$((num % 256))
    echo "$a.$b.$c.$d"
}

# Function to calculate subnet size based on netmask
get_subnet_size() {
    local netmask=$1
    echo $((2**(32-netmask)))
}

# Main function to generate subnets
generate_subnets() {
    local input_cidr=$1
    local count=$2
    local gateway_pattern=$3
    
    # Parse IP and netmask
    local ip=$(echo "$input_cidr" | cut -d'/' -f1)
    local netmask=$(echo "$input_cidr" | cut -d'/' -f2)
    
    # Convert IP to decimal
    local ip_decimal=$(ip_to_decimal "$ip")
    
    # Calculate subnet size
    local subnet_size=$(get_subnet_size "$netmask")
    
    # Convert gateway pattern to decimal if provided
    local gateway_base_decimal=""
    if [ -n "$gateway_pattern" ]; then
        gateway_base_decimal=$(ip_to_decimal "$gateway_pattern")
    fi
    
    # Generate subnets (starting from the original subnet)
    for ((i=0; i<count; i++)); do
        local next_ip_decimal=$((ip_decimal + subnet_size * i))
        local next_ip=$(decimal_to_ip "$next_ip_decimal")
        
        # Calculate gateway IP
        local gateway_ip
        if [ -n "$gateway_pattern" ]; then
            # Use the gateway pattern with the same increment as the subnet
            local gateway_ip_decimal=$((gateway_base_decimal + subnet_size * i))
            gateway_ip=$(decimal_to_ip "$gateway_ip_decimal")
        else
            # Default behavior: first available IP in subnet
            local gateway_ip_decimal=$((next_ip_decimal + 1))
            gateway_ip=$(decimal_to_ip "$gateway_ip_decimal")
        fi
        
        echo "$next_ip/$netmask Gateway: $gateway_ip"
    done
}

# Check if correct number of arguments provided
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "Usage: $0 <IP/netmask> <count> [gateway_pattern]"
    echo "Example: $0 192.168.0.0/24 3  # Generates 192.168.0.0/24, 192.168.1.0/24, 192.168.2.0/24"
    echo "Example: $0 192.168.0.0/24 2 192.168.0.1  # Custom gateway pattern"
    exit 1
fi

# Validate input format
if ! echo "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$'; then
    echo "Error: Invalid IP/netmask format. Use format like 192.168.0.0/24"
    exit 1
fi

# Validate count is a positive integer
if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -eq 0 ]; then
    echo "Error: Count must be a positive integer"
    exit 1
fi

# Validate gateway pattern if provided
if [ $# -eq 3 ]; then
    if ! echo "$3" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "Error: Invalid gateway pattern format. Use format like 192.168.0.1"
        exit 1
    fi
fi

# Generate and display subnets
generate_subnets "$1" "$2" "$3" 