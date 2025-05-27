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

## Microk8s minimal enabled plugins

```bash
microk8s enable dns
microk8s enable rbac
microk8s enable storage
```

## What settings can be modified and where?

```bash
helm show values ais/xnat
```

## Just XNAT

Create minimal helm values file `~/values.yaml`.

XNAT requires a minimum of 4GiB of RAM and 4x vCPUs. If your system is close to or smaller than these resources
then XNAT could take several minutes to start. If so, it is recommended that you add something similar to the settings
bellow for your deployment.

As an example, a test conducted (27/5/2025) on a VM with 4GiB of RAM and 4x vCPUs, took just over 6.5 minutes
for XNAT to start and present a healthy system.

```yaml
---
xnat-web:
  resources:
    requests:
      memory: 500Mi
    limits:
      memory: 3000Mi # 1 GiB lower than your system.
  probes:
    startup:
      failureThreshold: 120 # Disables the process watchdog for an extended period of time.
```

```bash
# Setup AIS Helm charts
helm repo add ais https://australian-imaging-service.github.io/charts
helm repo update

# Deploy minimal XNAT
# This command is also used to action changes to the `values.yaml` file
helm upgrade xnat ais/xnat --install --values ~/values.yaml --namespace xnat-demo --create-namespace

# From another terminal you can run the following commnad to watch deployment of resources
watch kubectl -nxnat-demo get all,pv,pvc

# From another terminal run the following command and
# access XNAT web UI from a browser with address `http://localhost:8080`
kubectl -nxnat-demo port-forward service/xnat-xnat-web-0 8080:80
```

Things to watch out for.
* This deployment will utilise the default storage class configured for your Kubernetes service.
  If there is no storage class set as default this deployment will not have any persistent volume(s)
  provisioned and will not complete.
  Out of scope for this document is how to manually create a Persistent Volume and bind to a Persistent Volume Claim.

```bash
kubectl get sc
```
```
NAME                          PROVISIONER            RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
microk8s-hostpath (default)   microk8s.io/hostpath   Delete          Immediate           false                  145d
```
You can see that Microk8s has a default storage class. However if this was not the case or another storage class was to be used the following would need to be added to your `values.yaml` file.

```yaml
---
global:
  storageClass: "microk8s-hostpath"
```

You should be seeing something similar to the following

```
$ kubectl -nxnat-demo get all,pvc
NAME                    READY   STATUS    RESTARTS   AGE
pod/xnat-postgresql-0   1/1     Running   30         27d
pod/xnat-xnat-web-0     1/1     Running   30         27d

NAME                               TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
service/xnat-xnat-web-headless     ClusterIP   None             <none>        80/TCP           27d
service/xnat-postgresql-headless   ClusterIP   None             <none>        5432/TCP         27d
service/xnat-postgresql            ClusterIP   10.152.183.17    <none>        5432/TCP         27d
service/xnat-xnat-web              ClusterIP   10.152.183.193   <none>        80/TCP           27d
service/xnat-xnat-web-dicom-scp    NodePort    10.152.183.187   <none>        8104:31002/TCP   27d

NAME                               READY   AGE
statefulset.apps/xnat-postgresql   1/1     27d
statefulset.apps/xnat-xnat-web     1/1     27d

NAME                                             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS        AGE
persistentvolumeclaim/xnat-xnat-web-archive      Bound    pvc-81a7308c-fb64-4acd-9a04-f54dbc6e1e0b   1Ti        RWX            microk8s-hostpath   27d
persistentvolumeclaim/xnat-xnat-web-prearchive   Bound    pvc-357f45aa-79af-4958-a3fe-ec3714e6db13   1Ti        RWX            microk8s-hostpath   27d
persistentvolumeclaim/data-xnat-postgresql-0     Bound    pvc-45d917d7-8660-4183-92cb-0e07c59d9fa7   8Gi        RWO            microk8s-hostpath   27d
persistentvolumeclaim/cache-xnat-xnat-web-0      Bound    pvc-f868215d-0962-4e99-95f5-0cf09440525f   10Gi       RWO            microk8s-hostpath   27d
```
