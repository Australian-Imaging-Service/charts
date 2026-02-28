# Charts Quick Start

This repository contains Helm charts and deployment documentation.

## Prerequisites

You need:

- A Kubernetes cluster with:
  - internal DNS provider
  - Ingress controller
  - RBAC enabled
  - default StorageClass for persistent volumes
- A workstation with:
  - `kubectl` configured for your cluster
  - `helm` installed

## Helm repository setup

```bash
# Add the AIS chart repository
helm repo add ais https://australian-imaging-service.github.io/charts
helm repo update
```

## Deploy XNAT

```bash
# Create namespace (idempotent)
kubectl create namespace xnat --dry-run=client -o yaml | kubectl apply -f -

# Install/upgrade release
helm upgrade --install xnat ais/xnat \
  --values ./my-site-overrides.yaml \
  --namespace xnat

# Watch resources
watch kubectl -n xnat get all
```

## Deploy Clinical Trials Processor (CTP)

```bash
# Create namespace (idempotent)
kubectl create namespace ctp --dry-run=client -o yaml | kubectl apply -f -

# Install/upgrade release
helm upgrade --install ctp ais/ctp \
  --values ./my-ctp-site-overrides.yaml \
  --namespace ctp

# Watch resources
watch kubectl -n ctp get all
```

## Next steps

- Charts and deployment docs: `docs/`
- Contribution process: `CONTRIBUTING.md`
- AIS docs: <https://australian-imaging-service.github.io/docs/>
