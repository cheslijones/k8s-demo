kubectl config use-context $(basename $PWD)
minikube delete -p $(basename $PWD)
deactivate
# kubectl delete secrets cronerapp-dev-secrets
# kubectl delete -f k8s/storage/development.yaml
rm -rf client/node_modules admin/node_modules api/.venv