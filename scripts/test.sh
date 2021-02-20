#!/bin/bash
resourceGroupName="k8stut"

kubectl config use-context ${resourceGroupName}aks

subscriptionId=$(az account show --query id -otsv)
tenantId=$(az account show --query tenantId -otsv)
aksClientId=$(az aks show -n ${resourceGroupName}aks -g $resourceGroupName --query identityProfile.kubeletidentity.clientId -otsv)
aksResourceGroup=$(az aks show -n k8stutaks -g k8stut --query nodeResourceGroup -otsv)
scope="/subscriptions/${subscriptionId}/resourcegroups/${aksResourceGroup}"

# az role assignment create --role "Managed Identity Operator" --assignee $aksClientId --scope $scope
# az role assignment create --role "Virtual Machine Contributor" --assignee $aksClientId --scope $scope

# az identity create -g $aksResourceGroup -n AksAkvIntegrationIdentity

identityClientId=$(az identity show -g $aksResourceGroup -n AksAkvIntegrationIdentity --query clientId -otsv)
identityResourceId=$(az identity show -g $aksResourceGroup -n AksAkvIntegrationIdentity --query id -otsv)

# az keyvault set-policy -n ${resourceGroupName}akv --secret-permissions get --spn $identityClientId
# echo $identityClientId
# echo $identityResourceId

cat <<EOF | kubectl apply -f -
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentity
metadata:
    name: aks-akv-identity
spec:
    type: 0                                 
    resourceID: $identityResourceId
    clientID: $identityClientId
---
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentityBinding
metadata:
    name: aks-akv-identity-binding
spec:
    azureIdentity: aks-akv-identity
    selector: aks-akv-identity-binding-selector
EOF

cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: aks-akv-secret-provider
spec:
  provider: azure
  parameters:
    usePodIdentity: "true"                                        
    keyvaultName: ${resourceGroupName}akv
    cloudName: ""                               
    objects:  |
      array:
        - |
            objectName: DEV-DJANGOSECRETKEY             
            objectType: secret                 
            objectVersion: ""
        - |
            objectName: DEV-PGDATABASE             
            objectType: secret                 
            objectVersion: ""         
        - |
            objectName: DEV-PGPASSWORD             
            objectType: secret                 
            objectVersion: ""         
        - |
            objectName: DEV-PGPORT             
            objectType: secret                 
            objectVersion: ""     
        - |
            objectName: DEV-PGUSER             
            objectType: secret                 
            objectVersion: ""         
    tenantId: $tenantId
EOF
