#!/bin/bash
set -euo pipefail

trap 'CHILDREN=$(jobs -p); if test -n "${CHILDREN}"; then kill ${CHILDREN} && wait; fi' TERM

# The oc binary is placed in the shared-tmp by the test container and we want to use
# that oc for all actions.
export PATH=/tmp:${PATH}

function backoff() {
    local attempt=0
    local failed=0
    while true; do
        "$@" && failed=0 || failed=1
        if [[ $failed -eq 0 ]]; then
            break
        fi
        attempt=$(( attempt + 1 ))
        if [[ $attempt -gt 5 ]]; then
            break
        fi
        echo "command failed, retrying in $(( 2 ** $attempt )) seconds"
        sleep $(( 2 ** $attempt ))
    done
    return $failed
}

GATHER_BOOTSTRAP_ARGS=

function gather_bootstrap_and_fail() {
  if test -n "${GATHER_BOOTSTRAP_ARGS}"; then
    openshift-install --dir=${ARTIFACT_DIR}/installer gather bootstrap --key "${SSH_PRIVATE_KEY_PATH}" ${GATHER_BOOTSTRAP_ARGS}
  fi

  return 1
}
function generate_proxy_certs() {

  ROOTCA=/tmp/CA
  INTERMEDIATE=${ROOTCA}/INTERMEDIATE

  mkdir ${ROOTCA}
  pushd ${ROOTCA}
  mkdir certs crl newcerts private
  chmod 700 private
  touch index.txt
  echo 1000 > serial

  cat > ${ROOTCA}/openssl.cnf << EOF
[ ca ]
default_ca = CA_default
[ CA_default ]
# Directory and file locations.
dir               = ${ROOTCA}
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
RANDFILE          = \$dir/private/.rand
# The root key and root certificate.
private_key       = \$dir/private/ca.key.pem
certificate       = \$dir/certs/ca.cert.pem
# For certificate revocation lists.
crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/ca.crl.pem
crl_extensions    = crl_ext
copy_extensions   = copy
default_crl_days  = 30
# SHA-1 is deprecated, so use SHA-2 instead.
default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_loose
[ policy_strict ]
# The root CA should only sign intermediate certificates that match.
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional
[ policy_loose ]
# Allow the intermediate CA to sign a more diverse range of certificates.
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional
[ req ]
default_bits        = 2048
distinguished_name  = ca_dn
string_mask         = utf8only
# SHA-1 is deprecated, so use SHA-2 instead.
default_md          = sha256
# Extension to add when the -x509 option is used.
x509_extensions     = v3_ca
prompt              = no
[ ca_dn ]
0.domainComponent       = "io"
1.domainComponent       = "openshift"
organizationName        = "OpenShift Origin"
organizationalUnitName  = "Proxy CI Signing CA"
commonName              = "Proxy CI Signing CA"
[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
[ usr_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection
[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
[ crl_ext ]
authorityKeyIdentifier=keyid:always
[ ocsp ]
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
EOF

  # create root key
  uuidgen | sha256sum | cut -b -32 > capassfile

  openssl genrsa -aes256 -out private/ca.key.pem -passout file:capassfile 4096 2>/dev/null
  chmod 400 private/ca.key.pem

  # create root certificate

  openssl req -config openssl.cnf \
      -key private/ca.key.pem \
      -passin file:capassfile \
      -new -x509 -days 7300 -sha256 -extensions v3_ca \
      -out certs/ca.cert.pem 2>/dev/null

  chmod 444 certs/ca.cert.pem

  mkdir ${INTERMEDIATE}
  pushd ${INTERMEDIATE}

  mkdir certs crl csr newcerts private
  chmod 700 private
  touch index.txt
  echo 1000 > serial

  echo 1000 > ${INTERMEDIATE}/crlnumber

  cat > ${INTERMEDIATE}/openssl.cnf << EOF
[ ca ]
default_ca = CA_default
[ CA_default ]
# Directory and file locations.
dir               = ${INTERMEDIATE}
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
RANDFILE          = \$dir/private/.rand
# The root key and root certificate.
private_key       = \$dir/private/intermediate.key.pem
certificate       = \$dir/certs/intermediate.cert.pem
# For certificate revocation lists.
crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/intermediate.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30
# SHA-1 is deprecated, so use SHA-2 instead.
default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_loose
[ policy_strict ]
# The root CA should only sign intermediate certificates that match.
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional
[ policy_loose ]
# Allow the intermediate CA to sign a more diverse range of certificates.
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional
[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
prompt              = no
string_mask         = utf8only
# SHA-1 is deprecated, so use SHA-2 instead.
default_md          = sha256
# Extension to add when the -x509 option is used.
x509_extensions     = v3_ca
req_extensions      = req_ext
[ req_distinguished_name ]
0.domainComponent       = "io"
1.domainComponent       = "openshift"
organizationName        = "OpenShift Origin"
organizationalUnitName  = "CI Proxy"
commonName              = "CI Proxy"
[ req_ext ]
subjectAltName          = "DNS.1:*.compute-1.amazonaws.com"
[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
[ usr_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection
[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
[ crl_ext ]
authorityKeyIdentifier=keyid:always
[ ocsp ]
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
EOF

  popd
  uuidgen | sha256sum | cut -b -32 > intpassfile

  openssl genrsa -aes256 \
      -out ${INTERMEDIATE}/private/intermediate.key.pem \
      -passout file:intpassfile 4096 2>/dev/null

  chmod 400 ${INTERMEDIATE}/private/intermediate.key.pem

  openssl req -config ${INTERMEDIATE}/openssl.cnf -new -sha256 \
      -key ${INTERMEDIATE}/private/intermediate.key.pem \
      -passin file:intpassfile \
      -out ${INTERMEDIATE}/csr/intermediate.csr.pem 2>/dev/null

  openssl ca -config openssl.cnf -extensions v3_intermediate_ca \
      -days 3650 -notext -md sha256 \
      -batch \
      -in ${INTERMEDIATE}/csr/intermediate.csr.pem \
      -passin file:capassfile \
      -out ${INTERMEDIATE}/certs/intermediate.cert.pem 2>/dev/null

  chmod 444 ${INTERMEDIATE}/certs/intermediate.cert.pem

  openssl verify -CAfile certs/ca.cert.pem \
      ${INTERMEDIATE}/certs/intermediate.cert.pem

  cat ${INTERMEDIATE}/certs/intermediate.cert.pem \
      certs/ca.cert.pem > ${INTERMEDIATE}/certs/ca-chain.cert.pem

  chmod 444 ${INTERMEDIATE}/certs/ca-chain.cert.pem
  popd
}

function generate_proxy_ignition() {
  cat > /tmp/proxy.ign << EOF
{
  "ignition": {
    "config": {},
    "security": {
      "tls": {}
    },
    "timeouts": {},
    "version": "2.2.0"
  },
  "passwd": {
    "users": [
      {
        "name": "core",
        "sshAuthorizedKeys": [
          "${SSH_PUB_KEY}"
        ]
      }
    ]
  },
  "storage": {
    "files": [
      {
        "filesystem": "root",
        "path": "/tmp/squid/passwords",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${HTPASSWD_CONTENTS}"
        },
        "mode": 420
      },
      {
        "filesystem": "root",
        "path": "/tmp/squid/tls.crt",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${PROXY_CERT}"
        },
        "mode": 420
      },
      {
        "filesystem": "root",
        "path": "/tmp/squid/tls.key",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${PROXY_KEY}"
        },
        "mode": 420
      },
      {
        "filesystem": "root",
        "path": "/tmp/squid/ca-chain.pem",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${CA_CHAIN}"
        },
        "mode": 420
      },
      {
        "filesystem": "root",
        "path": "/tmp/squid/squid.conf",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${SQUID_CONFIG}"
        },
        "mode": 420
      },
      {
        "filesystem": "root",
        "path": "/tmp/squid.sh",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${SQUID_SH}"
        },
        "mode": 420
      },
      {
        "filesystem": "root",
        "path": "/tmp/squid/proxy.sh",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${PROXY_SH}"
        },
        "mode": 420
      },
      {
        "filesystem": "root",
        "path": "/tmp/squid/passwd.sh",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${KEY_PASSWORD}"
        },
        "mode": 493
      }
    ]
  },
  "systemd": {
    "units": [
      {
        "contents": "[Service]\n\nExecStart=bash /tmp/squid.sh\n\n[Install]\nWantedBy=multi-user.target\n",
        "enabled": true,
        "name": "squid.service"
      },
      {
        "dropins": [
          {
            "contents": "[Service]\nExecStart=\nExecStart=/usr/lib/systemd/systemd-journal-gatewayd \\\n  --key=/opt/openshift/tls/journal-gatewayd.key \\\n  --cert=/opt/openshift/tls/journal-gatewayd.crt \\\n  --trust=/opt/openshift/tls/root-ca.crt\n",
            "name": "certs.conf"
          }
        ],
        "name": "systemd-journal-gatewayd.service"
      },
      {
        "enabled": true,
        "name": "systemd-journal-gatewayd.socket"
      }
    ]
  }
}
EOF
}

