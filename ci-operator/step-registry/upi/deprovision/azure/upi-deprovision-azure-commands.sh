#!/bin/bash
set +e
echo "Deprovisioning cluster ..."
if [[ -f ${ARTIFACT_DIR}/metadata.json ]]; then
    INFRA_ID="$(jq -r .infraID ${ARTIFACT_DIR}/metadata.json)"
    az group delete --name ${INFRA_ID}-rg --yes
fi
