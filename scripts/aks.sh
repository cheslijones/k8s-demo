#!/bin/bash
#CHANGE THESE AS NEEDED
resourceGroupName="k8stut"
region="westus"
k8sVersion="1.19.7"
size="Standard_B2s"

RED="\033[0;31m"
GREEN="\033[0;32m"
BLUE="\033[0;36m"
NC="\033[0m"
PROMPT_EOL_MARK=""

echo ""
echo "${BLUE}Select one of the following:"
echo "[S]etup resource group and services (Container Registry, Key Vault, and Kubernetes Services)..."
echo "[I]ntegrate Key Vaule and Kubernetes Services..."
echo "[D]estroy the resource group (NOT RECOMMENDED)."
printf "Response? (s/i/d)${NC} "
read -k userResponse
echo "\n"

resourceGroupSetup() {
    echo "${GREEN}Setting up the resource group...${NC}"
    echo ""

    # creates the resource group
    echo "${GREEN}Creating the ${resourceGroupName} resource group...${NC}"
    az group create -l $region -n $resourceGroupName
    echo "${GREEN}Done.${NC}"
    echo ""

    # creates azure container registry
    echo "${GREEN}Creating the ${resourceGroupName}acr container registry...${NC}"
    az acr create -g $resourceGroupName -n ${resourceGroupName}acr --sku Basic -l $region
    echo "${GREEN}Done.${NC}"
    echo ""

    # creates azure keyvault
    echo "${GREEN}Creating the ${resourceGroupName}akv key vault...${NC}"
    az keyvault create -n ${resourceGroupName}akv -g $resourceGroupName -l $region
    echo "${GREEN}Done.${NC}"
    echo ""

    # add secrets to the keyvault
    # NORMALLY THESE VALUES WOULD NOT BE STORED IN A FILE ESPECIALLY IF THE REPO IS PUBLIC
    # THIS IS JUST FOR DEMO PURPOSES AND SHOULD NOT BE USED IN ACTUAL PROJECTS
    echo "${GREEN}Creating the demo secrets...${NC}"
    echo "${RED}THIS IS JUST TO DEMO. NEVER DO THIS ESPECIALLY IN A PUBLIC REPO...${NC}"
    az keyvault secret set --vault-name ${resourceGroupName}akv --name DEV-DJANGOSECRETKEY --value "o9n==^po&cio93kl57ll#1n=n5537=x3r9qqb9)^hvpc)hn2&#"
    az keyvault secret set --vault-name ${resourceGroupName}akv --name DEV-PGDATABASE --value "${resourceGroupName}_dev"
    az keyvault secret set --vault-name ${resourceGroupName}akv --name DEV-PGPORT --value "5432"
    az keyvault secret set --vault-name ${resourceGroupName}akv --name DEV-PGUSER --value "${resourceGroupName}-dev"
    az keyvault secret set --vault-name ${resourceGroupName}akv --name DEV-PGPASSWORD --value "password12345"
    echo "${GREEN}Done.${NC}"
    echo ""

    # creates azure kubernetes service
    echo "${GREEN}Building kuberetes cluster... take a break, this takes about 10 minutes...${NC}"
    az aks create -n ${resourceGroupName}aks \
        -g $resourceGroupName \
        --kubernetes-version=$k8sVersion \
        --node-count 1 \
        -l $region \
        --enable-managed-identity \
        --attach-acr ${resourceGroupName}acr \
        -s $size \
        --network-plugin azure
    echo "${GREEN}Done.${NC}"
    echo ""

    # switch to the context of the new aks cluster
    echo "${GREEN}Switching to the correct context...${NC}"
    az aks get-credentials -n ${resourceGroupName}aks -g $resourceGroupName
    echo ""

    echo "${GREEN}Done creating the resource group and all services.${NC}"

}

