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
export TEST_PROVIDER='azurestack'
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=quay.io/padillon/ash-release-mirror:latest
echo $OPENSHIFT_INSTALL_INVOKER

dir=/tmp/installer
mkdir "${dir}"
pushd "${dir}"
cp -t "${dir}" \
    "${SHARED_DIR}/install-config.yaml"

if ! pip -V; then
    echo "pip is not installed: installing"
    if python -c "import sys; assert(sys.version_info >= (3,0))"; then
      python -m ensurepip --user || easy_install --user 'pip'
    else
      echo "python < 3, installing pip<21"
      python -m ensurepip --user || easy_install --user 'pip<21'
    fi
fi
curl -L https://github.com/mikefarah/yq/releases/download/3.3.0/yq_linux_amd64 -o ${HOME}/yq && chmod +x ${HOME}/yq
PATH="${HOME}:${HOME}/.local/bin:${PATH}"

cat "${SHARED_DIR}/servicePrincipal.json" | jq '{subscriptionId:.subscriptionId,clientId:.appId,clientSecret:.password,tenantId:.tenant}' \
     > "${SHARED_DIR}/osServicePrincipal.json"

CLUSTER_NAME=$(yq r install-config.yaml metadata.name)
AAD_CLIENT_ID=$(jq -r .clientId ${SHARED_DIR}/osServicePrincipal.json)
AZURE_REGION=ppe3
SSH_KEY=$(yq r install-config.yaml sshKey | xargs)
BASE_DOMAIN=$(yq r install-config.yaml baseDomain)
TENANT_ID=$(jq -r .tenantId ${SHARED_DIR}/osServicePrincipal.json)
AAD_CLIENT_SECRET=$(jq -r .clientSecret ${SHARED_DIR}/osServicePrincipal.json)
APP_ID=$(jq -r .clientId ${SHARED_DIR}/osServicePrincipal.json)

export CLUSTER_NAME
export AAD_CLIENT_ID
export AZURE_REGION
export SSH_KEY
export TENANT_ID
export BASE_DOMAIN
export AAD_CLIENT_SECRET
export APP_ID

az cloud register \
    -n PPE \
    --endpoint-resource-manager "https://management.ppe3.stackpoc.com" \
    --suffix-storage-endpoint "ppe3.stackpoc.com" 
az cloud set -n PPE
az cloud update --profile 2019-03-01-hybrid
az login --service-principal -u $APP_ID -p $AAD_CLIENT_SECRET --tenant $TENANT_ID > /dev/null

# shellcheck disable=SC2034
SUBSCRIPTION_ID=$(az account show | jq -r .id)
export SUBSCRIPTION_ID
export AZURE_AUTH_LOCATION="${SHARED_DIR}/osServicePrincipal.json"

echo "Installing python modules: yaml"
python3 -c "import yaml" || pip3 install --user pyyaml

# remove workers from the install config so the mco won't try to create them
python3 -c '
import yaml;
path = "install-config.yaml";
data = yaml.full_load(open(path));
data["compute"][0]["replicas"] = 0;
open(path, "w").write(yaml.dump(data, default_flow_style=False))'

openshift-install create manifests

# we don't want to create any machine* objects 
rm -f openshift/99_openshift-cluster-api_master-machines-*.yaml
rm -f openshift/99_openshift-cluster-api_worker-machineset-*.yaml

python3 -c '
import sys, json, yaml, os;
path = "manifests/cloud-provider-config.yaml";
data = yaml.full_load(open(path));
config = json.loads(data["data"]["config"]);
config["cloud"] = "AzureStackCloud";
config["tenantId"] = os.environ["TENANT_ID"];
config["subscriptionId"] = os.environ["SUBSCRIPTION_ID"];
config["location"] = os.environ["AZURE_REGION"];
config["aadClientId"] = os.environ["AAD_CLIENT_ID"];
config["aadClientSecret"] = os.environ["AAD_CLIENT_SECRET"];
config["useManagedIdentityExtension"] = False;
config["useInstanceMetadata"] = False;
config["loadBalancerSku"] = "basic";
data["data"]["config"] = json.dumps(config);
open(path, "w").write(yaml.dump(data, default_flow_style=False))'