function generate_proxy_template() {
  cat > /tmp/04_cluster_proxy.yaml << EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Template for OpenShift Cluster Proxy (EC2 Instance, Security Groups and IAM)

Parameters:
  InfrastructureName:
    AllowedPattern: ^([a-zA-Z][a-zA-Z0-9\-]{0,26})$
    MaxLength: 27
    MinLength: 1
    ConstraintDescription: Infrastructure name must be alphanumeric, start with a letter, and have a maximum of 27 characters.
    Description: A short, unique cluster ID used to tag cloud resources and identify items owned or used by the cluster.
    Type: String
  RhcosAmi:
    Description: Current Red Hat Enterprise Linux CoreOS AMI to use for proxy.
    Type: AWS::EC2::Image::Id
  AllowedProxyCidr:
    AllowedPattern: ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|1[0-9]|2[0-9]|3[0-2]))$
    ConstraintDescription: CIDR block parameter must be in the form x.x.x.x/0-32.
    Default: 0.0.0.0/0
    Description: CIDR block to allow access to the proxy node.
    Type: String
  PrivateHostedZoneId:
    Description: The Route53 private zone ID to register the etcd targets with, such as Z21IXYZABCZ2A4.
    Type: String
  PrivateHostedZoneName:
    Description: The Route53 zone to register the targets with, such as cluster.example.com. Omit the trailing period.
    Type: String
  ClusterName:
    Description: The cluster name used to uniquely identify the proxy load balancer
    Type: String
  PublicSubnet:
    Description: The public subnet to launch the proxy node into.
    Type: AWS::EC2::Subnet::Id
  MasterSecurityGroupId:
    Description: The master security group ID for registering temporary rules.
    Type: AWS::EC2::SecurityGroup::Id
  VpcId:
    Description: The VPC-scoped resources will belong to this VPC.
    Type: AWS::EC2::VPC::Id
  PrivateSubnets:
    Description: The internal subnets.
    Type: List<AWS::EC2::Subnet::Id>
  ProxyIgnitionLocation:
    Default: s3://my-s3-bucket/proxy.ign
    Description: Ignition config file location.
    Type: String
  AutoRegisterDNS:
    Default: "yes"
    AllowedValues:
    - "yes"
    - "no"
    Description: Do you want to invoke DNS etcd registration, which requires Hosted Zone information?
    Type: String
  AutoRegisterELB:
    Default: "yes"
    AllowedValues:
    - "yes"
    - "no"
    Description: Do you want to invoke NLB registration, which requires a Lambda ARN parameter?
    Type: String
  RegisterNlbIpTargetsLambdaArn:
    Description: ARN for NLB IP target registration lambda.
    Type: String
  ExternalApiTargetGroupArn:
    Description: ARN for external API load balancer target group.
    Type: String
  InternalApiTargetGroupArn:
    Description: ARN for internal API load balancer target group.
    Type: String
  InternalServiceTargetGroupArn:
    Description: ARN for internal service load balancer target group.
    Type: String

