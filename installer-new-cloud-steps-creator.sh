#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# FOR TESTING: REMOVE
git reset --hard

# Change config file to add the new cloud e2e tests.
echo "Appending config file with new cloud platform e2e tests information"
read -p "Enter the new cloud platform name :" CLOUD_NAME
rm -rf ci-operator/step-registry/ipi/${CLOUD_NAME}
rm -rf ci-operator/step-registry/ipi/conf/${CLOUD_NAME}
rm -rf ci-operator/step-registry/openshift/e2e/${CLOUD_NAME}
rm -rf ci-operator/step-registry/upi/deprovision/${CLOUD_NAME}
rm -rf ci-operator/step-registry/upi/install/${CLOUD_NAME}
rm -rf ci-operator/step-registry/openshift/e2e/${CLOUD_NAME}/upi
rm -rf ci-operator/step-registry/upi/${CLOUD_NAME}

CONFIG_FILENAME=ci-operator/config/openshift/installer/openshift-installer-master.yaml
head -n -4 $CONFIG_FILENAME > tmp.txt
mv tmp.txt $CONFIG_FILENAME
cat >> "${CONFIG_FILENAME}" << EOF
- as: e2e-${CLOUD_NAME}
  steps:
    cluster_profile: ${CLOUD_NAME}
    workflow: openshift-e2e-${CLOUD_NAME}
- as: e2e-${CLOUD_NAME}-upi
  steps:
    cluster_profile: ${CLOUD_NAME}
    workflow: openshift-e2e-${CLOUD_NAME}-upi
zz_generated_metadata:
  branch: master
  org: openshift
  repo: installer
EOF

# Change jobs presubmits to add the e2e test parameters (cluster secrets, trigger etc.).
echo "Appending jobs file with new cloud platform e2e tests information"
JOBS_FILENAME=ci-operator/jobs/openshift/installer/openshift-installer-master-presubmits.yaml
cat >> ${JOBS_FILENAME} << EOF
  - agent: kubernetes
    always_run: false
    branches:
    - ^master$
    - ^master-
    cluster: build01
    context: ci/prow/e2e-${CLOUD_NAME}
    decorate: true
    labels:
      ci-operator.openshift.io/prowgen-controlled: "true"
      pj-rehearse.openshift.io/can-be-rehearsed: "true"
    name: pull-ci-openshift-installer-master-e2e-${CLOUD_NAME}
    optional: true
    rerun_command: /test e2e-${CLOUD_NAME}
    spec:
      containers:
      - args:
        - --gcs-upload-secret=/secrets/gcs/service-account.json
        - --image-import-pull-secret=/etc/pull-secret/.dockerconfigjson
        - --lease-server-credentials-file=/etc/boskos/credentials
        - --report-credentials-file=/etc/report/credentials
        - --secret-dir=/usr/local/e2e-${CLOUD_NAME}-cluster-profile
        - --target=e2e-${CLOUD_NAME}
        command:
        - ci-operator
        image: ci-operator:latest
        imagePullPolicy: Always
        name: ""
        resources:
          requests:
            cpu: 10m
        volumeMounts:
        - mountPath: /etc/boskos
          name: boskos
          readOnly: true
        - mountPath: /usr/local/e2e-${CLOUD_NAME}-cluster-profile
          name: cluster-profile
        - mountPath: /secrets/gcs
          name: gcs-credentials
          readOnly: true
        - mountPath: /etc/pull-secret
          name: pull-secret
          readOnly: true
        - mountPath: /etc/report
          name: result-aggregator
          readOnly: true
      serviceAccountName: ci-operator
      volumes:
      - name: boskos
        secret:
          items:
          - key: credentials
            path: credentials
          secretName: boskos-credentials
      - name: cluster-profile
        projected:
          sources:
          - secret:
              name: cluster-secrets-${CLOUD_NAME}
      - name: pull-secret
        secret:
          secretName: registry-pull-credentials
      - name: result-aggregator
        secret:
          secretName: result-aggregator
    trigger: (?m)^/test( | .* )e2e-${CLOUD_NAME},?($|\s.*)
  - agent: kubernetes
    always_run: false
    branches:
    - ^master$
    - ^master-
    cluster: build01
    context: ci/prow/e2e-${CLOUD_NAME}-upi
    decorate: true
    labels:
      ci-operator.openshift.io/prowgen-controlled: "true"
      pj-rehearse.openshift.io/can-be-rehearsed: "true"
    name: pull-ci-openshift-installer-master-e2e-${CLOUD_NAME}-upi
    optional: true
    rerun_command: /test e2e-${CLOUD_NAME}-upi
    spec:
      containers:
      - args:
        - --gcs-upload-secret=/secrets/gcs/service-account.json
        - --image-import-pull-secret=/etc/pull-secret/.dockerconfigjson
        - --lease-server-credentials-file=/etc/boskos/credentials
        - --report-credentials-file=/etc/report/credentials
        - --secret-dir=/usr/local/e2e-${CLOUD_NAME}-upi-cluster-profile
        - --target=e2e-${CLOUD_NAME}-upi
        command:
        - ci-operator
        image: ci-operator:latest
        imagePullPolicy: Always
        name: ""
        resources:
          requests:
            cpu: 10m
        volumeMounts:
        - mountPath: /etc/boskos
          name: boskos
          readOnly: true
        - mountPath: /usr/local/e2e-${CLOUD_NAME}-upi-cluster-profile
          name: cluster-profile
        - mountPath: /secrets/gcs
          name: gcs-credentials
          readOnly: true
        - mountPath: /etc/pull-secret
          name: pull-secret
          readOnly: true
        - mountPath: /etc/report
          name: result-aggregator
          readOnly: true
      serviceAccountName: ci-operator
      volumes:
      - name: boskos
        secret:
          items:
          - key: credentials
            path: credentials
          secretName: boskos-credentials
      - name: cluster-profile
        projected:
          sources:
          - secret:
              name: cluster-secrets-${CLOUD_NAME}
      - name: pull-secret
        secret:
          secretName: registry-pull-credentials
      - name: result-aggregator
        secret:
          secretName: result-aggregator
    trigger: (?m)^/test( | .* )e2e-${CLOUD_NAME}-upi,?($|\s.*)