python3 -c '
import yaml,os;
path = "manifests/cluster-config.yaml";
data = yaml.full_load(open(path));
install_config = yaml.full_load(data["data"]["install-config"]);
platform = install_config["platform"];
platform["azure"]["cloudName"] = "AzureStackCloud";
platform["azure"]["region"] = os.environ["AZURE_REGION"];
install_config["platform"] = platform;
data["data"]["install-config"] = yaml.dump(install_config);
open(path, "w").write(yaml.dump(data, default_flow_style=False))'

python3 -c '
import base64, yaml,os;
path = "openshift/99_cloud-creds-secret.yaml";
data = yaml.full_load(open(path));
data["data"]["azure_subscription_id"] = base64.b64encode(os.environ["SUBSCRIPTION_ID"].encode("ascii")).decode("ascii");
data["data"]["azure_client_id"] = base64.b64encode(os.environ["AAD_CLIENT_ID"].encode("ascii")).decode("ascii");
data["data"]["azure_client_secret"] = base64.b64encode(os.environ["AAD_CLIENT_SECRET"].encode("ascii")).decode("ascii");
data["data"]["azure_tenant_id"] = base64.b64encode(os.environ["TENANT_ID"].encode("ascii")).decode("ascii");
data["data"]["azure_region"] = base64.b64encode(os.environ["AZURE_REGION"].encode("ascii")).decode("ascii");
open(path, "w").write(yaml.dump(data, default_flow_style=False))'

python3 -c '
import yaml;
path = "manifests/cluster-infrastructure-02-config.yml";
data = yaml.full_load(open(path));
data["status"]["platformStatus"]["azure"]["cloudName"] = "AzureStackCloud";
open(path, "w").write(yaml.dump(data, default_flow_style=False))'

# typical upi instruction
python3 -c '
import yaml;
path = "manifests/cluster-scheduler-02-config.yml";
data = yaml.full_load(open(path));
data["spec"]["mastersSchedulable"] = False;
open(path, "w").write(yaml.dump(data, default_flow_style=False))'

# typical upi instruction
python3 -c '
import yaml;
path = "manifests/cluster-dns-02-config.yml";
data = yaml.full_load(open(path));
del data["spec"]["publicZone"];
open(path, "w").write(yaml.dump(data, default_flow_style=False))'

azurestackjson=$(cat $SHARED_DIR/azurestackcloud.json)

cat << EOF > openshift/99_openshift-machineconfig_99-master-azurestackcloud.yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  creationTimestamp: null
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-master-azurestack
spec:
  config:
    ignition:
      config: {}
      security:
        tls: {}
      timeouts: {}
      version: 3.2.0
    networkd: {}
    passwd: {}
    storage:
      files:
        - path: ${SHARED_DIR}/azurestackcloud.json
          contents:
            source: data:text/plain;charset=utf-8;base64,$(echo $azurestackjson | base64 | tr -d '\n')
          mode: 420
          user:
            name: root
    systemd:
      units:
        - name: kubelet.service
          dropins:
            - name: 10-azurestack.conf
              contents: |
                [Service]
                Environment="AZURE_ENVIRONMENT_FILEPATH=/etc/kubernetes/azurestackcloud.json"
  fips: false
  kernelArguments: null
  kernelType: ""
  osImageURL: ""
EOF

INFRA_ID=$(yq r manifests/cluster-infrastructure-02-config.yml 'status.infrastructureName')
RESOURCE_GROUP=$(yq r manifests/cluster-infrastructure-02-config.yml 'status.platformStatus.azure.resourceGroupName')
echo "${RESOURCE_GROUP}" > "${SHARED_DIR}/RESOURCE_GROUP_NAME"

openshift-install create ignition-configs &

set +e
wait "$!"
ret="$?"
set -e

cp "${dir}/.openshift_install.log" "${ARTIFACT_DIR}/.openshift_install.log"

if [ $ret -ne 0 ]; then
  exit "$ret"
fi