Metadata:
  AWS::CloudFormation::Interface:
    ParameterGroups:
    - Label:
        default: "Cluster Information"
      Parameters:
      - InfrastructureName
    - Label:
        default: "Host Information"
      Parameters:
      - RhcosAmi
      - ProxyIgnitionLocation
      - MasterSecurityGroupId
    - Label:
        default: "Network Configuration"
      Parameters:
      - VpcId
      - AllowedProxyCidr
      - PublicSubnet
      - PrivateSubnets
      - ClusterName
    - Label:
        default: "DNS"
      Parameters:
      - AutoRegisterDNS
      - PrivateHostedZoneId
      - PrivateHostedZoneName
    - Label:
        default: "Load Balancer Automation"
      Parameters:
      - AutoRegisterELB
      - RegisterNlbIpTargetsLambdaArn
      - ExternalApiTargetGroupArn
      - InternalApiTargetGroupArn
      - InternalServiceTargetGroupArn
    ParameterLabels:
      InfrastructureName:
        default: "Infrastructure Name"
      VpcId:
        default: "VPC ID"
      AllowedProxyCidr:
        default: "Allowed ingress Source"
      PublicSubnet:
        default: "Public Subnet"
      PrivateSubnets:
        default: "Private Subnets"
      RhcosAmi:
        default: "Red Hat Enterprise Linux CoreOS AMI ID"
      ProxyIgnitionLocation:
        default: "Bootstrap Ignition Source"
      MasterSecurityGroupId:
        default: "Master Security Group ID"
      AutoRegisterDNS:
        default: "Use Provided DNS Automation"
      AutoRegisterELB:
        default: "Use Provided ELB Automation"
      PrivateHostedZoneName:
        default: "Private Hosted Zone Name"
      PrivateHostedZoneId:
        default: "Private Hosted Zone ID"
      ClusterName:
        default: "Cluster name"

Conditions:
  DoRegistration: !Equals ["yes", !Ref AutoRegisterELB]
  DoDns: !Equals ["yes", !Ref AutoRegisterDNS]

Resources:
  ProxyIamRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
        - Effect: "Allow"
          Principal:
            Service:
            - "ec2.amazonaws.com"
          Action:
          - "sts:AssumeRole"
      Path: "/"
      Policies:
      - PolicyName: !Join ["-", [!Ref InfrastructureName, "proxy", "policy"]]
        PolicyDocument:
          Version: "2012-10-17"
          Statement:
          - Effect: "Allow"
            Action: "ec2:Describe*"
            Resource: "*"

  ProxyInstanceProfile:
    Type: "AWS::IAM::InstanceProfile"
    Properties:
      Path: "/"
      Roles:
      - Ref: "ProxyIamRole"

  ProxySecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Cluster Proxy Security Group
      SecurityGroupIngress:
      - IpProtocol: tcp
        FromPort: 22
        ToPort: 22
        CidrIp: 0.0.0.0/0
      - IpProtocol: tcp
        ToPort: 3128
        FromPort: 3128
        CidrIp: !Ref AllowedProxyCidr
      - IpProtocol: tcp
        ToPort: 3130
        FromPort: 3130
        CidrIp: !Ref AllowedProxyCidr
      - IpProtocol: tcp
        ToPort: 19531
        FromPort: 19531
        CidrIp: !Ref AllowedProxyCidr
      VpcId: !Ref VpcId

  ProxyInstance:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: !Ref RhcosAmi
      IamInstanceProfile: !Ref ProxyInstanceProfile
      InstanceType: "i3.large"
      NetworkInterfaces:
      - AssociatePublicIpAddress: "true"
        DeviceIndex: "0"
        GroupSet:
        - !Ref "ProxySecurityGroup"
        - !Ref "MasterSecurityGroupId"
        SubnetId: !Ref "PublicSubnet"
      UserData:
        Fn::Base64: !Sub
        - '{"ignition":{"config":{"replace":{"source":"\${IgnitionLocation}","verification":{}}},"timeouts":{},"version":"2.1.0"},"networkd":{},"passwd":{},"storage":{},"systemd":{}}'
        - {
          IgnitionLocation: !Ref ProxyIgnitionLocation
        }

  ProxyRecord:
    Condition: DoDns
    Type: AWS::Route53::RecordSet
    Properties:
      HostedZoneId: !Ref PrivateHostedZoneId
      Name: !Join [".", ["squid", !Ref PrivateHostedZoneName]]
      ResourceRecords:
      - !GetAtt ProxyInstance.PublicIp
      TTL: 60
      Type: A

