#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

trap 'CHILDREN=$(jobs -p); if test -n "${CHILDREN}"; then kill ${CHILDREN} && wait; fi' TERM

export HOME=/tmp

RESOURCE_GROUP=$(cat "${SHARED_DIR}/RESOURCE_GROUP_NAME")
az resource delete --resource-group $RESOURCE_GROUP
az network dns zone list