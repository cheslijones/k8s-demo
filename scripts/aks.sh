#!/bin/bash
#CHANGE THESE AS NEEDED
resourceGroupName="k8stut"
region="westus"
k8sVersion="1.19.7"
size="Standard_B2s"

RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"
PROMPT_EOL_MARK=""

echo ""
echo "Select one of the following:"
echo "[S]etup resource group and services (Container Registry, Key Vault, and Kubernetes Services)..."
echo "[I]ntegrate Key Vaule and Kubernetes Services..."
echo "[D]estroy the resource group (NOT RECOMMENDED)."
printf "Response? (s/i/d) "
read -k userResponse
echo "\n"

resourceGroupSetup() {
    echo "Setting up the resource group..."
    echo ""

    # creates the resource group
    az group create -l $region -n $resourceGroupName
    echo ""

    # creates azure container registry
    az acr create -g $resourceGroupName -n ${resourceGroupName}acr --sku Basic -l $region
    echo ""

    # creates azure keyv ault
    az keyvault create -n ${resourceGroupName}akv -g $resourceGroupName -l $region
    echo ""

    # add secrets to the keyvault
    # NORMALLY THESE VALUES WOULD NOT BE STORED IN A FILE ESPECIALLY IF THE REPO IS PUBLIC
    # THIS IS JUST FOR DEMO PURPOSES AND SHOULD NOT BE USED IN ACTUAL PROJECTS
    az keyvault secret set --vault-name ${resourceGroupName}akv --name DEV-DJANGOSECRETKEY --value "o9n==^po&cio93kl57ll#1n=n5537=x3r9qqb9)^hvpc)hn2&#"
    az keyvault secret set --vault-name ${resourceGroupName}akv --name DEV-PGDATABASE --value "${resourceGroupName}_dev"
    az keyvault secret set --vault-name ${resourceGroupName}akv --name DEV-PGPORT --value "5432"
    az keyvault secret set --vault-name ${resourceGroupName}akv --name DEV-PGUSER --value "${resourceGroupName}-dev"
    az keyvault secret set --vault-name ${resourceGroupName}akv --name DEV-PGPASSWORD --value "password12345"

    # creates azure kubernetes service
    az aks create -n ${resourceGroupName}aks \
        -g $resourceGroupName \
        --kubernetes-version=$k8sVersion \
        --node-count 1 \
        -l $region \
        --enable-managed-identity \
        --attach-acr ${resourceGroupName}acr \
        -s $size \
        --network-plugin azure
    echo ""

    # switch to the context of the new aks cluster
    az aks get-credentials -n ${resourceGroupName}aks -g $resourceGroupName
    echo ""
    echo "Done."
}

akvIntegration() {
    helm repo add csi-secrets-store-provider-azure \
        https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
    helm install csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --generate-name
}

destoryResourceGroup() {
    # make sure the user wants to destroy the resource group
    echo "${RED}This is destructive and get rid of everything in the resource group."
    printf "Are you sure you want to continue? (y/n)${NC} "
    read -k confirmDestroy
    echo "\n"

    case $confirmDestroy in
    [yY])
        echo "Destroying resource group..."
        echo ""
        
        # Delete the group
        az aks delete -n ${resourceGroupName}aks -g $resourceGroupName
        echo ""

        # Make sure to purge the keys
        az keyvault purge --name ${resourceGroupName}akv
        echo ""
        echo "Done."
        ;;
    [nN])
        echo "Stopping shell script."
        ;;
    *)
        echo "This is not a valid option."
        ;;
    esac
}

case $userResponse in
[sS])
    resourceGroupSetup
    ;;
[iI])
    akvIntegration
    ;;
[dD])
    destoryResourceGroup
    ;;
*)
    echo "This is not a valid option."
    ;;
esac