Outputs:
  ProxyPublicIp:
    Description: The proxy node public IP address.
    Value: !GetAtt ProxyInstance.PublicIp
EOF
}

# ensure LEASED_RESOURCE is set
if [[ -z "${LEASED_RESOURCE}" ]]; then
  echo "Failed to acquire lease"
  exit 1
fi

cp "$(command -v openshift-install)" /tmp
mkdir ${ARTIFACT_DIR}/installer

echo "Installing from initial release ${RELEASE_IMAGE_LATEST}"
OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${RELEASE_IMAGE_LATEST}"
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE

SSH_PRIVATE_KEY_PATH=${CLUSTER_PROFILE_DIR}/ssh-privatekey
PULL_SECRET_PATH=${CLUSTER_PROFILE_DIR}/pull-secret
OPENSHIFT_INSTALL_INVOKER=openshift-internal-ci/${JOB_NAME}/${BUILD_ID}
AWS_SHARED_CREDENTIALS_FILE=${CLUSTER_PROFILE_DIR}/.awscred

export PULL_SECRET_PATH
export OPENSHIFT_INSTALL_INVOKER
export AWS_SHARED_CREDENTIALS_FILE

EXPIRATION_DATE=$(date -d '4 hours' --iso=minutes --utc)
SSH_PUB_KEY=${CLUSTER_PROFILE_DIR}/ssh-publickey
PULL_SECRET=${CLUSTER_PROFILE_DIR}/pull-secret
export EXPIRATION_DATE
export SSH_PUB_KEY
export PULL_SECRET

cp ${SHARED_DIR}/install-config.yaml ${ARTIFACT_DIR}/installer/install-config.yaml
pushd ${ARTIFACT_DIR}/installer

base_domain=$(python3 -c 'import yaml;data = yaml.full_load(open("install-config.yaml"));print(data["baseDomain"])')
AWS_REGION=$(python3 -c 'import yaml;data = yaml.full_load(open("install-config.yaml"));print(data["platform"]["aws"]["region"])')
CLUSTER_NAME=$(python3 -c 'import yaml;data = yaml.full_load(open("install-config.yaml"));print(data["metadata"]["name"])')
MACHINE_CIDR=10.0.0.0/16
# Add proxy info to install-config.yaml
# create and sign a cert
generate_proxy_certs
ROOTCA=/tmp/CA
INTERMEDIATE=${ROOTCA}/INTERMEDIATE

# load in certs here
PROXY_CERT="$(base64 -w0 ${INTERMEDIATE}/certs/intermediate.cert.pem)"
PROXY_KEY="$(base64 -w0 ${INTERMEDIATE}/private/intermediate.key.pem)"
PROXY_KEY_PASSWORD="$(cat ${ROOTCA}/intpassfile)"

CA_CHAIN="$(base64 -w0 ${INTERMEDIATE}/certs/ca-chain.cert.pem)"

# create random uname and pw
USER_NAME="${CLUSTER_NAME}"
PASSWORD="$(uuidgen | sha256sum | cut -b -32)"

HTPASSWD_CONTENTS="${USER_NAME}:$(openssl passwd -apr1 ${PASSWORD})"
HTPASSWD_CONTENTS="$(echo -e ${HTPASSWD_CONTENTS} | base64 -w0)"

KEY_PASSWORD="$(base64 -w0 << EOF
#!/bin/sh
echo ${PROXY_KEY_PASSWORD}
EOF
)"

PROXY_DNS="squid.${CLUSTER_NAME}.${base_domain}"

export PROXY_URL="http://${USER_NAME}:${PASSWORD}@${PROXY_DNS}:3128/"
export TLS_PROXY_URL="https://${USER_NAME}:${PASSWORD}@${PROXY_DNS}:3130/"

# TODO:
# restore using "httpsProxy: ${TLS_PROXY_URL}"
# once we have a squid image with at least version 4.x so that we can do a TLS 1.3 handshake.
# Currently 3.5 only does up to 1.2 which podman fails to do a handshake with  https://github.com/containers/image/issues/699

cat >> ${ARTIFACT_DIR}/installer/install-config.yaml << EOF
proxy:
  httpsProxy: ${PROXY_URL}
  httpProxy: ${PROXY_URL}
