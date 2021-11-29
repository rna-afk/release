#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

trap 'CHILDREN=$(jobs -p); if test -n "${CHILDREN}"; then kill ${CHILDREN} && wait; fi' TERM
CLUSTER_NAME=${NAMESPACE}-${JOB_NAME_HASH}
export CLUSTER_NAME

workers=3
if [[ "${CLUSTER_VARIANT}" =~ "compact" ]]; then
  workers=0
fi

cat > ${SHARED_DIR}/installer/install-config.yaml << EOF
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
compute:
- name: worker
  replicas: ${workers}
controlPlane:
  name: master
  replicas: 3
platform:
  none: {}
EOF

network_type="${CLUSTER_NETWORK_TYPE-}"
if [[ "${CLUSTER_VARIANT}" =~ "ovn" ]]; then
  network_type=OVNKubernetes
fi
if [[ -n "${network_type}" ]]; then
  cat >> ${SHARED_DIR}/installer/install-config.yaml << EOF
networking:
  networkType: ${network_type}
EOF
fi

if [[ "${CLUSTER_VARIANT}" =~ "mirror" ]]; then
  cat >> ${SHARED_DIR}/installer/install-config.yaml << EOF
imageContentSources:
- source: "${MIRROR_BASE}-scratch"
  mirrors:
  - "${MIRROR_BASE}"
EOF
fi

if [[ "${CLUSTER_VARIANT}" =~ "fips" ]]; then
  cat >> ${SHARED_DIR}/installer/install-config.yaml << EOF
fips: true
EOF
fi

cat >> ${SHARED_DIR}/installer/install-config.yaml << EOF
pullSecret: >
  ${PULL_SECRET}
EOF