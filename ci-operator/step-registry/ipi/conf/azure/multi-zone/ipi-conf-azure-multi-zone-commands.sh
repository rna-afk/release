#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

CONFIG="${SHARED_DIR}/install-config.yaml"
PATCH="/tmp/install-config-multi-zone.yaml.patch"

# azure_region=$(yq-go r "${CONFIG}" 'platform.azure.region')

# create a patch with existing resource group configuration
cat > "${PATCH}" << EOF
platform:
  azure:
    natGatewaySpec:
      - name: test-nat-gateway
        subnet: 10.0.255.0/24
EOF

# apply patch to install-config
yq-go m -x -i "${CONFIG}" "${PATCH}"