additionalTrustBundle: |
$(cat ${INTERMEDIATE}/certs/ca-chain.cert.pem | awk '{print "  "$0}')
EOF
date "+%F %X" > "${SHARED_DIR}/CLUSTER_INSTALL_START_TIME"
openshift-install --dir=${ARTIFACT_DIR}/installer create manifests
sed -i '/^  channel:/d' ${ARTIFACT_DIR}/installer/manifests/cvo-overrides.yaml
rm -f ${ARTIFACT_DIR}/installer/openshift/99_openshift-cluster-api_master-machines-*.yaml
rm -f ${ARTIFACT_DIR}/installer/openshift/99_openshift-cluster-api_worker-machineset-*.yaml
sed -i "s;mastersSchedulable: true;mastersSchedulable: false;g" ${ARTIFACT_DIR}/installer/manifests/cluster-scheduler-02-config.yml

echo "Creating ignition configs"
openshift-install --dir=${ARTIFACT_DIR}/installer create ignition-configs &
wait "$!"

cp ${ARTIFACT_DIR}/installer/bootstrap.ign ${SHARED_DIR}
BOOTSTRAP_URI="https://${JOB_NAME_SAFE}-bootstrap-exporter-${NAMESPACE}.svc.ci.openshift.org/bootstrap.ign"
export BOOTSTRAP_URI
START_TIME=$(date "+%F %X")

# begin bootstrapping
if openshift-install coreos print-stream-json 2>/tmp/err.txt >coreos.json; then
  RHCOS_AMI="$(jq -r .architectures.x86_64.images.aws.regions[\"${AWS_REGION}\"].image coreos.json)"
else
  RHCOS_AMI="$(jq -r .amis[\"${AWS_REGION}\"].hvm /var/lib/openshift-install/rhcos.json)"
fi

export AWS_DEFAULT_REGION="${AWS_REGION}"  # CLI prefers the former

INFRA_ID="$(jq -r .infraID ${ARTIFACT_DIR}/installer/metadata.json)"
TAGS="Key=expirationDate,Value=${EXPIRATION_DATE}"
IGNITION_CA="$(jq '.ignition.security.tls.certificateAuthorities[0].source' ${ARTIFACT_DIR}/installer/master.ign)"  # explicitly keeping wrapping quotes