akvIntegration() {
    echo "${GREEN}Integrating Azure Kubernetes Services and Azure Key Vault...${NC}"
    echo ""

    # set the correct context
    echo "${GREEN}Switching to the correct context...${NC}"
    kubectl config use-context ${resourceGroupName}aks
    echo "${GREEN}Done.${NC}"
    echo ""

    # assign variables
    echo "${GREEN}Settings variables...${NC}"
    subscriptionId=$(az account show --query id -otsv)
    aksClientId=$(az aks show -n ${resourceGroupName}aks -g $resourceGroupName --query identityProfile.kubeletidentity.clientId -otsv)
    aksResourceGroup=$(az aks show -n k8stutaks -g k8stut --query nodeResourceGroup -otsv)
    scope="/subscriptions/${subscriptionId}/resourcegroups/${aksResourceGroup}"
    echo "${GREEN}Done.${NC}"
    echo ""

    echo "${GREEN}Getting helm charts for CSI and installing...${NC}"
    # Add the helm charts for csi
    helm repo add csi-secrets-store-provider-azure \
        https://raw.githubusercontent.com/Azure/secretst-store-csi-driver-provider-azure/master/charts

    # Install the helm charts
    helm install csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --generate-name
    echo "${GREEN}Done.${NC}"
    echo ""

    # create rbac roles necessary for the integration
    echo "${GREEN}Creating the necessary role dependencies...${NC}"
    az role assignment create --role "Managed Identity Operator" --assignee $aksClientId --scope $scope
    az role assignment create --role "Virtual Machine Contributor" --assignee $aksClientId --scope $scope
    echo "${GREEN}Done.${NC}"
    echo ""

    echo "${GREEN}Getting helm charts for AAD Pod Identity and installing...${NC}"
    # Add the helm charts for aad-pod-identity
    helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts

    # Install the helm charts
    helm install pod-identity aad-pod-identity/aad-pod-identity
    echo "${GREEN}Done.${NC}"
    echo ""

    # Create identity for the integratoin
    echo "${GREEN}Getting helm charts for AAD Pod Identity and installing...${NC}"
    az identity create -g $aksResourceGroup -n AksAkvIntegrationIdentity
    echo "${GREEN}Done.${NC}"
    echo ""

    # pause to give time the identity to be created and query it
    echo "${GREEN}Taking a break while Pods are spinning up and identities are being created...${NC}"
    sleep 10
    echo "${GREEN}Done.${NC}"
    echo ""

    # Get the clientid for the new identity
    echo "${GREEN}Declare vars related to the new identity...${NC}"
    identityClientId=$(az identity show -g $aksResourceGroup -n AksAkvIntegrationIdentity --query clientId -otsv)
    identityResourceId=$(az identity show -g $aksResourceGroup -n AksAkvIntegrationIdentity --query id -otsv)
    echo "${GREEN}Done.${NC}"
    echo ""

    # Set the GET policy for the secrets for the identity
    echo "${GREEN}Give the new identity GET privileges to the AKV keys...${NC}"
    az keyvault set-policy -n ${resourceGroupName}akv --secret-permissions get --spn $identityClientId
    echo "${GREEN}Done.${NC}"
    echo ""

    # Build the appropriate kubectl configs
    # There are not yamls of these due to the content being dynamic
    # and based on the AKS subscription. sed could be a possible option
    # to find a nd replace in .yaml files though.
    echo "${GREEN}Create the link and storage for the keys...${NC}"
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
    echo "${GREEN}Donekeys.${NC}"
    echo ""

    echo "${GREEN}Done with the AKS and AKV integration.${NC}"
    echo ""
    echo "${GREEN}Give it a few minutes and then run: kubectl apply -f k8s/test/nginx.yaml${NC}"
}

destoryResourceGroup() {
    # make sure the user wants to destroy the resource group
    echo "${RED}This is destructive and will get rid of everything in the resource group ${resourceGroupName}."
    printf "Are you sure you want to continue? (y/n)${NC} "
    read -k confirmDestroy
    echo "\n"

    case $confirmDestroy in
    [yY])
        echo "${RED}Destroying resource group ${resourceGroupName}...${NC}"
        echo ""

        # Delete the group
        echo "${RED}Deleting resource group ${resourceGroupName}...${NC}"
        az group delete -n $resourceGroupName
        echo "${RED}Done.${NC}"
        echo ""

        # Make sure to purge the keys
        echo "${RED}Purge the ${resourceGroupName}akv key vault...${NC}"
        az keyvault purge --name ${resourceGroupName}akv
        echo "${RED}Done.${NC}"
        echo ""

        echo "${RED}Done destroying the resource group.${NC}"

        ;;
    [nN])
        echo "${RED}Stopping shell script.${NC}"
        ;;
    *)
        echo "${RED}This is not a valid option.${NC}"
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
    echo "${RED}This is not a valid option.${NC}"
    ;;
esac