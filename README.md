# Quick start

Requires:

* existing Kubernetes (k8s) service with the following:
  * internal DNS provider
  * Ingress controller
  * Role Based Access Control (RBAC)
  * default Storage Class for persistent volumes
* Workstation with the following:
  * `kubectl` client configured to control your k8s service
  * `helm` client

Helm client configuration

```bash
# Add the AIS helm chart repository
helm repo add ais https://australian-imaging-service.github.io/charts
helm repo update
```

Deploy XNAT

```bash
# Create a namespace and deploy the AIS XNAT service
kubectl create namespace xnat
helm upgrade xnat ais/xnat --install --values ./my-site-overrides.yaml --namespace xnat

# Watch the AIS goodness
watch kubectl -nxnat get all
```

Deploy Clinical Trials Processor (CTP)

```bash
# Create a namespace and deploy the AIS CTP service
kubectl create namespace ctp
helm upgrade ctp ais/ctp --install --values ./my-ctp-site-overrides.yaml --namespace ctp

# Watch the AIS goodness
watch kubectl -nctp get all
```

For more information refer to the [AIS Dev Documentation](https://australian-imaging-service.github.io/docs/)
