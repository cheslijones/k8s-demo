#!/bin/bash
# CHANGE THESE AS NEEDED
driver="docker"
clusterName=$(basename $PWD)
k8sVersion="1.19.7"

# formats
RED="\033[0;31m"
GREEN="\033[0;32m"
BLUE="\033[0;36m"
NC="\033[0m"
PROMPT_EOL_MARK=""

echo ""
echo "${BLUE}Select one of the following:"
echo "[S]etup dev environment (creates a new minikube cluster from scratch and everything in it)..."
echo "[R]efresh cluster (creates storage, secrets, local dependencies)..."
echo "[C]lean cluster (deletes storage, secrets, local dependencies)..."
echo "[D]estroy cluster (deletes minikube container and everything in it)..."
printf "Response? (s/r/c/d)${NC} "
read -k userResponse
echo "\n"

standardSetup() {
    # switch to correct context (should happen automatically, but just in case)
    echo ""
    echo "${GREEN}Setting the correct context...${NC}"
    kubectl config use-context $clusterName
    echo "${GREEN}Done.${NC}"
    echo ""

    # apply ingress nginx controller settings
    echo "${GREEN}Appling ingress-nginx controller...${NC}"
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.44.0/deploy/static/provider/cloud/deploy.yaml
    echo "${GREEN}Done.${NC}"
    echo ""

    # create development namespace in kubectl
    echo "${GREEN}Creating the development namespace...${NC}"
    kubectl create ns development
    echo "${GREEN}Done.${NC}"
    echo ""

    # create storage for postgresql and files
    echo "${GREEN}Creating storage...${NC}"
    kubectl apply -f k8s/storage/development.yaml -n development
    echo "${GREEN}Done.${NC}"
    echo ""

    # make sure using correct node version (change as necessary)
    echo "${GREEN}Installing and switching to the correct NodeJS version...${NC}"
    nvm install 14
    nvm use 14
    echo "${GREEN}Done.${NC}"
    echo ""

    # move into api and create virtualenv
    echo "${GREEN}Switching into the api service and creating virtualenv...${NC}"
    cd api
    virtualenv -p python3 .venv
    echo "${GREEN}Done.${NC}"
    echo ""

    # activate the .venv
    echo "${GREEN}Activate virtualenv...${NC}"
    source .venv/bin/activate
    echo "${GREEN}Done.${NC}"
    echo ""

    # install api dependencies
    echo "${GREEN}Install API dependencies...${NC}"
    pip install -r requirements.txt
    echo "${GREEN}Done.${NC}"
    echo ""

    # go into the client and install dependencies
    echo "${GREEN}Install Client dependencies...${NC}"
    cd ../client
    npm install
    echo "${GREEN}Done.${NC}"
    echo ""

    # go into the  and install dependencies
    echo "${GREEN}Install Admin dependencies...${NC}"
    cd ../admin
    npm install
    echo "${GREEN}Done.${NC}"
    echo ""

    # navigate back to project root
    cd ..

    # get necessary env vars from akv
    echo "${GREEN}Retrieving secrets from Azure Key Vault...${NC}"
    djangoSecret=$(az keyvault secret show --vault-name ${clusterName}akv -n DEV-DJANGOSECRETKEY --query value | tr -d '"')
    domain=localhost
    debug=True
    pgDatabase=$(az keyvault secret show --vault-name ${clusterName}akv -n DEV-PGDATABASE --query value | tr -d '"')
    pgHost=localhost
    pgPort=$(az keyvault secret show --vault-name ${clusterName}akv -n DEV-PGPORT --query value | tr -d '"')
    pgUser=$(az keyvault secret show --vault-name ${clusterName}akv -n DEV-PGUSER --query value | tr -d '"')
    pgPassword=$(az keyvault secret show --vault-name ${clusterName}akv -n DEV-PGPASSWORD --query value | tr -d '"')
    echo "${GREEN}Done.${NC}"
    echo ""

    # write env vars from akz into api .venv env
    echo "${GREEN}Adding env vars to virtualenv...${NC}"
    echo '' >>api/.venv/bin/activate
    echo "export SECRET_KEY='"$djangoSecret"'" >>api/.venv/bin/activate
    echo "export DOMAIN='"$domain"'" >>api/.venv/bin/activate
    echo "export DEBUG=$debug" >>api/.venv/bin/activate
    echo "export PGDATABASE='"$pgDatabase"'" >>api/.venv/bin/activate
    echo "export PGHOST='"$pgHost"'" >>api/.venv/bin/activate
    echo "export PGPORT='"$pgPort"'" >>api/.venv/bin/activate
    echo "export PGUSER='"$pgUser"'" >>api/.venv/bin/activate
    echo "export PGPASSWORD='"$pgPassword"'" >>api/.venv/bin/activate
    echo "${GREEN}Done.${NC}"
    echo ""

    # make the k8s secrets
    echo "${GREEN}Adding env vars to cluster...${NC}"
    kubectl create secret generic ${clusterName}-dev-secrets \
        --from-literal=SECRET_KEY=$djangoSecret \
        --from-literal=DOMAIN=$domain \
        --from-literal=DEBUG=$debug \
        --from-literal=PGDATABASE=$pgDatabase \
        --from-literal=PGHOST=$pgHost \
        --from-literal=PGPORT=$pgPort \
        --from-literal=PGUSER=$pgUser \
        --from-literal=PGPASSWORD=$pgPassword \
        -n development
    echo "${GREEN}Done.${NC}"
    echo ""
}

