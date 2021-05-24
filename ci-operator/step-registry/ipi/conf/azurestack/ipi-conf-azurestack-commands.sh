#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

CONFIG="${SHARED_DIR}/install-config.yaml"

REGION="ppe2"
echo "Azure region: ${REGION}"

workers=3
if [[ "${SIZE_VARIANT}" == "compact" ]]; then
  workers=0
fi
master_type=null
if [[ "${SIZE_VARIANT}" == "xlarge" ]]; then
  master_type=Standard_D32s_v3
elif [[ "${SIZE_VARIANT}" == "large" ]]; then
  master_type=Standard_D16s_v3
elif [[ "${SIZE_VARIANT}" == "compact" ]]; then
  master_type=Standard_D8s_v3
fi

ENDPOINT="https://management.ppe2.stackpoc.com"
echo "ASH ARM Endpoint: ${ENDPOINT}"

azurestackjson=$(cat <<EOF
{
  "name": "AzureStackCloud",
  "resourceManagerEndpoint": "https://management.ppe2.stackpoc.com",
  "activeDirectoryEndpoint": "https://login.microsoftonline.com/",
  "galleryEndpoint": "https://providers.ppe2.local:30016/",
  "storageEndpointSuffix": "https://providers.ppe2.local:30016/",
  "serviceManagementEndpoint": "https://management.stackpoc.com/81c9b804-ec9e-4b5a-8845-1d197268b1f5",
  "graphEndpoint":                "https://graph.windows.net/",
  "resourceIdentifiers": {
    "graph": "https://graph.windows.net/"
  }
}
EOF
)

cat $azurestackjson >> "${SHARED_DIR}/azurestackcloud.json"

export AZURE_ENVIRONMENT_FILEPATH=${SHARED_DIR}/azurestackcloud.json
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=quay.io/padillon/ash-release-mirror:latest
export OPENSHIFT_INSTALL_OS_IMAGE_OVERRIDE=https://rhcossa.blob.ppe3.stackpoc.com/vhd/rhcos4.vhd
cat "/var/run/azurestack-cluster-secrets/service-principal" >> "${SHARED_DIR}/osServicePrincipal.json"

cat >> "${CONFIG}" << EOF
baseDomain: ppe.ash.devcluster.openshift.com
metadata:
  name: ci-op
platform:
  azure:
    baseDomainResourceGroupName: os4-common
    region: ${REGION}
controlPlane:
  name: master
  platform:
    azure:
      azure_arm_endpoint: ${ENDPOINT}
      type: ${master_type}
compute:
- name: worker
  replicas: ${workers}
  platform:
    azure:
      type: ${COMPUTE_NODE_TYPE}
EOF
