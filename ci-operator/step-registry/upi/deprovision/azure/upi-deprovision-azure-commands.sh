#!/bin/bash
function queue() {
    local TARGET="${1}"
    shift
    local LIVE
    LIVE="$(jobs | wc -l)"
    while [[ "${LIVE}" -ge 45 ]]; do
    sleep 1
    LIVE="$(jobs | wc -l)"
    done
    echo "${@}"
    if [[ -n "${FILTER:-}" ]]; then
    "${@}" | "${FILTER}" >"${TARGET}" &
    else
    "${@}" >"${TARGET}" &
    fi
}

set +e
touch /tmp/shared/exit
export PATH=$PATH:/tmp/shared

echo "Deprovisioning cluster ..."
if [[ -f ${ARTIFACT_DIR}/installer/metadata.json ]]; then
    INFRA_ID="$(jq -r .infraID ${ARTIFACT_DIR}/installer/metadata.json)"
    az group delete --name ${INFRA_ID}-rg --yes
fi
