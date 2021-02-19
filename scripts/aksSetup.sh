#!/bin/bash
# create the azure resource group
az group create -l westus -n k8s-tut 

# create the azure container registry
az acr create -g k8s-tut -n k8stutacr --sku Basic -l westus 

# creat the key vault
az keyvault create --name k8stutakv --resource-group k8s-tut -l westus 

# add secrets to the keyvault 
# NORMALLY THESE VALUES WOULD NOT BE STORED IN A FILE ESPECIALLY IF THE REPO IS PUBLIC
# THIS IS JUST FOR DEMO PURPOSES AND SHOULD NOT BE USED IN ACTUAL PROJECTS
az keyvault secret set --vault-name k8stutakv --name DEV-DJANGOSECRETKEY --value "o9n==^po&cio93kl57ll#1n=n5537=x3r9qqb9)^hvpc)hn2&#"
az keyvault secret set --vault-name k8stutakv --name DEV-PGDATABASE --value "k8s_tut_dev" 
az keyvault secret set --vault-name k8stutakv --name DEV-PGPORT --value "5432" 
az keyvault secret set --vault-name k8stutakv --name DEV-PGUSER --value "k8s-tut-dev" 
az keyvault secret set --vault-name k8stutakv --name DEV-PGPASSWORD --value "password12345"

# create the azure kubernetes service
az aks create -n k8stutaks -g k8s-tut --kubernetes-version=1.19.7 --node-count 1 -l westus --enable-managed-identity --attach-acr k8stutacr -s Standard_B2s --network-plugin azure 

# add the aks context to local .kubeconfig
az aks get-credentials -n k8stutaks -g k8s-tut
