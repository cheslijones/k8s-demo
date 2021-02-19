#!/bin/bash
# CHANGE THESE AS NEEDED
driver="docker"
clusterName=$(basename $PWD)
k8sVersion="1.19.7"

# formats
RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"
PROMPT_EOL_MARK=""

echo ""
echo "Select one of the following:"
echo "[S]etup dev environment (creates a new minikube cluster from scratch and everything in it)..."
echo "[R]efresh cluster (creates storage, secrets, local dependencies)..."
echo "[C]lean cluster (deletes storage, secrets, local dependencies)..."
echo "[D]estroy cluster (deletes minikube container and everything in it)..."
printf "Response? (s/r/c/d) "
read -k userResponse
echo "\n"

standardSetup() {
    # switch to correct context (should happen automatically, but just in case)
    echo ""
    kubectl config use-context $clusterName
    echo ""

    # apply ingress nginx controller settings
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.44.0/deploy/static/provider/cloud/deploy.yaml
    echo ""

    # create development namespace in kubectl
    kubectl create ns development
    echo ""

    # create storage for postgresql and files
    kubectl apply -f k8s/storage/development.yaml -n development
    echo ""

    # make sure using correct node version (change as necessary)
    nvm install 14
    nvm use 14
    echo ""

    # move into api and create virtualenv
    cd api
    virtualenv -p python3 .venv
    echo ""

    # activate the .venv
    source .venv/bin/activate
    echo ""

    # install api dependencies
    pip install -r requirements.txt
    echo ""

    # go into the client and install dependencies
    cd ../client
    npm install
    echo ""

    # go into the  and install dependencies
    cd ../admin
    npm install
    echo ""

    # navigate back to project root
    cd ..
    echo ""

    # get necessary env vars from akv
    djangoSecret=$(az keyvault secret show --vault-name ${clusterName}akv -n DEV-DJANGOSECRETKEY --query value | tr -d '"')
    domain=localhost
    debug=True
    pgDatabase=$(az keyvault secret show --vault-name ${clusterName}akv -n DEV-PGDATABASE --query value | tr -d '"')
    pgHost=localhost
    pgPort=$(az keyvault secret show --vault-name ${clusterName}akv -n DEV-PGPORT --query value | tr -d '"')
    pgUser=$(az keyvault secret show --vault-name ${clusterName}akv -n DEV-PGUSER --query value | tr -d '"')
    pgPassword=$(az keyvault secret show --vault-name ${clusterName}akv -n DEV-PGPASSWORD --query value | tr -d '"')

    # write env vars from akz into api .venv env
    echo '' >>api/.venv/bin/activate
    echo "export SECRET_KEY='"$djangoSecret"'" >>api/.venv/bin/activate
    echo "export DOMAIN='"$domain"'" >>api/.venv/bin/activate
    echo "export DEBUG=$debug" >>api/.venv/bin/activate
    echo "export PGDATABASE='"$pgDatabase"'" >>api/.venv/bin/activate
    echo "export PGHOST='"$pgHost"'" >>api/.venv/bin/activate
    echo "export PGPORT='"$pgPort"'" >>api/.venv/bin/activate
    echo "export PGUSER='"$pgUser"'" >>api/.venv/bin/activate
    echo "export PGPASSWORD='"$pgPassword"'" >>api/.venv/bin/activate

    # make the k8s secrets
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
    echo ""
    echo "Done."
}

setup() {
    echo "Creating cluster from scratch..."
    # create minikube container for the project (change --kuberentes-version as necessary)
    minikube -p $clusterName start --kubernetes-version=$k8sVersion --driver=$driver

    # call the function where the bulk of the setup resides
    standardSetup
}

refresh() {
    echo "Refreshing existing cluster..."
    # call the function where the bulk of the setup resides
    standardSetup
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
        echo "Cleaning cluster..."
        echo ""
        # set correct context
        kubectl config use-context $clusterName
        echo ""

        # deactivate the .venv env
        deactivate
        echo ""

        # delete secrets from the cluster
        kubectl delete secrets ${clusterName}-dev-secrets -n development
        echo ""

        # delete storage from the cluster
        kubectl delete -f k8s/storage/development.yaml -n development
        echo ""

        # delete local dependencies
        rm -rf client/node_modules admin/node_modules api/.venv
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
        echo "Destroying cluster..."
        echo ""
        # set the correct context
        kubectl config use-context ${clusterName}
        echo ""

        # deactivate the .venv env
        deactivate
        echo ""

        # delete the minikube cluster
        minikube delete -p ${clusterName}
        echo ""

        # delete local dependencies
        rm -rf client/node_modules admin/node_modules api/.venv
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
    echo "This is not a valid option."
    ;;
esac
