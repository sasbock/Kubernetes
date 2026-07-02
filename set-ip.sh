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

# Remove any existing connection for the interface
while read -r NAME DEVICE; do
    if [[ "$DEVICE" == "$INTERFACE" ]]; then
        nmcli connection delete "$NAME"
    fi
done < <(nmcli -t -f NAME,DEVICE connection show)

# Create a new persistent connection
nmcli connection add \
    type ethernet \
    ifname "$INTERFACE" \
    con-name "$INTERFACE" \
    ipv4.method manual \
    ipv4.addresses "$IPADDR" \
    ipv6.method ignore \
    autoconnect yes

nmcli connection up "$INERFACE"

echo "Successfully configured $INTERFACE with IP address $IPADDR."
