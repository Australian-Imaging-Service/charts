---
layout: default
title: "XNAT chart README"
---

```bash
# add the required helm repositories
helm repo add bitnami https://charts.bitnami.com/bitnami

# import the helm chart dependencies (e.g., PostgreSQL) from the xnat chart directory
# ensure you have cloned the repo and changed to charts/xnat directory before running this command
helm dependency update

# view the helm output without deployment from the xnat chart directory
helm install --debug --dry-run xnat ais/xnat  2>&1 |less

# create xnat namespace in kubernetes
kubectl create ns xnat

# Deploy the AIS XNAT service
helm upgrade xnat ais/xnat --install --values ./my-site-overrides.yaml --namespace xnat

# Watch the AIS goodness
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
kubectl -nxnat delete pod,svc,pvc --all
kubectl delete namespace xnat

```

