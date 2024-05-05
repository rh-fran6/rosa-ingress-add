#!/bin/bash

set -eo pipefail

export CERTMGR_NAMESPACE="cert-manager"
export CERTMGR_SA="cert-manager"
export TRUST_POLICY_FILE="TrustPolicy.json"
export POLICY_FILE="s3Policy.json"
export SCRATCH_DIR="./"
export CERT_NAME="sandbox2791-cert"
export SCOPE="External"
export CLUSTERISSUER_NAME="demo-clusterissuer"
export INGRESS_NAME=sandbox-ingresscontroller


# Function to prompt user for input with a message
prompt_user() {
    read -rp "$1: " "$2"
}

# Function to extract AWS account ID
get_account_id() {
    aws sts get-caller-identity --query Account --output text
}

# Function to extract AWS region
get_aws_region() {
    aws configure get region
}

# Function to extract OIDC Provider endpoint
get_oidc_provider_endpoint() {
    rosa describe cluster -c "$(oc get clusterversion -o jsonpath='{.items[].spec.clusterID}{"\n"}')" -o yaml | awk '/oidc_endpoint_url/ {print $2}' | cut -d '/' -f 3,4
}

# Function to create IAM role
create_iam_role() {
    local a="$1"
    aws iam create-role --role-name "${1}-demo-certmgr-r53-role" --assume-role-policy-document file://$TRUST_POLICY_FILE --query "Role.Arn" --output text
}

# Function to create IAM policy
create_iam_policy() {
    local a=$1
    aws iam create-policy --policy-name "${1}-demo-certmgr-r53-policy" --policy-document file://$POLICY_FILE --query 'Policy.Arn' --output text
}

# Function to attach IAM policy to role
attach_policy_to_role() {
    aws iam attach-role-policy --role-name "${1}" --policy-arn "$2"
}
# Function to Get Zone ID
get_hosted_zone_id() {
    aws route53 list-hosted-zones-by-name --dns-name "${1}" | jq -r '.HostedZones[].Id' | cut -d'/' -f3
}

# Read Cluster Name
prompt_user "Please enter Cluster Name: " CLUSTER_NAME

# Read Zone ID from Zone Name
prompt_user "Please enter Route53 DNS Name: " DOMAIN

# Get the Hosted Zone ID
HOSTEDZONEID=$(get_hosted_zone_id "$DOMAIN")
echo Hosted Zone ID: $HOSTEDZONEID

# Display variables
ROLE_NAME=$CLUSTER_NAME-demo-certmgr-r53-role

POLICY_NAME=$CLUSTER_NAME-demo-certmgr-r53-policy


echo ROLE NAME: $CLUSTER_NAME-demo-certmgr-r53-role

echo POLICY NAME: $CLUSTER_NAME-demo-certmgr-r53-policy

# Extract Account ID
AWS_ACCOUNT_ID=$(get_account_id)
# Extract AWSRegion
AWS_REGION=$(get_aws_region)

# Extract OIDC Provider endpoint
OIDC_PROVIDER_ENDPOINT=$(get_oidc_provider_endpoint)
echo "OIDC Provider Endpoint: $OIDC_PROVIDER_ENDPOINT"

# Create IAM policy
echo "Creating policy file $POLICY_FILE in local directory..."
cat <<EOF > "${SCRATCH_DIR}/$POLICY_FILE"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "route53:GetChange",
      "Resource": "arn:aws:route53:::change/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/$HOSTEDZONEID"
    }
  ]
}
EOF

# Create IAM role
echo "Creating trust policy $TRUST_POLICY_FILE file in local directory..."
cat <<EOF > "${SCRATCH_DIR}/$TRUST_POLICY_FILE"
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_ENDPOINT}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDC_PROVIDER_ENDPOINT}:sub": [
                        "system:serviceaccount:${CERTMGR_NAMESPACE}:${CERTMGR_SA}"
                    ]
                }
            }
        }
    ]
}
EOF

echo AWS Acount ID: $AWS_ACCOUNT_ID
echo OIDC Provider: $OIDC_PROVIDER_ENDPOINT
echo CERT Manager Namespace: $CERTMGR_NAMESPACE
echo Cert Manager Service Account: $CERTMGR_SA
echo Policy Name: $POLICY_NAME

