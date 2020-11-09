# Cheat sheet

```bash
# add the required helm repositories
helm repo add bitnami https://charts.bitnami.com/bitnami

# import the helm chart dependencies (e.g., PostgreSQL) from the xnat chart directory 
# ensure you have cloned the repo and changed to charts/xnat directory before running this command
helm dependency update

# view the helm output without deployment from the xnat chart directory
helm install --debug --dry-run xnat-dev . --values ./values-dev.yaml 2>&1 |less

# create xnat namespace in kubernetes
kubectl create namespace xnat

# Deploy and upgrade from the xnat chart directory
helm upgrade xnat . --install --values ./values-dev.yaml --namespace xnat

# watch it all happen, at least most of it
watch kubectl -nxnat get all

# watch the logs scroll by
kubectl -nxnat logs xnat-xnat-web-0 -f

# find out what happened if pod does not start
kubectl -nxnat get pod xnat-xnat-web-0 -o json

# view the persistent volumes
kubectl -nxnat get pvc,pv

# view the content of a secret
kubectl -nxnat get secret xnat-xnat-web -o go-template='{{ index .data "xnat-conf.properties" }}' | base64 -d

# tear it all down
helm delete xnat -nxnat
```

# Tool chain(s)

## Development

Shortcuts - Ansible playbooks

* contrib/ansible/playbooks/development.yaml

### Helm client

```bash
sudo snap install helm --classic
```

### [microk8s](https://microk8s.io/)


```bash
sudo snap install microk8s --classic
microk8s enable dns fluentd ingress metrics-server prometheus rbac registry storage

# Install and configure the kubectl client
sudo snap install kubectl --classic
# Start running more than one cluster and you will be glad you did these steps
microk8s config |sed 's/\(user\|name\): admin/\1: microk8s-admin/' >${HOME}/.kube/microk8s.config
cat >>${HOME}/.profile <<'EOT'
DIR="${HOME}/.kube"
if [ -d "${DIR}" ]; then
  KUBECONFIG="$(/usr/bin/find $DIR \( -name 'config' -o -name '*.config' \) \( -type f -o -type l \) -print0 | tr '\0' ':')"
  KUBECONFIG="${KUBECONFIG%:}"
  export KUBECONFIG
fi
EOT
# logout or run the above code in your current shell to set the KUBECONFIG environment variable
kubectl config use-context microk8s
```

If you have an issue with the operation of microk8s `microk8s inspect` command is you best friend.

### NixOS + Minikube

```bash
# Configure environment
cat <<EOF > default.nix
{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    minikube
    kubernetes-helm
  ];

  shellHook = ''
    alias kubectl='minikube kubectl'
    . <(minikube completion bash)
    . <(kubectl completion bash)
    . <(helm completion bash)
  '';
}
EOF
nix-shell

minikube start

# Will block the terminal, will need to open a new one
minikube dashboard

# Creates "default-http-backend"
minikube addons enable ingress
```

## CI/CD

| [Kind](https://github.com/kubernetes-sigs/kind) | Tool for running local Kubernetes clusters using Docker container "nodes" | Testing chart functionality |

# References (Must reads!)

* [The Chart Best Practices Guide](https://helm.sh/docs/chart_best_practices/)
* [Best Practices for Creating Production-Ready Helm charts](https://docs.bitnami.com/tutorials/production-ready-charts/)
* [Open Source Initiative licenses](https://opensource.org/licenses)