HOSTED_ZONE="$(aws route53 list-hosted-zones-by-name \
  --dns-name "${base_domain}" \
  --query "HostedZones[? Config.PrivateZone != \`true\` && Name == \`${base_domain}.\`].Id" \
  --output text)"

# Create s3 bucket for bootstrap and proxy ignition configs
aws s3 mb s3://"${CLUSTER_NAME}-infra"

# If we are using a proxy, create a 'black-hole' private subnet vpc TODO
# For now this is just a placeholder...
aws cloudformation create-stack  --stack-name "${CLUSTER_NAME}-vpc" \
  --template-body "$(cat "/var/lib/openshift-install/upi/${CLUSTER_TYPE}/cloudformation/01_vpc.yaml")" \
  --tags "${TAGS}" \
  --parameters \
    ParameterKey=AvailabilityZoneCount,ParameterValue=3 &
wait "$!"

aws cloudformation wait stack-create-complete --stack-name "${CLUSTER_NAME}-vpc" &
wait "$!"

VPC_JSON="$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-vpc" \
  --query 'Stacks[].Outputs[]' --output json)"
VPC_ID="$(echo "${VPC_JSON}" | jq -r '.[] | select(.OutputKey == "VpcId").OutputValue')"
PRIVATE_SUBNETS="$(echo "${VPC_JSON}" | jq '.[] | select(.OutputKey == "PrivateSubnetIds").OutputValue')"  # explicitly keeping wrapping quotes
PRIVATE_SUBNET_0="$(echo "${PRIVATE_SUBNETS}" | sed 's/"//g' | cut -d, -f1)"
PRIVATE_SUBNET_1="$(echo "${PRIVATE_SUBNETS}" | sed 's/"//g' | cut -d, -f2)"
PRIVATE_SUBNET_2="$(echo "${PRIVATE_SUBNETS}" | sed 's/"//g' | cut -d, -f3)"
PUBLIC_SUBNETS="$(echo "${VPC_JSON}" | jq '.[] | select(.OutputKey == "PublicSubnetIds").OutputValue')"  # explicitly keeping wrapping quotes

aws cloudformation create-stack \
  --stack-name "${CLUSTER_NAME}-infra" \
  --template-body "$(cat "/var/lib/openshift-install/upi/${CLUSTER_TYPE}/cloudformation/02_cluster_infra.yaml")" \
  --tags "${TAGS}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=ClusterName,ParameterValue="${CLUSTER_NAME}" \
    ParameterKey=InfrastructureName,ParameterValue="${INFRA_ID}" \
    ParameterKey=HostedZoneId,ParameterValue="${HOSTED_ZONE}" \
    ParameterKey=HostedZoneName,ParameterValue="${base_domain}" \
    ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
    ParameterKey=PrivateSubnets,ParameterValue="${PRIVATE_SUBNETS}" \
    ParameterKey=PublicSubnets,ParameterValue="${PUBLIC_SUBNETS}" &
wait "$!"

aws cloudformation wait stack-create-complete --stack-name "${CLUSTER_NAME}-infra" &
wait "$!"

INFRA_JSON="$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-infra" \
  --query 'Stacks[].Outputs[]' --output json)"
NLB_IP_TARGETS_LAMBDA="$(echo "${INFRA_JSON}" | jq -r '.[] | select(.OutputKey == "RegisterNlbIpTargetsLambda").OutputValue')"
EXTERNAL_API_TARGET_GROUP="$(echo "${INFRA_JSON}" | jq -r '.[] | select(.OutputKey == "ExternalApiTargetGroupArn").OutputValue')"
INTERNAL_API_TARGET_GROUP="$(echo "${INFRA_JSON}" | jq -r '.[] | select(.OutputKey == "InternalApiTargetGroupArn").OutputValue')"
INTERNAL_SERVICE_TARGET_GROUP="$(echo "${INFRA_JSON}" | jq -r '.[] | select(.OutputKey == "InternalServiceTargetGroupArn").OutputValue')"
PRIVATE_HOSTED_ZONE="$(echo "${INFRA_JSON}" | jq -r '.[] | select(.OutputKey == "PrivateHostedZoneId").OutputValue')"

aws cloudformation create-stack \
  --stack-name "${CLUSTER_NAME}-security" \
  --template-body "$(cat "/var/lib/openshift-install/upi/${CLUSTER_TYPE}/cloudformation/03_cluster_security.yaml")" \
  --tags "${TAGS}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=InfrastructureName,ParameterValue="${INFRA_ID}" \
    ParameterKey=VpcCidr,ParameterValue="${MACHINE_CIDR}" \
    ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
    ParameterKey=PrivateSubnets,ParameterValue="${PRIVATE_SUBNETS}" &
wait "$!"

aws cloudformation wait stack-create-complete --stack-name "${CLUSTER_NAME}-security" &
wait "$!"

SECURITY_JSON="$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-security" \
  --query 'Stacks[].Outputs[]' --output json)"
MASTER_SECURITY_GROUP="$(echo "${SECURITY_JSON}" | jq -r '.[] | select(.OutputKey == "MasterSecurityGroupId").OutputValue')"
MASTER_INSTANCE_PROFILE="$(echo "${SECURITY_JSON}" | jq -r '.[] | select(.OutputKey == "MasterInstanceProfile").OutputValue')"
WORKER_SECURITY_GROUP="$(echo "${SECURITY_JSON}" | jq -r '.[] | select(.OutputKey == "WorkerSecurityGroupId").OutputValue')"
WORKER_INSTANCE_PROFILE="$(echo "${SECURITY_JSON}" | jq -r '.[] | select(.OutputKey == "WorkerInstanceProfile").OutputValue')"

echo "creating proxy..."

# define squid config
SQUID_CONFIG="$(base64 -w0 << EOF
http_port 3128
sslpassword_program /squid/passwd.sh
https_port 3130 cert=/squid/tls.crt key=/squid/tls.key cafile=/squid/ca-chain.pem
cache deny all
access_log stdio:/tmp/squid-access.log all
debug_options ALL,1
shutdown_lifetime 0
auth_param basic program /usr/lib64/squid/basic_ncsa_auth /squid/passwords
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
pid_filename /tmp/proxy-setup
EOF
)"

PROXY_IMAGE=registry.ci.openshift.org/origin/4.5:egress-http-proxy

# define squid.sh
SQUID_SH="$(base64 -w0 << EOF
#!/bin/bash
podman run --entrypoint='["bash", "/squid/proxy.sh"]' --expose=3128 --net host --volume /tmp/squid:/squid:Z ${PROXY_IMAGE}
EOF
)"

# define proxy.sh
PROXY_SH="$(base64 -w0 << EOF
#!/bin/bash
function print_logs() {
while [[ ! -f /tmp/squid-access.log ]]; do
sleep 5
done
tail -f /tmp/squid-access.log
}
print_logs &
squid -N -f /squid/squid.conf
EOF
)"

# create ignition entries for certs and script to start squid and systemd unit entry
# create the proxy stack and then get its IP
generate_proxy_ignition
generate_proxy_template

# host proxy ignition on s3
S3_PROXY_URI="s3://${CLUSTER_NAME}-infra/proxy.ign"
aws s3 cp /tmp/proxy.ign "$S3_PROXY_URI"

PROXY_URI="https://${JOB_NAME_SAFE}-bootstrap-exporter-${NAMESPACE}.svc.ci.openshift.org/proxy.ign"
export PROXY_URI

aws cloudformation create-stack \
  --stack-name "${CLUSTER_NAME}-proxy" \
  --template-body "$(cat "/tmp/04_cluster_proxy.yaml")" \
  --tags "${TAGS}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=InfrastructureName,ParameterValue="${INFRA_ID}" \
    ParameterKey=RhcosAmi,ParameterValue="${RHCOS_AMI}" \
    ParameterKey=PrivateHostedZoneId,ParameterValue="${PRIVATE_HOSTED_ZONE}" \
    ParameterKey=PrivateHostedZoneName,ParameterValue="${CLUSTER_NAME}.${base_domain}" \
    ParameterKey=ClusterName,ParameterValue="${CLUSTER_NAME}" \
    ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
    ParameterKey=PublicSubnet,ParameterValue="${PUBLIC_SUBNETS%%,*}\"" \
    ParameterKey=MasterSecurityGroupId,ParameterValue="${MASTER_SECURITY_GROUP}" \
    ParameterKey=ProxyIgnitionLocation,ParameterValue="${S3_PROXY_URI}" \
    ParameterKey=PrivateSubnets,ParameterValue="${PRIVATE_SUBNETS}" \
    ParameterKey=RegisterNlbIpTargetsLambdaArn,ParameterValue="${NLB_IP_TARGETS_LAMBDA}" \
    ParameterKey=ExternalApiTargetGroupArn,ParameterValue="${EXTERNAL_API_TARGET_GROUP}" \
    ParameterKey=InternalApiTargetGroupArn,ParameterValue="${INTERNAL_API_TARGET_GROUP}" \
    ParameterKey=InternalServiceTargetGroupArn,ParameterValue="${INTERNAL_SERVICE_TARGET_GROUP}" &
wait "$!"

aws cloudformation wait stack-create-complete --stack-name "${CLUSTER_NAME}-proxy" &
wait "$!"

PROXY_IP="$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-proxy" \
  --query 'Stacks[].Outputs[?OutputKey == `ProxyPublicIp`].OutputValue' --output text)"

echo "Proxy is available at ${PROXY_URL}"
echo "TLS Proxy is available at ${TLS_PROXY_URL}"

echo ${PROXY_IP} > ${ARTIFACT_DIR}/installer/proxyip


S3_BOOTSTRAP_URI="s3://${CLUSTER_NAME}-infra/bootstrap.ign"
aws s3 cp ${ARTIFACT_DIR}/installer/bootstrap.ign "$S3_BOOTSTRAP_URI"

aws cloudformation create-stack \
  --stack-name "${CLUSTER_NAME}-bootstrap" \
  --template-body "$(cat "/var/lib/openshift-install/upi/${CLUSTER_TYPE}/cloudformation/04_cluster_bootstrap.yaml")" \
  --tags "${TAGS}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=InfrastructureName,ParameterValue="${INFRA_ID}" \
    ParameterKey=RhcosAmi,ParameterValue="${RHCOS_AMI}" \
    ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
    ParameterKey=PublicSubnet,ParameterValue="${PUBLIC_SUBNETS%%,*}\"" \
    ParameterKey=MasterSecurityGroupId,ParameterValue="${MASTER_SECURITY_GROUP}" \
    ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
    ParameterKey=BootstrapIgnitionLocation,ParameterValue="${S3_BOOTSTRAP_URI}" \
    ParameterKey=RegisterNlbIpTargetsLambdaArn,ParameterValue="${NLB_IP_TARGETS_LAMBDA}" \
    ParameterKey=ExternalApiTargetGroupArn,ParameterValue="${EXTERNAL_API_TARGET_GROUP}" \
    ParameterKey=InternalApiTargetGroupArn,ParameterValue="${INTERNAL_API_TARGET_GROUP}" \
    ParameterKey=InternalServiceTargetGroupArn,ParameterValue="${INTERNAL_SERVICE_TARGET_GROUP}" &
wait "$!"

aws cloudformation wait stack-create-complete --stack-name "${CLUSTER_NAME}-bootstrap" &
wait "$!"

BOOTSTRAP_IP="$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-bootstrap" \
  --query 'Stacks[].Outputs[?OutputKey == `BootstrapPublicIp`].OutputValue' --output text)"
GATHER_BOOTSTRAP_ARGS="${GATHER_BOOTSTRAP_ARGS} --bootstrap ${BOOTSTRAP_IP}"

aws cloudformation create-stack \
  --stack-name "${CLUSTER_NAME}-control-plane" \
  --template-body "$(cat "/var/lib/openshift-install/upi/${CLUSTER_TYPE}/cloudformation/05_cluster_master_nodes.yaml")" \
  --tags "${TAGS}" \
  --parameters \
    ParameterKey=InfrastructureName,ParameterValue="${INFRA_ID}" \
    ParameterKey=RhcosAmi,ParameterValue="${RHCOS_AMI}" \
    ParameterKey=PrivateHostedZoneId,ParameterValue="${PRIVATE_HOSTED_ZONE}" \
    ParameterKey=PrivateHostedZoneName,ParameterValue="${CLUSTER_NAME}.${base_domain}" \
    ParameterKey=Master0Subnet,ParameterValue="${PRIVATE_SUBNET_0}" \
    ParameterKey=Master1Subnet,ParameterValue="${PRIVATE_SUBNET_1}" \
    ParameterKey=Master2Subnet,ParameterValue="${PRIVATE_SUBNET_2}" \
    ParameterKey=MasterSecurityGroupId,ParameterValue="${MASTER_SECURITY_GROUP}" \
    ParameterKey=IgnitionLocation,ParameterValue="https://api-int.${CLUSTER_NAME}.${base_domain}:22623/config/master" \
    ParameterKey=CertificateAuthorities,ParameterValue="${IGNITION_CA}" \
    ParameterKey=MasterInstanceProfileName,ParameterValue="${MASTER_INSTANCE_PROFILE}" \
    ParameterKey=RegisterNlbIpTargetsLambdaArn,ParameterValue="${NLB_IP_TARGETS_LAMBDA}" \
    ParameterKey=ExternalApiTargetGroupArn,ParameterValue="${EXTERNAL_API_TARGET_GROUP}" \
    ParameterKey=InternalApiTargetGroupArn,ParameterValue="${INTERNAL_API_TARGET_GROUP}" \
    ParameterKey=InternalServiceTargetGroupArn,ParameterValue="${INTERNAL_SERVICE_TARGET_GROUP}" &
wait "$!"

aws cloudformation wait stack-create-complete --stack-name "${CLUSTER_NAME}-control-plane" &
wait "$!"

aws cloudformation wait stack-create-complete --stack-name "${CLUSTER_NAME}-control-plane"
CONTROL_PLANE_IPS="$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-control-plane" --query 'Stacks[].Outputs[?OutputKey == `PrivateIPs`].OutputValue' --output text)"
CONTROL_PLANE_0_IP="$(echo "${CONTROL_PLANE_IPS}" | cut -d, -f1)"
CONTROL_PLANE_1_IP="$(echo "${CONTROL_PLANE_IPS}" | cut -d, -f2)"
CONTROL_PLANE_2_IP="$(echo "${CONTROL_PLANE_IPS}" | cut -d, -f3)"
GATHER_BOOTSTRAP_ARGS="${GATHER_BOOTSTRAP_ARGS} --master ${CONTROL_PLANE_0_IP} --master ${CONTROL_PLANE_1_IP} --master ${CONTROL_PLANE_2_IP}"

for INDEX in 0 1 2
do
  SUBNET="PRIVATE_SUBNET_${INDEX}"
  aws cloudformation create-stack \
    --stack-name "${CLUSTER_NAME}-compute-${INDEX}" \
    --template-body "$(cat "/var/lib/openshift-install/upi/${CLUSTER_TYPE}/cloudformation/06_cluster_worker_node.yaml")" \
    --tags "${TAGS}" \
    --parameters \
      ParameterKey=InfrastructureName,ParameterValue="${INFRA_ID}" \
      ParameterKey=RhcosAmi,ParameterValue="${RHCOS_AMI}" \
      ParameterKey=Subnet,ParameterValue="${!SUBNET}" \
      ParameterKey=WorkerSecurityGroupId,ParameterValue="${WORKER_SECURITY_GROUP}" \
      ParameterKey=IgnitionLocation,ParameterValue="https://api-int.${CLUSTER_NAME}.${base_domain}:22623/config/worker" \
      ParameterKey=CertificateAuthorities,ParameterValue="${IGNITION_CA}" \
      ParameterKey=WorkerInstanceType,ParameterValue=m4.xlarge \
      ParameterKey=WorkerInstanceProfileName,ParameterValue="${WORKER_INSTANCE_PROFILE}" &
  wait "$!"

  aws cloudformation wait stack-create-complete --stack-name "${CLUSTER_NAME}-compute-${INDEX}" &
  wait "$!"

  COMPUTE_VAR="COMPUTE_${INDEX}_IP"
  COMPUTE_IP="$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-compute-${INDEX}" --query 'Stacks[].Outputs[?OutputKey == `PrivateIP`].OutputValue' --output text)"
  export COMPUTE_IP
  eval "${COMPUTE_VAR}=\${COMPUTE_IP}"
done

# shellcheck disable=SC2153
echo "bootstrap: ${BOOTSTRAP_IP} control-plane: ${CONTROL_PLANE_0_IP} ${CONTROL_PLANE_1_IP} ${CONTROL_PLANE_2_IP} compute: ${COMPUTE_0_IP} ${COMPUTE_1_IP}"

echo "Waiting for bootstrap to complete"
openshift-install --dir=${ARTIFACT_DIR}/installer wait-for bootstrap-complete &
wait "$!" || gather_bootstrap_and_fail

echo "Bootstrap complete, destroying bootstrap resources"
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-bootstrap" &
wait "$!"

aws cloudformation wait stack-delete-complete --stack-name "${CLUSTER_NAME}-bootstrap" &
wait "$!"

function approve_csrs() {
  oc version --client
  while true; do
    if [[ ! -f /tmp/install-complete ]]; then
      # even if oc get csr fails continue
      oc get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs --no-run-if-empty oc adm certificate approve || true
      sleep 15 & wait
      continue
    else
      break
    fi
  done
}

function update_image_registry() {
  while true; do
    sleep 10;
    oc get configs.imageregistry.operator.openshift.io/cluster > /dev/null && break
  done
  oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed","storage":{"emptyDir":{}}}}'
}

echo "Approving pending CSRs"
export KUBECONFIG=${ARTIFACT_DIR}/installer/auth/kubeconfig
approve_csrs &

set +x
echo "Completing UPI setup"
openshift-install --dir=${ARTIFACT_DIR}/installer wait-for install-complete 2>&1 | grep --line-buffered -v password &
wait "$!"

END_TIME=$(date "+%F %X")

echo "Updating openshift-install ConfigMap with the start and end times."
if ! oc patch configmap openshift-install -n openshift-config -p '{"data":{"startTime":"'"$START_TIME"'","endTime":"'"$END_TIME"'"}}'
then
  oc create configmap openshift-install -n openshift-config --from-literal=startTime="$START_TIME" --from-literal=endTime="$END_TIME"
fi

date "+%F %X" > "${SHARED_DIR}/CLUSTER_INSTALL_END_TIME"

# Password for the cluster gets leaked in the installer logs and hence removing them.
sed -i 's/password: .*/password: REDACTED"/g' ${ARTIFACT_DIR}/installer/.openshift_install.log
# The image registry in some instances the config object
# is not properly configured. Rerun patching
# after cluster complete
cp -t "${SHARED_DIR}" \
    "${ARTIFACT_DIR}/installer/auth/kubeconfig"
touch /tmp/install-complete