# Create IAM Role 
echo "Creating IAM ROLE ${CLUSTER_NAME}-demo-certmgr-r53-role ..."
ROLE_ARN=$(create_iam_role "$CLUSTER_NAME") || true
echo "Role ARN: $ROLE_ARN"

# Create IAM Policy
echo "Creating Trust Policy $POLICY_NAME..."
POLICY_ARN=$(create_iam_policy "$CLUSTER_NAME") || true
echo "Policy ARN: $POLICY_ARN"

# Attach IAM Role to Policy
echo "Attaching ${CLUSTER_NAME}-demo-certmgr-r53-role to $POLICY_NAME..."
attach_policy_to_role "$CLUSTER_NAME-demo-certmgr-r53-role" "$POLICY_ARN" || true

echo Successfully attached!

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  annotations:
    openshift.io/display-name: "cert-manager Operator for Red Hat OpenShift"
  labels:
    openshift.io/cluster-monitoring: 'true'
  name: $CERTMGR_NAMESPACE
EOF

# Label openshift-ingress for monitoring
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: 'true'
  name: openshift-ingress
EOF

# Installing Cert Manager Operator
echo Installing Cert Manager 
helm upgrade --install cert-manager cert-manager -n $CERTMGR_NAMESPACE

sleep 90

# Create Service Account for SA 
echo "Creating Service Account called $CERTMGR_NAMESPACE..."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    eks.amazonaws.com/role-arn: $ROLE_ARN
  name: $CERTMGR_SA
  namespace: $CERTMGR_NAMESPACE
EOF


# Restart cert-manager pods
echo Restart cert manager pods to apply STS...
oc delete deployment cert-manager -n $CERTMGR_NAMESPACE

oc get certmanager cluster -o yaml

# Patching cert manager instance
echo Patching cert manager to force use of ambient STS credentials...
cat <<EOF | oc apply -f -
apiVersion: operator.openshift.io/v1alpha1
kind: CertManager
metadata:
  name: cluster
spec:
  controllerConfig:
    overrideArgs:
    - "--issuer-ambient-credentials"
EOF


cat <<EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: $CLUSTERISSUER_NAME
spec:
  acme:
    # server: https://acme-v02.api.letsencrypt.org/directory
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: fanyaegb@redhat.com
    privateKeySecretRef:
      name: $CLUSTERISSUER_NAME-priv-key
    solvers:
    - dns01:
        route53:
          region: $AWS_REGION
          hostedZoneID: $HOSTEDZONEID
EOF

cat << EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: $DOMAIN
  namespace: $CERTMGR_NAMESPACE
spec:
  secretName: $DOMAIN
  commonName: $DOMAIN
  dnsNames:
  - $DOMAIN
  issuerRef:
    name: $CLUSTERISSUER_NAME
    kind: ClusterIssuer
EOF

cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: $DOMAIN
  namespace: openshift-ingress
spec:
  secretName: $CERT_NAME
  commonName: $DOMAIN
  dnsNames:
  - $DOMAIN
  issuerRef:
    name: $CLUSTERISSUER_NAME
    kind: ClusterIssuer
EOF

cat  <<EOF | oc apply -f -
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  annotations:
    ingress.operator.openshift.io/auto-delete-load-balancer: "true"
  finalizers:
  - ingresscontroller.operator.openshift.io/finalizer-ingresscontroller
  generation: 2
  labels:
    hypershift.openshift.io/managed: "true"
  name: $INGRESS_NAME
  namespace: openshift-ingress-operator
spec:
  defaultCertificate:
    name: $CERT_NAME
  domain: $DOMAIN
  endpointPublishingStrategy:
    loadBalancer:
      dnsManagementPolicy: Unmanaged
      providerParameters:
        aws:
          type: NLB
        type: AWS
      scope: $SCOPE
    type: LoadBalancerService
  replicas: 2
  logging:
    access:
      destination:
        type: Container
EOF



# oc new-project testapp2
# oc new-app --docker-image=docker.io/openshift/hello-openshift -n testapp2
# oc -n openshift-ingress-operator patch ingresscontroller/default --patch '{"spec":{"routeAdmission":{"namespaceOwnership":"InterNamespaceAllowed"}}}' --type=merge
# oc -n openshift-ingress-operator patch ingresscontroller/$INGRESS_NAME --patch '{"spec":{"routeAdmission":{"namespaceOwnership":"InterNamespaceAllowed"}}}' --type=merge
# oc new-app --name echo --image=quay.io/3scale/echoapi:stable