EOF

# Making the IPI directory, the OWNERS file and the metadata.json for the new cloud platform. Will copy these file everywhere.
echo "Creating OWNERS and metadata files"
IPI_CLOUD_DIR="ci-operator/step-registry/ipi/${CLOUD_NAME}"
mkdir "${IPI_CLOUD_DIR}"
OWNERS_FILE_LOCATION="${IPI_CLOUD_DIR}/OWNERS"
cat > "${OWNERS_FILE_LOCATION}" << EOF
approvers:
- staebler
- patrickdillon
- mtnbikenc
- e-tienne
- jhixson74
- jstuever
- rna-afk
EOF

METADATA_FILE_LOCATION="${IPI_CLOUD_DIR}/ipi-${CLOUD_NAME}-workflow.metadata.json"
METADATA_REPLACE_TEXT="ipi/${CLOUD_NAME}/ipi-${CLOUD_NAME}-workflow.yaml"
cat > "${METADATA_FILE_LOCATION}" << EOF
{
	"path": "ipi/${CLOUD_NAME}/ipi-${CLOUD_NAME}-workflow.yaml",
	"owners": {
		"approvers": [
			"staebler",
			"rna-afk",
			"patrickdillon",
			"mtnbikenc",
			"e-tienne",
			"jhixson74",
			"jstuever"
		]
	}
}
EOF

# Creating IPI workflow yaml.
echo "Creating IPI workflow yaml file"
cat > "${IPI_CLOUD_DIR}/ipi-${CLOUD_NAME}-workflow.yaml" << EOF
workflow:
  as: ipi-$CLOUD_NAME
  steps:
    pre:
    - chain: ipi-$CLOUD_NAME-pre
    post:
    - chain: ipi-$CLOUD_NAME-post
  documentation: |-
    The IPI workflow provides pre- and post- steps that provision and
    deprovision an OpenShift cluster with a default configuration on ${CLOUD_NAME} allowing job authors to inject their own end-to-end test logic.
    All modifications to this workflow should be done by modifying the
    `ipi-${CLOUD_NAME}-{pre,post}` chains to allow other workflows to mimic and extend
    this base workflow without a need to backport changes.
EOF

# Creating pre and post installation folders.
echo "Creating pre and post installation folders"
mkdir ${IPI_CLOUD_DIR}/pre
mkdir ${IPI_CLOUD_DIR}/post
cp ${OWNERS_FILE_LOCATION} "${IPI_CLOUD_DIR}/pre"
cp ${OWNERS_FILE_LOCATION} "${IPI_CLOUD_DIR}/post"
cp ${METADATA_FILE_LOCATION} "${IPI_CLOUD_DIR}/pre/ipi-${CLOUD_NAME}-pre-chain.metadata.json"
cp ${METADATA_FILE_LOCATION} "${IPI_CLOUD_DIR}/post/ipi-${CLOUD_NAME}-post-chain.metadata.json"

