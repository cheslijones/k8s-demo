#!/bin/bash
az group create -l westus -n k8s-tut && \
az acr create -g k8s-tut -n k8stutacr --sku Basic -l westus && \
az keyvault create --name k8stutakv --resource-group k8s-tut -l westus && \
az keyvault secret set --vault-name k8stutakv --name SECRETTEST --value abc123 && \
az aks create -n k8stutaks -g k8s-tut --kubernetes-version=1.19.7 --node-count 1 -l westus --enable-managed-identity --attach-acr k8stutacr -s Standard_B2s --network-plugin azure && \
az aks get-credentials -n k8stutaks -g k8s-tut && \
helm repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts && \
helm install csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --generate-name
