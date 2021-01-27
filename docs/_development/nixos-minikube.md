## NixOS + Minikube

```bash
# Configure environment
cat <<EOF > default.nix
{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    minikube
    kubernetes-helm
    jq
  ];

  shellHook = ''
    alias kubectl='minikube kubectl'
    . <(minikube completion bash)
    . <(helm completion bash)

    # kubectk and docker completion require the control plane to be running
    if [ $(minikube status -o json | jq -r .Host) = "Running" ]; then
            . <(kubectl completion bash)
            . <(minikube -p minikube docker-env)
    fi
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