cp -t "${SHARED_DIR}" \
    "${dir}/auth/kubeadmin-password" \
    "${dir}/auth/kubeconfig" \
    "${dir}/metadata.json" \
    ${dir}/*.ign

tar -czf "${SHARED_DIR}/.openshift_install_state.json.tgz" ".openshift_install_state.json"

export SSH_PRIV_KEY_PATH="${CLUSTER_PROFILE_DIR}/ssh-privatekey"
export OPENSHIFT_INSTALL_INVOKER="openshift-internal-ci/${JOB_NAME_SAFE}/${BUILD_ID}"

date "+%F %X" > "${SHARED_DIR}/CLUSTER_INSTALL_START_TIME"
RESOURCE_GROUP=$(cat "${SHARED_DIR}/RESOURCE_GROUP_NAME")

az group create --name "$RESOURCE_GROUP" --location "$AZURE_REGION"

az storage account create -g "$RESOURCE_GROUP" --location "$AZURE_REGION" --name "${INFRA_ID}sa" --kind Storage --sku Standard_LRS
ACCOUNT_KEY=$(az storage account keys list -g "$RESOURCE_GROUP" --account-name "${INFRA_ID}sa" --query "[0].value" -o tsv)

az storage container create --name files --account-name "${INFRA_ID}sa" --public-access blob --account-key "$ACCOUNT_KEY"
az storage blob upload --account-name "${INFRA_ID}sa" --account-key "$ACCOUNT_KEY" -c "files" -f "bootstrap.ign" -n "bootstrap.ign"

AZURESTACK_UPI_LOCATION="/var/lib/openshift-install/upi/azurestack"
az deployment group create -g "$RESOURCE_GROUP" \
  --template-file "${AZURESTACK_UPI_LOCATION}/01_vnet.json" \
  --parameters baseName="$INFRA_ID"


VHD_BLOB_URL="https://rhcossa.blob.ppe3.stackpoc.com/vhd/rhcos4.vhd"
az deployment group create -g "$RESOURCE_GROUP" \
  --template-file "${AZURESTACK_UPI_LOCATION}/02_storage.json" \
  --parameters vhdBlobURL="$VHD_BLOB_URL" \
  --parameters baseName="$INFRA_ID"

az deployment group create -g "$RESOURCE_GROUP" \
  --template-file "${AZURESTACK_UPI_LOCATION}/03_infra.json" \
  --parameters baseName="$INFRA_ID"

set +euE

az network dns zone create -g "$RESOURCE_GROUP" -n "${CLUSTER_NAME}.${BASE_DOMAIN}"
PUBLIC_IP=$(az network public-ip list -g "$RESOURCE_GROUP" --query "[?name=='${INFRA_ID}-master-pip'] | [0].ipAddress" -o tsv)
az network dns record-set a add-record -g "$RESOURCE_GROUP" -z "${CLUSTER_NAME}.${BASE_DOMAIN}" -n api -a "$PUBLIC_IP" --ttl 60
az network dns record-set a add-record -g "$RESOURCE_GROUP" -z "${CLUSTER_NAME}.${BASE_DOMAIN}" -n api-int -a "$PUBLIC_IP" --ttl 60

BOOTSTRAP_URL=$(az storage blob url --account-name "${INFRA_ID}sa" --account-key "$ACCOUNT_KEY" -c "files" -n "bootstrap.ign" -o tsv)
BOOTSTRAP_IGNITION=$(jq -rcnM --arg v "3.1.0" --arg url "$BOOTSTRAP_URL" '{ignition:{version:$v,config:{replace:{source:$url}}}}' | base64 | tr -d '\n')

az deployment group create --verbose -g "$RESOURCE_GROUP" \
  --template-file "${AZURESTACK_UPI_LOCATION}/04_bootstrap.json" \
  --parameters bootstrapIgnition="$BOOTSTRAP_IGNITION" \
  --parameters sshKeyData="$SSH_KEY" \
  --parameters baseName="$INFRA_ID" \
  --parameters diagnosticsStorageAccountName="${INFRA_ID}sa"

set -euE

MASTER_IGNITION=$(cat master.ign | base64 | tr -d '\n')
az deployment group create -g "$RESOURCE_GROUP" \
  --template-file "${AZURESTACK_UPI_LOCATION}/05_masters.json" \
  --parameters masterIgnition="$MASTER_IGNITION" \
  --parameters sshKeyData="$SSH_KEY" \
  --parameters baseName="$INFRA_ID" \
  --parameters masterVMSize="Standard_D4_v2" \
  --parameters diskSizeGB="1023" \
  --parameters diagnosticsStorageAccountName="${INFRA_ID}sa"

echo "$(date +%s)" > "${SHARED_DIR}/TEST_TIME_INSTALL_END"
date "+%F %X" > "${SHARED_DIR}/CLUSTER_INSTALL_END_TIME"
popd
touch /tmp/install-complete