setup() {
    echo "${GREEN}Setting environment up from scratch...${NC}"
    echo ""
    # create minikube container for the project (change --kuberentes-version as necessary)
    echo "${GREEN}Creating minikube cluster...${NC}"
    minikube -p $clusterName start --kubernetes-version=$k8sVersion --driver=$driver
    echo "${GREEN}Done.${NC}"

    # call the function where the bulk of the setup resides
    standardSetup
    echo "${GREEN}Done setting up the dev environment.${NC}"

}

refresh() {
    echo "Refreshing existing cluster..."
    # call the function where the bulk of the setup resides
    standardSetup
    echo "${GREEN}Done refreshing the dev environment.${NC}"

}

clean() {
    # have the user confirm they want to clean the cluster
    echo "${RED}This is destructive and will do the following:"
    echo "  - Delete environment variable secrets"
    echo "  - Delete PostgreSQL and file storage"
    echo "  - Delete local node_modules and .venv"
    echo "  - Does NOT delete the minikube cluster"
    printf "Are you sure you want to continue? (y/n)${NC} "
    read -k confirmClean
    echo "\n"
    case $confirmClean in
    [yY])
        echo "${RED}Cleaning cluster...${NC}"
        echo ""

        # set correct context
        echo "${RED}Switching to the correct conrext...${NC}"
        kubectl config use-context $clusterName
        echo "${RED}Done.${NC}"
        echo ""

        # deactivate the .venv env
        echo "${RED}Deactivate virtualenv...${NC}"
        deactivate
        echo "${RED}Done.${NC}"
        echo ""

        # delete secrets from the cluster
        echo "${RED}Delete secrets...${NC}"
        kubectl delete secrets ${clusterName}-dev-secrets -n development
        echo "${RED}Done.${NC}"
        echo ""

        # delete storage from the cluster
        echo "${RED}Delete storage...${NC}"
        kubectl delete -f k8s/storage/development.yaml -n development
        echo "${RED}Done.${NC}"
        echo ""

        # delete local dependencies
        echo "${RED}Delete local dependencies...${NC}"
        rm -rf client/node_modules admin/node_modules api/.venv
        echo "${RED}Done.${NC}"
        echo""

        echo "Done cleaning the cluster."
        ;;
    [nN])
        echo "${RED}Stopping shell script...${NC}"
        ;;
    *)
        echo "${RED}This is not a valid option.${NC}"
        ;;
    esac
}

destroy() {
    # make sure the user wants to destroy the cluster
    echo "${RED}This is destructive and will do the following:"
    echo "  - Delete the minikube cluster and everything in it"
    echo "  - Delete local node_modules and .venv"
    printf "Are you sure you want to continue? (y/n)${NC} "
    read -k confirmDestroy
    echo "\n"

    case $confirmDestroy in
    [yY])
        echo "${RED}Destroying the dev cluster...${NC}"
        echo ""
        
        # set the correct context
        echo "${RED}Switching to the correct context...${NC}"
        kubectl config use-context ${clusterName}
        echo "${RED}Done.${NC}"
        echo ""

        # deactivate the .venv env
        echo "${RED}Deactivating virtualenv...${NC}"
        deactivate
        echo "${RED}Done.${NC}"
        echo ""

        # delete the minikube cluster
        echo "${RED}Destroy the minikube cluster...${NC}"
        minikube delete -p ${clusterName}
        echo "${RED}Done.${NC}"
        echo ""

        # delete local dependencies
        echo "${RED}Delete local dependencies...${NC}"
        rm -rf client/node_modules admin/node_modules api/.venv
        echo "${RED}Done.${NC}"
        echo ""

        echo "${RED}Done destroying the dev cluster.${NC}"
        ;;
    [nN])
        echo "${RED}Stopping shell script...${NC}"
        ;;
    *)
        echo "${RED}This is not a valid option.${NC}"
        ;;
    esac
}

case $userResponse in
[sS])
    setup
    ;;
[rR])
    refresh
    ;;
[cC])
    clean
    ;;
[dD])
    destroy
    ;;
*)
    echo "${RED}This is not a valid option.${NC}"
    ;;
esac
