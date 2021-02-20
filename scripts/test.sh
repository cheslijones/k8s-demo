#!/bin/bash
resourceGroupName="k8stut"

kubectl config use-context ${resourceGroupName}aks

subscriptionId=$(az account show --query id -otsv)
aksClientId=$(az aks show -n ${resourceGroupName}aks -g $resourceGroupName --query identityProfile.kubeletidentity.clientId -otsv)
aksResourceGroup=$(az aks show -n k8stutaks -g k8stut --query nodeResourceGroup -otsv)
scope="/subscriptions/${subscriptionId}/resourcegroups/${aksResourceGroup}"

az role assignment create --role "Managed Identity Operator" --assignee $aksClientId --scope $scope
az role assignment create --role "Virtual Machine Contributor" --assignee $aksClientId --scope $scope

az identity create -g $aksResourceGroup -n AksAkvIntegrationIdentity

identityClientId=$(az identity show -g $aksResourceGroup -n AksAkvIntegrationIdentity --query clientId -otsv)

az keyvault set-policy -n ${resourceGroupName}akv --secret-permissions get --spn $identityClientId

cat <<EOF | kubectl apply -f -
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentity
metadata:
    name: test
spec:
    type: 0                                 
    resourceID: <resourceId>
    clientID: <clientId>
---
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentityBinding
metadata:
    name: azure-pod-identity-binding
spec:
    azureIdentity: test
    selector: azure-pod-identity-binding-selector
EOF

cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: azure-kvname-podid
spec:
  provider: azure
  parameters:
    usePodIdentity: "true"                                        
    keyvaultName: <akvName>
    cloudName: ""                               
    objects:  |
      array:
        - |
          objectName: SECRETTEST             
          objectType: secret                 
          objectVersion: ""                        
    tenantId: <tenantId>  
EOF