# Changing the metadata files path property to match current directory.
sed -i "s|${CLOUD_NAME}/|${CLOUD_NAME}/pre/|g" "${IPI_CLOUD_DIR}/pre/ipi-${CLOUD_NAME}-pre-chain.metadata.json"
sed -i "s|${CLOUD_NAME}-|${CLOUD_NAME}-pre-|g" "${IPI_CLOUD_DIR}/pre/ipi-${CLOUD_NAME}-pre-chain.metadata.json"

sed -i "s|${CLOUD_NAME}/|${CLOUD_NAME}/post/|g" "${IPI_CLOUD_DIR}/post/ipi-${CLOUD_NAME}-post-chain.metadata.json"
sed -i "s|${CLOUD_NAME}-|${CLOUD_NAME}-post-|g" "${IPI_CLOUD_DIR}/post/ipi-${CLOUD_NAME}-post-chain.metadata.json"

# Creating the chain files.
cat > "${IPI_CLOUD_DIR}/pre/ipi-${CLOUD_NAME}-pre-chain.yaml" << EOF
chain:
  as: ipi-${CLOUD_NAME}-pre
  steps:
  - chain: ipi-conf-${CLOUD_NAME}
  - chain: ipi-install
  documentation: |-
    The IPI setup step contains all steps that provision an OpenShift cluster
    with a default configuration on ${CLOUD_NAME}.
EOF

cat > "${IPI_CLOUD_DIR}/post/ipi-${CLOUD_NAME}-post-chain.yaml" << EOF
chain:
  as: ipi-${CLOUD_NAME}-post
  steps:
  - chain: ipi-deprovision
  documentation: |-
    The IPI cleanup step contains all steps that deprovision an OpenShift
    cluster on ${CLOUD_NAME}, provisioned by the `ipi-${CLOUD_NAME}-post` chain.
EOF

# Creating the conf directory.
CONF_DIR="ci-operator/step-registry/ipi/conf/${CLOUD_NAME}"
mkdir "${CONF_DIR}"
cp ${OWNERS_FILE_LOCATION} "${CONF_DIR}"
cp ${METADATA_FILE_LOCATION} "${CONF_DIR}/ipi-conf-${CLOUD_NAME}-chain.metadata.json"
sed -i "s|ipi/${CLOUD_NAME}/ipi-${CLOUD_NAME}|ipi/conf/${CLOUD_NAME}/ipi-conf-${CLOUD_NAME}|g" "${CONF_DIR}/ipi-conf-${CLOUD_NAME}-chain.metadata.json"

cat > "${CONF_DIR}/ipi-conf-${CLOUD_NAME}-chain.yaml" << EOF
chain:
  as: ipi-conf-${CLOUD_NAME}
  steps:
  - ref: ipi-conf
  - ref: ipi-conf-${CLOUD_NAME}
  - ref: ipi-install-monitoringpvc
  documentation: |-
    The IPI configure step chain generates the install-config.yaml file based on the cluster profile and optional input files.
EOF

cat > "${CONF_DIR}/ipi-conf-${CLOUD_NAME}-commands.sh" << EOF
#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# TODO: Please fill in the necessary information for creating an install-config for your cloud platform.
Reference material are in the same folder structure in other cloud platforms.
EOF

cp "${CONF_DIR}/ipi-conf-${CLOUD_NAME}-chain.metadata.json" "${CONF_DIR}/ipi-conf-${CLOUD_NAME}-ref.metadata.json"
sed -i "s|chain|ref|g" "${CONF_DIR}/ipi-conf-${CLOUD_NAME}-ref.metadata.json"

