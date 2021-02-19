#!/bin/bash
# create minikube container for the project (change --kuberentes-version as necessary)
minikube -p $(basename $PWD) start --kubernetes-version=1.19.7 --driver=docker 

# switch to correct context (should happen automatically, but just in case)
kubectl config use-context $(basename $PWD) 

# apply ingress nginx controller settings
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.44.0/deploy/static/provider/cloud/deploy.yaml 

# create development namespace in kubectl
kubectl create ns development 

# create storage for postgresql and files
kubectl apply -f k8s/storage/development.yaml 

# make sure using correct node version (change as necessary)
nvm install 14 
nvm use 14 

# move into api and create virtualenv
cd api 
virtualenv -p python3 .venv 

# activate the .venv
source .venv/bin/activate 

# install api dependencies
pip install -r requirements.txt

# go into the client and install dependencies
cd ../client 
npm install 

# go into the  and install dependencies
cd ../admin 
npm install 

# navigate back to project root
cd .. 

# get necessary env vars from akv
djangoSecret=$(az keyvault secret show --vault-name k8stutakv -n DEV-DJANGOSECRETKEY --query value | tr -d '"') 
pgDatabase=$(az keyvault secret show --vault-name k8stutakv -n DEV-PGDATABASE --query value  | tr -d '"') 
pgPort=$(az keyvault secret show --vault-name k8stutakv -n DEV-PGPORT --query value  | tr -d '"') 
pgUser=$(az keyvault secret show --vault-name k8stutakv -n DEV-PGUSER --query value  | tr -d '"') 
pgPassword=$(az keyvault secret show --vault-name k8stutakv -n DEV-PGPASSWORD --query value  | tr -d '"') 

# write env vars from akz into api .venv env
echo '' >> api/.venv/bin/activate
echo "export DEBUG=True" >> api/.venv/bin/activate
echo "export SECRET_KEY='"$djangoSecret"'" >> api/.venv/bin/activate
echo "export PGDATABASE='"$pgDatabase"'" >> api/.venv/bin/activate
echo "export PGHOST='localhost" >> api/.venv/bin/activate
echo "export PGPORT='"$pgPort"'" >> api/.venv/bin/activate
echo "export PGUSER='"$pgUser"'" >> api/.venv/bin/activate
echo "export PGPASSWORD='"$pgPassword"'" >> api/.venv/bin/activate
echo "export DOMAIN='localhost'" >> api/.venv/bin/activate

# make the k8s secrets 
kubectl create secret generic k8stut-dev-secrets \
--from-literal=DEBUG=True \
--from-literal=SECRET_KEY=$djangoSecret \
--from-literal=PGDATABASE=$pgDatabase \
--from-literal=PGHOST=localhost \
--from-literal=PGPORT=$pgPort \
--from-literal=PGUSER=$pgUser \
--from-literal=PGPASSWORD=$pgPassword \
--from-literal=DOMAIN=localhost \
-n development