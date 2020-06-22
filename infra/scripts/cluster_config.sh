#!/bin/bash
SUBSCRIPTION_ID=$1
AKS_RESOURCE_GROUP=$2
CLUSTER_NAME=$3
NAME_SPACES=("ingress-nginx" "test" "uat" "prod")
IDENTITY_NAME="${3}-agentpool"

az aks get-credentials -n $CLUSTER_NAME -g $AKS_RESOURCE_GROUP

for namespace in ${NAME_SPACES[@]};
do
     # create namespace
     kubectl create namespace $namespace
done

###########################################################################################################
# Start config AAD Pod Identity
###########################################################################################################

# Deploy aad-pod-identity
helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
helm install aad-pod-identity aad-pod-identity/aad-pod-identity

LOCATION="$(az aks show -g $AKS_RESOURCE_GROUP -n $CLUSTER_NAME --query location -otsv)"

RESOURCE_GROUP="MC_${AKS_RESOURCE_GROUP}_${CLUSTER_NAME}_${LOCATION}"

IDENTITY_CLIENT_ID="$(az identity show -g $RESOURCE_GROUP -n $IDENTITY_NAME --subscription $SUBSCRIPTION_ID --query clientId -otsv)"
IDENTITY_RESOURCE_ID="$(az identity show -g $RESOURCE_GROUP -n $IDENTITY_NAME --subscription $SUBSCRIPTION_ID --query id -otsv)"

#az role assignment create --role "Managed Identity Operator" --assignee $IDENTITY_CLIENT_ID --scope "/subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${RESOURCE_GROUP}"
#az role assignment create --role "Virtual Machine Contributor" --assignee $IDENTITY_CLIENT_ID --scope "/subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${RESOURCE_GROUP}"

###########################################################################################################
# End config AAD Pod Identity
###########################################################################################################


###########################################################################################################
# Start config secrets-store-csi-driver for Key Vault
###########################################################################################################

# Install secrets store csi driver and Azure Key Vault Provider
helm repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
helm install csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --generate-name

# Assign Reader Role to new Identity for your keyvault
#az role assignment create --role "Reader" --assignee $IDENTITY_CLIENT_ID --scope "/subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${KV_RG}/providers/Microsoft.KeyVault/vaults/${KV_NAME}"
# set policy to access keys in your keyvault
#az keyvault set-policy -n $KV_NAME --key-permissions get --spn $IDENTITY_CLIENT_ID
# set policy to access secrets in your keyvault
#az keyvault set-policy -n $KV_NAME --secret-permissions get --spn $IDENTITY_CLIENT_ID
# set policy to access certs in your keyvault
#az keyvault set-policy -n $KV_NAME --certificate-permissions get --spn $IDENTITY_CLIENT_ID

cat <<EOF | kubectl apply -f -
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity
metadata:
  name: $CLUSTER_NAME-azid
spec:
  type: 0
  resourceID: $IDENTITY_RESOURCE_ID
  clientID: $IDENTITY_CLIENT_ID
EOF

cat <<EOF | kubectl apply -f -
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentityBinding
metadata:
  name: $CLUSTER_NAME-binding
spec:
  azureIdentity: $CLUSTER_NAME-azid
  selector: $CLUSTER_NAME-id
EOF

###########################################################################################################
# End config secrets-store-csi-driver for Key Vault
###########################################################################################################