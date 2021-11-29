#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

trap 'CHILDREN=$(jobs -p); if test -n "${CHILDREN}"; then kill ${CHILDREN} && wait; fi' TERM
export HOME=/tmp

if [[ -z "$RELEASE_IMAGE_LATEST" ]]; then
  echo "RELEASE_IMAGE_LATEST is an empty string, exiting"
  exit 1
fi

# Ensure ignition assets are configured with the correct invoker to track CI jobs.
export OPENSHIFT_INSTALL_INVOKER="openshift-internal-ci/${JOB_NAME_SAFE}/${BUILD_ID}"
export TEST_PROVIDER='packet'
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${RELEASE_IMAGE_LATEST}"

# The oc binary is placed in the shared-tmp by the test container and we want to use
# that oc for all actions.
export PATH=${SHARED_DIR}:${PATH}

cp "$(command -v openshift-install)" ${SHARED_DIR}
mkdir ${SHARED_DIR}/installer

if [[ "${CLUSTER_VARIANT}" =~ "mirror" ]]; then
  export PATH=$PATH:${SHARED_DIR}  # gain access to oc
  # mirror the release image and override the release image to point to the mirrored one
  mkdir /tmp/.docker && cp /etc/openshift-installer/pull-secret /tmp/.docker/config.json
  oc registry login
  MIRROR_BASE=$( oc get is release -o 'jsonpath={.status.publicDockerImageRepository}' )
  oc adm release new --from-release ${RELEASE_IMAGE_LATEST} --to-image ${MIRROR_BASE}-scratch:release --mirror ${MIRROR_BASE}-scratch || echo 'ignore: the release could not be reproduced from its inputs'
  oc adm release mirror --from ${MIRROR_BASE}-scratch:release --to ${MIRROR_BASE} --to-release-image ${MIRROR_BASE}:mirrored
  RELEASE_PAYLOAD_IMAGE_SHA=$(oc get istag ${MIRROR_BASE##*/}:mirrored -o=jsonpath="{.image.metadata.name}")
  oc delete imagestream "$(basename "${MIRROR_BASE}-scratch")"
  RELEASE_IMAGE_MIRROR="${MIRROR_BASE}@${RELEASE_PAYLOAD_IMAGE_SHA}"

  echo "Installing from mirror override release ${RELEASE_IMAGE_MIRROR}"
  OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${RELEASE_IMAGE_MIRROR}"
else
  echo "Installing from release ${RELEASE_IMAGE_LATEST}"
fi

EXPIRATION_DATE=$(date -d '4 hours' --iso=minutes --utc)
SSH_PUB_KEY=$(cat "${CLUSTER_PROFILE_DIR}/packet-ssh-key")
PULL_SECRET=$(cat "${CLUSTER_PROFILE_DIR}/pull-secret")
BASE_DOMAIN="origin-ci-int-aws.dev.rhcloud.com"
CLUSTER_NAME=${NAMESPACE}-${JOB_NAME_HASH}
PACKET_PROJECT_ID=$(cat "${CLUSTER_PROFILE_DIR}/packet-project-id")
MATCHBOX_CLIENT_KEY=$(cat /var/run/cluster-secrets-metal/matchbox-client.key)
MATCHBOX_CLIENT_CERT=$(cat /var/run/cluster-secrets-metal/matchbox-client.crt)

export EXPIRATION_DATE
export SSH_PUB_KEY
export PULL_SECRET
export BASE_DOMAIN
export CLUSTER_NAME
export PACKET_PROJECT_ID
export MATCHBOX_CLIENT_KEY
export MATCHBOX_CLIENT_CERT

workers=3
if [[ "${CLUSTER_VARIANT}" =~ "compact" ]]; then
  workers=0
fi

cat > ${SHARED_DIR}/installer/matchbox-trusted-bundle.crt <<EOF
-----BEGIN CERTIFICATE-----
MIIFGDCCAwCgAwIBAgIUMcQ9HOev3PFJ0+mLyH384yQJokUwDQYJKoZIhvcNAQEL
BQAwEjEQMA4GA1UEAwwHZmFrZS1jYTAeFw0yMDA0MDExOTQ0MTdaFw0zMDAzMzAx
OTQ0MTdaMBIxEDAOBgNVBAMMB2Zha2UtY2EwggIiMA0GCSqGSIb3DQEBAQUAA4IC
DwAwggIKAoICAQDdWuSbpIV2vT97Zih//kupKbNmM6IOLjdaP1Dwq3u/DzwbcCdG
+4F/nXuRXeIpeyWYZkE2kODNRVD7/R/4U1l45K++0nVsg1MXbUzN7gOtzs0yT11N
sCD+YRyWoBRK3w2cb7wbmKKG3i3bA5uuWRBnNjSzSB71y6A1oxpFLhVTZNSumtOd
Ujc68occ5p7r3scbc/qQwFuEHhjBLdJA2rIh4djOj0gXFT5U95Bfp9AygdmjA5B6
45X8xXCH6yN0IDG1gxNLqjmCvT9A5sJyRD4NErN2LRIUn2WaS1xroqPi1ksuORuK
IdFwvCVJZ41pwtv/6oZmR2RZ/KS3C3iDygCRlamY06kdKPxEXuvy3Y9eEsnhkdSk
87QvBgMYAqwHAvWLuwfxsHsF15pxCG+nF39hF9tnH2Uxrd9i+3n7xyDXNxFOpnFv
3WVL31Pw9P797rVUntiK4eKc5bztjtfcMez9bfArqNPvBUZ/QgJ4kx2i25beiaW7
yWVXo7ZEexb50FzKV37xggAkf8e1rJ/ZKVstF7B2tsGT/jtEIHLLN7cOGofthQY7
k5S8N5cwlscKR6cGkpPOeylwDnxVZc0KbeHmVj4fAds1NvExblITTULG5aMbzyS+
NPzIyzTGP3QfDPfTIVosdtke0OzxgkRvVd02ps/UTW+JC5alH/RBqVfHdwIDAQAB
o2YwZDAdBgNVHQ4EFgQU5FnCPHCrqd4vs9819itLjcU1bFcwHwYDVR0jBBgwFoAU
5FnCPHCrqd4vs9819itLjcU1bFcwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8B
Af8EBAMCAYYwDQYJKoZIhvcNAQELBQADggIBANdEhWRNjJJqu3L3xEXIPumv49Or
Uhmsmv7LyCrE4Dkv7h5SiAfDe1t6T4IM1Uw7Zy9X2af2sOzUdm4wnkIw5srtSwmF
Grw0GzLt4/v6guM/Tv8x37Knif2oNLOedjHLvRQfknTkTiZ6FXPS1eO/LZOuqeFM
e4x+Az0O1aH/v1f6CdawXLc+grzZawX8hRrPxvXsmLY1zYbCrG3CzlyDfBKAhQWP
ZTum+mlUvrxgK5cttZ23k5d45vz/IIoB4O4PFQ588BLt2MGrylWgCqWvvJK8NzJE
RhSAhAk04fuPOHoOrZT7UAw1ecnPf6yiHkErqEOc0mLzR4RTPMWrJE6tO1ySG3Cr
vxvCvg7dcYYMZfbggG0jqvDIFoMqdP8DQG2JnaqmkNYUa2S2tNaXG/t/7/ybtD67
Wo6xCoLXy4l91ftXz2Q/eIi2fpm4Q7Y+RIQw8E7uDjHvNyKnILlLV5FsaEo9YZgT
/LjWWHwX/fSML8qwAj/QzRNqPjiSs4suPENhPWoEkByTzImryWmhX8kEFThjWiZb
QNDtcNi8j1XaJAXkJHdMgqKIlzOuXN2H4CKaTm0NFhIGr7hnApZ+gwVvqn8ftUw8
n/4Cz8FqvbNh1HLdnSjCiJ0O0pR6L4dcOgVujtY4MvAv2FXVRi2MKp9aim/PogGT
n/gYNEejzkRn3Xx9
-----END CERTIFICATE-----
EOF

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

# as a current stop gap -- this is pointing to a proxy hosted in
# the namespace "ci-test-ewolinet" on the ci cluster
if [[ "${CLUSTER_VARIANT}" =~ "proxy" ]]; then

# FIXME: due to https://bugzilla.redhat.com/show_bug.cgi?id=1750650 we need to
# use a http endpoint for the httpsProxy value
# TODO: revert back to using https://ewolinet:5f6ccbbbafc66013d012839921ada773@35.231.5.161:3128/

  cat ?> ${SHARED_DIR}/installer/install-config.yaml << EOF
proxy:
  httpsProxy: http://ewolinet:5f6ccbbbafc66013d012839921ada773@35.196.128.173:3128/
  httpProxy: http://ewolinet:5f6ccbbbafc66013d012839921ada773@35.196.128.173:3128/
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  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
  GtklzYOidGtxo1MT
  -----END CERTIFICATE-----
  -----BEGIN CERTIFICATE-----
  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
  Q/6M
  -----END CERTIFICATE-----
EOF
fi

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
echo "$(date +%s)" > "${SHARED_DIR}/CLUSTER_INSTALL_START_TIME"
openshift-install --dir=${SHARED_DIR}/installer/ create manifests &
wait "$!"

sed -i '/^  channel:/d' ${SHARED_DIR}/installer/manifests/cvo-overrides.yaml

# TODO: Replace with a more concise manifest injection approach
# if [[ -z "${CLUSTER_NETWORK_MANIFEST}" ]]; then
#     echo "${CLUSTER_NETWORK_MANIFEST}" > ${SHARED_DIR}/installer/manifests/cluster-network-03-config.yml
# fi

cat >> ${SHARED_DIR}/installer/openshift/99_kernelargs_e2e_metal.yaml << EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: "master"
  name: 99-kernelargs-e2e-metal
spec:
  kernelArguments:
    - 'console=tty0'
    - 'console=ttyS1,115200n8'
    - 'rd.neednet=1'
EOF

openshift-install --dir=${SHARED_DIR}/installer create ignition-configs

mkdir ${SHARED_DIR}/terraform
cp -r /var/lib/openshift-install/upi/metal/* ${SHARED_DIR}/terraform/
cp /bin/terraform-provider-matchbox ${SHARED_DIR}/terraform/

if openshift-install coreos print-stream-json 2>/tmp/err.txt >/tmp/coreos-print-stream.json; then
  RHCOS_JSON_FILE="/tmp/coreos-print-stream.json"
  PXE_INITRD_URL="$(jq -r '.architectures.x86_64.artifacts.metal.formats.pxe.initramfs.location' "${RHCOS_JSON_FILE}")"
  PXE_KERNEL_URL="$(jq -r '.architectures.x86_64.artifacts.metal.formats.pxe.kernel.location' "${RHCOS_JSON_FILE}")"
  PXE_OS_IMAGE_URL="$(jq -r '.architectures.x86_64.artifacts.metal.formats."raw.gz".disk.location' "${RHCOS_JSON_FILE}")"
  PXE_ROOTFS_URL="$(jq -r '.architectures.x86_64.artifacts.metal.formats.pxe.rootfs.location' "${RHCOS_JSON_FILE}")"
else
  RHCOS_JSON_FILE="/var/lib/openshift-install/rhcos.json"
  BASE_URI="$(jq -r '.baseURI' "${RHCOS_JSON_FILE}" | sed 's|https://|http://|' | sed 's|rhcos-redirector.apps.art.xq1c.p1.openshiftapps.com|releases-art-rhcos.svc.ci.openshift.org|')"
  PXE_INITRD_URL="${BASE_URI}$(jq -r '.images["live-initramfs"].path // .images["initramfs"].path' "${RHCOS_JSON_FILE}")"
  PXE_KERNEL_URL="${BASE_URI}$(jq -r '.images["live-kernel"].path // .images["kernel"].path' "${RHCOS_JSON_FILE}")"
  PXE_OS_IMAGE_URL="${BASE_URI}$(jq -r '.images["metal-bios"].path // .images["metal"].path' "${RHCOS_JSON_FILE}")"
  PXE_ROOTFS_URL="${BASE_URI}$(jq -r '.images["live-rootfs"].path' "${RHCOS_JSON_FILE}")"
fi
if [[ $PXE_KERNEL_URL =~ "live" ]]; then
  PXE_KERNEL_ARGS="coreos.live.rootfs_url=${PXE_ROOTFS_URL}"
else
  PXE_KERNEL_ARGS="coreos.inst.image_url=${PXE_OS_IMAGE_URL}"
fi
# 4.3 unified 'metal-bios' and 'metal-uefi' into just 'metal', unused in 4.6
cat > ${SHARED_DIR}/terraform/terraform.tfvars << EOF
cluster_id = "${CLUSTER_NAME}"
bootstrap_ign_file = "${SHARED_DIR}/installer/bootstrap.ign"
cluster_domain = "${CLUSTER_NAME}.${BASE_DOMAIN}"
master_count = "3"
master_ign_file = "${SHARED_DIR}/installer/master.ign"
matchbox_client_cert = "${MATCHBOX_CLIENT_CERT}"
matchbox_client_key = "${MATCHBOX_CLIENT_KEY}"
matchbox_http_endpoint = "http://http-matchbox.apps.build01.ci.devcluster.openshift.com"
matchbox_rpc_endpoint = "a3558a943132041b48b20a67aa291d99-23796056.us-east-1.elb.amazonaws.com:8081"
matchbox_trusted_ca_cert = "${SHARED_DIR}/installer/matchbox-trusted-bundle.crt"
packet_project_id = "${PACKET_PROJECT_ID}"
packet_plan = "${PACKET_PLAN}"
packet_facility = "${PACKET_FACILITY}"
packet_hardware_reservation_id = "${PACKET_HARDWARE_RESERVATION_ID}"
public_r53_zone = "${BASE_DOMAIN}"
pxe_initrd_url = "${PXE_INITRD_URL}"
pxe_kernel_url = "${PXE_KERNEL_URL}"
pxe_os_image_url = "${PXE_OS_IMAGE_URL}"
pxe_kernel_args = "${PXE_KERNEL_ARGS}"
worker_count = "${workers}"
worker_ign_file = "${SHARED_DIR}/installer/worker.ign"
EOF

PACKET_AUTH_TOKEN=$(cat "${CLUSTER_PROFILE_DIR}/packet-auth-token")
export PACKET_AUTH_TOKEN

echo "Creating resources using terraform"
(cd ${SHARED_DIR}/terraform && terraform init)

rc=1
(cd ${SHARED_DIR}/terraform && terraform apply -auto-approve) && rc=0
if test "${rc}" -eq 1; then echo "failed to create the infra resources"; exit 1; fi

echo "Waiting for bootstrap to complete"
rc=1
openshift-install wait-for bootstrap-complete &

set +e
wait "$!"
ret="$?"
set -e

if [ "$ret" -ne 0 ]; then
  echo "failed to bootstrap"
  pushd ${SHARED_DIR}/terraform
  GATHER_BOOTSTRAP_ARGS="--bootstrap $(terraform output -json | jq -r ".bootstrap_ip.value")"
  for ip in $(terraform output -json | jq -r ".master_ips.value[]")
  do
    GATHER_BOOTSTRAP_ARGS="${GATHER_BOOTSTRAP_ARGS} --master=${ip}"
  done
  popd
  openshift-install --dir=${SHARED_DIR}/installer gather bootstrap ${GATHER_BOOTSTRAP_ARGS}
  mv log-bundle* ${ARTIFACT_DIR}
  exit 1
fi

echo "Removing bootstrap host from control plane api pool"
(cd ${SHARED_DIR}/terraform && terraform apply -auto-approve=true -var=bootstrap_dns="false")

function approve_csrs() {
  while [[ ! -f ${SHARED_DIR}/setup-failed ]] && [[ ! -f ${SHARED_DIR}/setup-success ]]; do
    oc get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs --no-run-if-empty oc adm certificate approve || true
    sleep 15
  done
}

function update_image_registry() {
  while true; do
    sleep 10;
    oc get configs.imageregistry.operator.openshift.io/cluster > /dev/null && break
  done
  oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed","storage":{"emptyDir":{}}}}'
}

approve_csrs &
update_image_registry &

echo "Completing UPI setup"
openshift-install --dir=${SHARED_DIR}/installer wait-for install-complete 2>&1 | grep --line-buffered -v password &
wait "$!"

# Password for the cluster gets leaked in the installer logs and hence removing them.
sed '
  s/password: .*/password: REDACTED/g;
  s/X-Auth-Token.*/X-Auth-Token REDACTED/g;
  s/UserData:.*,/UserData: REDACTED,/g;
  ' "${SHARED_DIR}/installer/.openshift_install.log" > "${ARTIFACT_DIR}/.openshift_install.log"

echo "$(date +%s)" > "${SHARED_DIR}/TEST_TIME_INSTALL_END"
date "+%F %X" > "${SHARED_DIR}/CLUSTER_INSTALL_END_TIME"

cp -t "${SHARED_DIR}" \
    "${SHARED_DIR}/installer/auth/kubeconfig"