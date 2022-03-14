---
title: XNAT Quick Start Guide
description: Getting started with an XNAT deployment step-by-step
draft: false
---

This quick start guide will follow a progression starting from the most basic single instance XNAT deployment
up to a full XNAT service.

Please be aware that this is a guide and not considered a production ready service.

## Prerequisites

* a Kubernetes service. You can use Microk8s on your workstation if you do not have access to a cloud service.
* Kubectl client installed and configured to access your Kubernetes service
* Helm client installed

## Just XNAT

Create minimal helm values file `~/values.yaml`

```yaml
---
global:
  postgresql:
    postgresqlPassword: "xnat"
```

```bash
# Setup AIS Helm charts
helm repo add ais https://australian-imaging-service.github.io/charts
helm repo update

# Deploy minimal XNAT
helm upgrade xnat ais/xnat --install --values ~/values.yaml --namespace xnat-demo --create-namespace

# Watch deployment
watch kubectl -nxnat-demo get all,pv,pvc

# From another terminal run the following command and
# access XNAT web UI from a browser with address `http://localhost:8080`
kubectl -nxnat-demo port-forward service/xnat-xnat-web-0 8080:80
```

Things to watch out for.
* This deployment will utilise the default storage class configured for your Kubernetes service.
  If there is no storage class set as default this deployment will not have any persistent volume(s)
  provisioned and will not complete.
