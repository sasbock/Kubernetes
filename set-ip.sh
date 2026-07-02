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

if grep -qiE 'rocky' /etc/os-release; then
	DISTRIBUTION=rocky
elif grep -qiE 'fedora' /etc/os-release; then
	DISTRIBUTION=fedora
elif grep -qiE 'ubuntu' /etc/os-release; then
	DISTRIBUTION=ubuntu
else
	echo "Unsupported distribution"
	exit 1
fi

case "$DISTRIBUTION" in
rocky|fedora)
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

    nmcli connection up "$INTERFACE"

    echo "Successfully configured $INTERFACE with IP address $IPADDR."
    ;;
ubuntu)
	cat <<-EOF | tee /etc/netplan/00-installer-config.yaml > /dev/null
	network:
		version: 2
		renderer: networkd
		ethernets:
			enp0s8:
				dhcp4: false
				dhcp6: false
				addresses:
					- $IPADDR
	EOF

	sudo netplan apply

	;;
esac