cat > "${CONF_DIR}/ipi-conf-${CLOUD_NAME}-ref.yaml" << EOF
ref:
  as: ipi-conf-${CLOUD_NAME}
  from: installer
  commands: ipi-conf-${CLOUD_NAME}-commands.sh
  resources:
    requests:
      cpu: 10m
      memory: 100Mi
  credentials:
  - namespace: test-credentials
    name: ${CLOUD_NAME}-cluster-secrets
    mount_path: /var/run/${CLOUD_NAME}-cluster-secrets
  env:
  - name: SIZE_VARIANT
    default: ""
    documentation: |-
      The size of the cluster in one of our supported t-shirt values that is standard across all CI environments.
      The sizes are:
      * "" (default) - 4 vCPU, 16GB control plane nodes, default workers
      * "compact" - 8 vCPU, 32GB control plane nodes, no workers
      * "large" - 16 vCPU, 64GB+ control plane nodes, default workers, suitable for clusters up to 250 nodes
      * "xlarge" - 32 vCPU, 128GB+ control plane nodes, default workers, suitable for clusters up to 1000 nodes
      These sizes are roughly consistent across all cloud providers, but we may not be able to instantiate some sizes
      in some regions or accounts due to quota issues.
  - name: COMPUTE_NODE_TYPE
    default: 'Standard_D4_v3'
    documentation: |-
      The instance type to use for compute nodes
  documentation: |-
    The IPI ${CLOUD_NAME} configure step generates the ${CLOUD_NAME} specific install-config.yaml contents based on the cluster profile and optional input files.
EOF

# Creating the openshift e2e test workflows.
echo "Creating the openshift e2e test workflows for the platform."
OPENSHIFT_DIR="ci-operator/step-registry/openshift/e2e/${CLOUD_NAME}"
mkdir ${OPENSHIFT_DIR}
cp "${OWNERS_FILE_LOCATION}" "${OPENSHIFT_DIR}"
cp "${METADATA_FILE_LOCATION}" "${OPENSHIFT_DIR}/openshift-e2e-${CLOUD_NAME}-workflow.metadata.json"
sed -i "s|ipi/${CLOUD_NAME}/ipi-${CLOUD_NAME}|openshift/e2e/${CLOUD_NAME}/openshift-e2e-${CLOUD_NAME}|g" "${OPENSHIFT_DIR}/openshift-e2e-${CLOUD_NAME}-workflow.metadata.json"
cat > "${OPENSHIFT_DIR}/openshift-e2e-${CLOUD_NAME}-workflow.yaml" << EOF
workflow:
  as: openshift-e2e-${CLOUD_NAME}
  steps:
    pre:
    - chain: ipi-${CLOUD_NAME}-pre
    test:
    - ref: openshift-e2e-test
    post:
    - chain: gather-core-dump
    - chain: ipi-${CLOUD_NAME}-post
  documentation: |-
    The Openshift E2E ${CLOUD_NAME} workflow executes the common end-to-end test suite on ${CLOUD_NAME} with a default cluster configuration.
EOF

# Creating the openshift e2e upi test workflows.
echo "Creating the openshift e2e upi test workflows."
OPENSHIFT_UPI_DIR="ci-operator/step-registry/openshift/e2e/${CLOUD_NAME}/upi"
mkdir "${OPENSHIFT_UPI_DIR}"
cp "${OWNERS_FILE_LOCATION}" "${OPENSHIFT_UPI_DIR}"
cp "${METADATA_FILE_LOCATION}" "${OPENSHIFT_UPI_DIR}/openshift-e2e-${CLOUD_NAME}-upi-workflow.metadata.json"
sed -i "s|ipi/${CLOUD_NAME}/ipi-${CLOUD_NAME}|openshift/e2e/${CLOUD_NAME}/upi/openshift-e2e-${CLOUD_NAME}-upi|g" "${OPENSHIFT_UPI_DIR}/openshift-e2e-${CLOUD_NAME}-upi-workflow.metadata.json"
cat > "${OPENSHIFT_UPI_DIR}/openshift-e2e-${CLOUD_NAME}-upi-workflow.yaml" << EOF
workflow:
  as: openshift-e2e-${CLOUD_NAME}-upi
  steps:
    pre:
    - chain: upi-${CLOUD_NAME}-pre
    test:
    - ref: openshift-e2e-test
    post:
    - chain: gather-core-dump
    - chain: upi-${CLOUD_NAME}-post
  documentation: |-
    The Openshift E2E ${CLOUD_NAME} UPI workflow executes the common end-to-end test suite on ${CLOUD_NAME} with a default cluster configuration.
EOF

# Creating the UPI step files.
echo "Creating the UPI step files."
UPI_CLOUD_DIR="ci-operator/step-registry/upi/${CLOUD_NAME}"
mkdir "${UPI_CLOUD_DIR}"
cp "${OWNERS_FILE_LOCATION}" "${UPI_CLOUD_DIR}"
cp "${METADATA_FILE_LOCATION}" "${UPI_CLOUD_DIR}/upi-${CLOUD_NAME}-workflow.metadata.json"
sed -i "s|ipi|upi|g" "${UPI_CLOUD_DIR}/upi-${CLOUD_NAME}-workflow.metadata.json"

