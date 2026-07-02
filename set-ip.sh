#!/usr/bin/env bash

set -euo pipefail

INTERFACE="enp0s8"

usage() {
    echo "Usage: $0 <IPv4/CIDR>"
    echo "Example: $0 192.168.1.100/24"
    exit 1
}

# Verify an IP address was supplied
[[ $# -eq 1 ]] || usage
IPADDR="$1"

# Must be run as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root."
    exit 1
fi

# Verify Rocky Linux
if [[ ! -f /etc/os-release ]]; then
    echo "Error: Cannot determine operating system."
    exit 1
fi

source /etc/os-release

if [[ "$ID" != "rocky" ]]; then
    echo "Error: This script only supports Rocky Linux."
    exit 1
fi

# Verify NetworkManager is available
if ! command -v nmcli >/dev/null 2>&1; then
    echo "Error: nmcli is not installed."
    exit 1
fi

# Verify interface exists
if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
    echo "Error: Network interface '$INTERFACE' does not exist."
    exit 1
fi

# Find the NetworkManager connection associated with the interface
CONNECTION=$(nmcli -t -f NAME,DEVICE connection show | \
    awk -F: -v iface="$INTERFACE" '$2 == iface { print $1; exit }')

if [[ -z "$CONNECTION" ]]; then
    echo "Error: No NetworkManager connection found for $INTERFACE."
    exit 1
fi

echo "Updating interface '$INTERFACE' on Rocky Linux..."
echo "Connection: $CONNECTION"
echo "New IP: $IPADDR"

# Configure a static IPv4 address while leaving the current gateway/DNS unchanged.
nmcli connection modify "$CONNECTION" \
    ipv4.addresses "$IPADDR" \
    ipv4.method manual

# Reactivate the connection
nmcli connection down "$CONNECTION" || true
nmcli connection up "$CONNECTION"

echo "Successfully configured $INTERFACE with IP address $IPADDR."
