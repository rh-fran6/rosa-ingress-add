# Certificate Manager Setup

This repository contains Bash scripts for setting up and cleaning up a certificate manager in your Kubernetes cluster using OpenShift. These scripts automate the process of creating IAM roles and policies, configuring the certificate manager, and installing necessary resources in your cluster.

## Prerequisites

Before running the scripts, ensure that you have the following prerequisites set up:

- AWS CLI configured with appropriate permissions
- OpenShift CLI (`oc`) installed and configured to connect to your cluster
- Helm installed for managing Kubernetes applications

## Script 1: cert-manager-setup.sh

This script sets up the certificate manager by performing the following steps:

1. Prompts the user to enter the cluster name and Route53 DNS name.
2. Retrieves the Hosted Zone ID for the specified DNS name.
3. Creates IAM roles and policies required for managing Route53 records.
4. Creates a namespace for cert-manager and labels it for cluster monitoring.
5. Installs the cert-manager operator using Helm.
6. Creates a service account for the certificate manager with appropriate permissions.
7. Configures the certificate manager instance with necessary settings.
8. Creates a ClusterIssuer for managing certificates.
9. Deploys certificates for the specified domain.

To run the script, execute:

```bash
./cert-manager-setup.sh
```


Certainly! Here's the complete README.md file with both scripts and additional notes:

markdown
Copy code
# Certificate Manager Setup

This repository contains Bash scripts for setting up and cleaning up a certificate manager in your Kubernetes cluster using OpenShift. These scripts automate the process of creating IAM roles and policies, configuring the certificate manager, and installing necessary resources in your cluster.

## Prerequisites

Before running the scripts, ensure that you have the following prerequisites set up:

- AWS CLI configured with appropriate permissions
- OpenShift CLI (`oc`) installed and configured to connect to your cluster
- Helm installed for managing Kubernetes applications

## Script 1: cert-manager-setup.sh

This script sets up the certificate manager by performing the following steps:

1. Prompts the user to enter the cluster name and Route53 DNS name.
2. Retrieves the Hosted Zone ID for the specified DNS name.
3. Creates IAM roles and policies required for managing Route53 records.
4. Creates a namespace for cert-manager and labels it for cluster monitoring.
5. Installs the cert-manager operator using Helm.
6. Creates a service account for the certificate manager with appropriate permissions.
7. Configures the certificate manager instance with necessary settings.
8. Creates a ClusterIssuer for managing certificates.
9. Deploys certificates for the specified domain.
10. User cert manager issued certificate for the custom ingress controller.

To run the script, execute:

```bash
./cert-manager-setup.sh
```

Make sure to review and adjust the script variables as per your environment before running it.

## Script 2: cert-manager-cleanup.sh

This script cleans up the resources created by the first script. It deletes IAM roles, policies, namespaces, certificate manager instance, and associated resources.

To run the script, execute:

```bash
./cert-manager-cleanup.sh
```

Make sure to review and adjust the script variables as per your environment before running it.

## Additional Notes

1. Please review and adjust the scripts as per your specific requirements before executing them in your environment.
2. These scripts assume certain configurations and may need modifications based on your environment and policies.
3. Always exercise caution when running scripts that interact with your production environment.