cat > "${UPI_CLOUD_DIR}/upi-${CLOUD_NAME}-workflow.yaml" << EOF
workflow:
  as: upi-${CLOUD_NAME}
  steps:
    pre:
    - chain: upi-${CLOUD_NAME}-pre
    post:
    - chain: upi-${CLOUD_NAME}-post
  documentation: |-
    The UPI workflow provides pre- and post- steps that provision and
    deprovision an OpenShift cluster with a default configuration on ${CLOUD_NAME} allowing job authors to inject their own end-to-end test logic.
    All modifications to this workflow should be done by modifying the
    `upi-${CLOUD_NAME}-{pre,post}` chains to allow other workflows to mimic and extend
    this base workflow without a need to backport changes.
EOF


# Creating UPI pre and post installation folders.
echo "Creating UPI pre and post installation folders."
mkdir "${UPI_CLOUD_DIR}/pre"
mkdir "${UPI_CLOUD_DIR}/post"
cp ${OWNERS_FILE_LOCATION} "${UPI_CLOUD_DIR}/pre"
cp ${OWNERS_FILE_LOCATION} "${UPI_CLOUD_DIR}/post"
cp "${IPI_CLOUD_DIR}/pre/ipi-${CLOUD_NAME}-pre-chain.metadata.json" "${UPI_CLOUD_DIR}/pre/upi-${CLOUD_NAME}-pre-chain.metadata.json"
cp "${IPI_CLOUD_DIR}/post/ipi-${CLOUD_NAME}-post-chain.metadata.json" "${UPI_CLOUD_DIR}/post/upi-${CLOUD_NAME}-post-chain.metadata.json"

sed -i "s|ipi|upi|g" "${UPI_CLOUD_DIR}/pre/upi-${CLOUD_NAME}-pre-chain.metadata.json"
sed -i "s|ipi|upi|g" "${UPI_CLOUD_DIR}/post/upi-${CLOUD_NAME}-post-chain.metadata.json"

cat > "${UPI_CLOUD_DIR}/pre/upi-${CLOUD_NAME}-pre-chain.yaml" << EOF
chain:
  as: upi-${CLOUD_NAME}-pre
  steps:
  - ref: ipi-install-rbac
  - chain: ipi-conf-${CLOUD_NAME}
  - ref: upi-install-${CLOUD_NAME}
  - ref: ipi-install-times-collection
  documentation: >-
    This chain contains all of the steps to provision an OpenShift cluster using the ${CLOUD_NAME} UPI workflow.
EOF

cat > "${UPI_CLOUD_DIR}/post/upi-${CLOUD_NAME}-post-chain.yaml" << EOF
chain:
  as: upi-${CLOUD_NAME}-post
  steps:
  - chain: ipi-deprovision
  - ref: upi-deprovision-${CLOUD_NAME}
  documentation: >-
    This chain deprovisions all the components created by the upi-${CLOUD_NAME}-pre chain.
EOF

# Creating UPI deprovision step.
echo "Creating UPI deprovision step."
UPI_DEPROVISION_DIR="ci-operator/step-registry/upi/deprovision/${CLOUD_NAME}"
mkdir "${UPI_DEPROVISION_DIR}"
cp ${OWNERS_FILE_LOCATION} "${UPI_DEPROVISION_DIR}"
cp "${METADATA_FILE_LOCATION}" "${UPI_DEPROVISION_DIR}/upi-deprovision-${CLOUD_NAME}-ref.metadata.json"
sed -i "s|ipi/${CLOUD_NAME}/ipi-${CLOUD_NAME}-workflow.yaml|upi/deprovision/${CLOUD_NAME}/upi-deprovision-${CLOUD_NAME}-ref.yaml|g" "${UPI_DEPROVISION_DIR}/upi-deprovision-${CLOUD_NAME}-ref.metadata.json"

cat > "${UPI_DEPROVISION_DIR}/upi-deprovision-${CLOUD_NAME}-commands.sh" << EOF
#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

trap 'CHILDREN=\$(jobs -p); if test -n "\${CHILDREN}"; then kill \${CHILDREN} && wait; fi' TERM

# TODO: Enter the logic to remove a UPI cluster.
EOF

cat > "${UPI_DEPROVISION_DIR}/upi-deprovision-${CLOUD_NAME}-ref.yaml" << EOF
ref:
  as: upi-deprovision-${CLOUD_NAME}
  from: upi-installer
  grace_period: 10m
  commands: upi-deprovision-${CLOUD_NAME}-commands.sh
  resources:
    requests:
      cpu: 10m
      memory: 100Mi
  documentation: >-
    This step deprovisions the ${CLOUD_NAME} deployments created by upi-install-${CLOUD_NAME}.
    It requires the ipi-deprovision step already be executed against the cluster.
