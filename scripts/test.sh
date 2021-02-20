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