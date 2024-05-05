#!/bin/bash

export CERTMGR_NAMESPACE="cert-manager"
export CERTMGR_SA="cert-manager"
export TRUST_POLICY_FILE="TrustPolicy.json"
export POLICY_FILE="s3Policy.json"
export SCRATCH_DIR="./"
export CERT_NAME="sandbox2791-cert"
export SCOPE="External"
export CLUSTERISSUER_NAME="demo-clusterissuer"


# Validating Zone ID
echo "Please enter Route53 DNS Domain :"
read -r DOMAIN

HOSTEDZONEID=$(get_hosted_zone_id "$DOMAIN")

INGRESS_NAME=$DOMAIN-ingresscontroller

echo "Please enter Cluster Name:"
read -r CLUSTER_NAME

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

POLICY_NAME="${CLUSTER_NAME}-demo-certmgr-r53-policy"
ROLE_NAME="${CLUSTER_NAME}-demo-certmgr-r53-role"

# Function to print error message and exit
handle_error() {
    echo "An error occurred. Exiting..."
    exit 1
}

# Read Cluster Name
get_hosted_zone_id() {
    aws route53 list-hosted-zones-by-name --dns-name "${1}" | jq -r '.HostedZones[].Id' | cut -d'/' -f3
}

# Trap errors and handle them using the handle_error function
trap handle_error ERR

# Grab policy ARN
echo "Retrieving IAM policy ARN..."
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" --output text) || true

if [[ -z "$POLICY_ARN" ]]; then
    echo "Policy $POLICY_NAME not found. "
fi

# Deleting policy files from directory
echo "Deleting json files from local directory..."
rm -rf *.json

# Detach policy from role
echo "Detaching IAM policy from role..."
aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" || true

# Delete IAM role
echo "Deleting IAM role..."
aws iam delete-role --role-name "$ROLE_NAME" || true

# Delete IAM policy
echo "Deleting IAM policy..."
aws iam delete-policy --policy-arn "$POLICY_ARN" || true

# Delete Service Account
echo "Delete Service Account called cert-manager..."
oc delete serviceaccount cert-manager -n cert-manager || true

# Deleting ClusterIssuer
echo "Delete ClusterIssuer called letsencrypt-dev..."
oc delete clusterissuer $CLUSTERISSUER_NAME || true

# Deleting Certificate called $DOMAIN
echo "Delete Certificate $CERT_NAME..."
oc delete certificate $CERT_NAME -n openshift-ingress || true

# Deleting Certificate called $DOMAIN
echo "Delete Certificates ..."
oc delete certificate $DOMAIN -n $CERTMGR_NAMESPACE || true

# Deleting IngressController called $INGRESS_NAME
echo "Delete Certificate called $DOMAIN..."
oc delete ingresscontroller $INGRESS_NAME -n openshift-ingress-operator || true

# Deleting Deployment
echo "Delete Deployments $DOMAIN..."
oc delete deployment -n $CERTMGR_NAMESPACE -l app.kubernetes.io/instance=$CERTMGR_NAMESPACE || true

# Get a list of namespaces
namespaces=$(oc get namespaces -o=jsonpath='{.items[*].metadata.name}')

# Loop through each namespace
for namespace in $namespaces; do
    # Get a list of issuers in the current namespace
    issuers=$(oc get issuer -n $namespace -o=jsonpath='{.items[*].metadata.name}')

    # Check if there are issuers in the namespace
    if [ -n "$issuers" ]; then
        echo "Deleting issuers in namespace $namespace..."
        
        # Loop through each issuer in the namespace
        for issuer in $issuers; do
            # Delete the issuer
            oc delete issuer $issuer -n $namespace || true
        done
    else
        echo "No issuers found in namespace $namespace."
    fi
done

# Deleting Cert Manager CRDs
echo Deleting Cert Manager CRDs...
certreqs=$(oc get certificaterequest -n $CERTMGR_NAMESPACE | grep $CERT_NAME | awk '{print $1}')
challenge=$(oc get challenge -n $CERTMGR_NAMESPACE | grep $CERT_NAME | awk '{print $1}')
orders=$(oc get order -n $CERTMGR_NAMESPACE | grep $CERT_NAME | awk '{print $1}')
clusterissuer=$(oc get clusterissuer | awk '{print $1}')

echo Deleting ClusterIssuers ...
if [ -n "$clusterissuer" ]; then
    for i in $clusterissuer; do
        oc delete clusterissuer $i -n $CERTMGR_NAMESPACE || true
    done
fi

echo Deleting Open Cert Requests ...
if [ -n "$certreqs" ]; then
    for i in $certreqs; do
        oc delete certificaterequest $i -n $CERTMGR_NAMESPACE || true
    done
fi

echo Deleting Open Challenges ...
if [ -n "$challenge" ]; then
    for i in $challenge; do
        oc delete challenge $i -n $CERTMGR_NAMESPACE || true
    done
fi

echo Deleting Open Orders ...
if [ -n "$orders" ]; then
    for i in $orders; do
        oc delete order $i -n $CERTMGR_NAMESPACE || true
    done
fi


# Deleting CertManager instance...
echo "Delete CertManager Instance..."
oc delete certmanager cluster -n cert-manager || true

# Installing Cert Manager Operator
echo Uninstalling Cert Manager Helm Chart
helm uninstall cert-manager -n $CERTMGR_NAMESPACE || true

# Deleting Cert Manager Namespace
echo Deleting Cert Manager Namespace
oc delete project $CERTMGR_NAMESPACE --wait || true
