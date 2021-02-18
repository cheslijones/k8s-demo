minikube -p $(basename $PWD) start --kubernetes-version=1.19.7 --driver=docker 
kubectl config use-context $(basename $PWD)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.44.0/deploy/static/provider/cloud/deploy.yaml
kubectl create ns development
kubectl apply -f k8s/storage/development.yaml
nvm install 14
nvm use 14
cd api
virtualenv -p python3 .venv
source .venv/bin/activate
pip install requirements.txt
cd ../client
npm install
cd ../admin
npm install
cd ..
