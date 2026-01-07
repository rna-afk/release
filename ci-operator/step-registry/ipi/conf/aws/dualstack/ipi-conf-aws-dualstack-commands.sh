#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo "Configuring AWS dual-stack networking for install-config.yaml"

# Read the current install-config.yaml
CONFIG="${SHARED_DIR}/install-config.yaml"

# Determine primary IP family (default to IPv4-primary)
# Set DUALSTACK_PRIMARY_IP_FAMILY=ipv6 to make IPv6 primary
PRIMARY_IP_FAMILY="${DUALSTACK_PRIMARY_IP_FAMILY:-ipv4}"

echo "Configuring dual-stack with ${PRIMARY_IP_FAMILY} as primary IP family"

# Add dual-stack networking configuration
# The order of CIDRs determines the primary IP family:
# - IPv4-primary: IPv4 CIDRs listed first
# - IPv6-primary: IPv6 CIDRs listed first

if [[ "${PRIMARY_IP_FAMILY}" == "ipv6" ]]; then
  # IPv6-primary configuration
  cat >> "${CONFIG}" << EOF
networking:
  networkType: OVNKubernetes
  machineNetwork:
  - cidr: 10.0.0.0/16
  clusterNetwork:
  - cidr: fd01::/48
    hostPrefix: 64
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - fd02::/112
  - 172.30.0.0/16
EOF
else
  # IPv4-primary configuration (default)
  cat >> "${CONFIG}" << EOF
networking:
  networkType: OVNKubernetes
  machineNetwork:
  - cidr: 10.0.0.0/16
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  - cidr: fd01::/48
    hostPrefix: 64
  serviceNetwork:
  - 172.30.0.0/16
  - fd02::/112
EOF
fi

echo "Dual-stack networking configuration added to install-config.yaml (${PRIMARY_IP_FAMILY}-primary)"
cat "${CONFIG}"