EOF

# Creating the UPI install step.
echo "Creating the UPI install step."
UPI_INSTALL_DIR="ci-operator/step-registry/upi/install/${CLOUD_NAME}"
mkdir "${UPI_INSTALL_DIR}"
cp "${OWNERS_FILE_LOCATION}" "${UPI_INSTALL_DIR}"
cp "${METADATA_FILE_LOCATION}" "${UPI_INSTALL_DIR}/upi-install-${CLOUD_NAME}-ref.metadata.json"
sed -i "s|ipi/${CLOUD_NAME}/ipi-${CLOUD_NAME}-workflow.yaml|upi/install/${CLOUD_NAME}/upi-install-${CLOUD_NAME}-ref.yaml|g" "${UPI_DEPROVISION_DIR}/upi-deprovision-${CLOUD_NAME}-ref.metadata.json"

cat > "${UPI_INSTALL_DIR}/upi-install-${CLOUD_NAME}-ref.yaml" << EOF
ref:
  as: upi-install-${CLOUD_NAME}
  from: upi-installer
  grace_period: 10m
  commands: upi-install-${CLOUD_NAME}-commands.sh
  resources:
    requests:
      cpu: 10m
      memory: 100Mi
  documentation: >-
    This step deploys a UPI cluster to the CI ${CLOUD_NAME} project.
EOF

cat > "${UPI_INSTALL_DIR}/upi-install-${CLOUD_NAME}-commands.sh" << EOF
#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

trap 'CHILDREN=\$(jobs -p); if test -n "\${CHILDREN}"; then kill \${CHILDREN} && wait; fi' TERM
export HOME=/tmp

if [[ -z "\$RELEASE_IMAGE_LATEST" ]]; then
  echo "RELEASE_IMAGE_LATEST is an empty string, exiting"
  exit 1
fi

# Ensure ignition assets are configured with the correct invoker to track CI jobs.
export OPENSHIFT_INSTALL_INVOKER="openshift-internal-ci/\${JOB_NAME_SAFE}/\${BUILD_ID}"
export TEST_PROVIDER='azurestack'
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="\${RELEASE_IMAGE_LATEST}"

dir=/tmp/installer
mkdir "\${dir}"
pushd "\${dir}"
cp -t "\${dir}" \
    "\${SHARED_DIR}/install-config.yaml"

if ! pip -V; then
    echo "pip is not installed: installing"
    if python -c "import sys; assert(sys.version_info >= (3,0))"; then
      python -m ensurepip --user || easy_install --user 'pip'
    else
      echo "python < 3, installing pip<21"
      python -m ensurepip --user || easy_install --user 'pip<21'
    fi
fi

# TODO: Write logic for UPI install in ${CLOUD_NAME}
EOF

sudo make all

echo "Successfully created the step files for both UPI and IPI"
echo "Please fill in the following files for configuration, installation and destruction."
echo "- ${CONF_DIR}/ipi-conf-${CLOUD_NAME}-commands.sh"
echo "- ${CONF_DIR}/ipi-conf-${CLOUD_NAME}-ref.yaml"
echo "- ${UPI_DEPROVISION_DIR}/upi-deprovision-${CLOUD_NAME}-commands.sh"
echo "- ${UPI_INSTALL_DIR}/upi-install-${CLOUD_NAME}-commands.sh"

echo "You might want to look at the following files to check and see if you need any extra steps for the cloud platform during IPI installation."
echo "- ci-operator/step-registry/ipi/deprovision/deprovision/ipi-deprovision-deprovision-commands.sh : Check if any additional destruction logic is required here."
echo "- ci-operator/step-registry/ipi/install/install/ipi-install-install-commands.sh : Check for CLUSTER_TYPE case statement if you need any additional configuration setup."
echo "- ci-operator/step-registry/openshift/e2e/test/openshift-e2e-test-commands.sh : Add cloud platform to case CLUSTER_TYPE statement for tests to complete."
echo "You also might want to check other make steps like jobs, template-allowlist in case something is not generated."
echo "You need to checkout https://github.com/openshift/release/pull/20861/files for creating boskos releases and cluster profile secrets too."
echo "https://github.com/openshift/ci-tools/pull/2175 for creating the cloud platform cluster profile."
echo "Creation complete!"