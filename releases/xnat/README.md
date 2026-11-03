# XNAT

[XNAT](https://www.xnat.org/) is an open source imaging informatics platform developed by the Neuroinformatics Research Group at Washington University. XNAT was originally developed at Washington University in the Buckner Lab, which is now located at Harvard University. It facilitates common management, productivity, and quality assurance tasks for imaging and associated data.

```bash
$ helm repo add ais https://australian-imaging-service.github.io/charts
$ helm upgrade xnat ais/xnat --install
```

## Introduction

## Prerequisites

- Kubernetes 1.12+
- Helm 3.0-beta3+
- Persistent Volume (PV) provisioner support in the underlying infrastructure

## Installing the chart

To install the chart with the release name my-xnat

Minimum values file required.

xnat_values.yaml
```yaml
postgresql:
  auth:
    password: CHANGEME
```

```bash
$ helm upgrade my-xnat ais/xnat --install -f xnat_values.yaml
```

The command deploys XNAT on the Kubernetes cluster in the default configuration. The [Parameters](#parameters) section lists the parameters that can be configured during installation.

Note: From chart 1.1.16, dependent Bitnami PostgreSQL engine is upgraded to 16.4.0 from 11.14.0. If you use internal PostgreSQL, you need to create a full backup of your existing database before upgrade, afterwards restore it to the upgraded database. If your chart is configured to connect to an external PostgreSQL database (not managed by the Bitnami subchart), this message is less directly relevant to your database upgrade process.

## Uninstalling the chart

To uninstall/delete the my-xnat deployment

```bash
$ helm delete my-xnat
```

The command removes all the kubernetes components but the Persistent Volume Claims (PVC) associated with the chart and deletes the release.

To delete the PVC's associated with `my-xnat`:

> **WARNING**: Deleting the PVC's will delete all the associated data. Perform this action with the utmost care and consideration, there is no turning back.

```bash
kubectl delete pvc -l release=my-xnat
```

## Parameters

The following tables list the configuration parameters of the XNAT Chart and their default values.

| Parameter                                   | Description                                                                          | Default |
| ------------------------------------------- | ------------------------------------------------------------------------------------ | --- |
| `global.imageRegistry`                      | Global Docker Image registry                                                         | `nil` |
| `global.imagePullSecrets`                   | Global Docker registry secret names as an array                                      | `[]` (does not add image pull secrets to deployed pods) |
| `global.postgresql.postgresqlDatabase`      | PostgreSQL database (overrides `postgresql.postgresqlDatabase`)                      | `xnat` |
| `global.postgresql.postgresqlUsername`      | PostgreSQL username (overrides `postgresql.postgresqlUsername`)                      | `xnat` |
| `global.postgresql.postgresqlPassword`      | PostgreSQL admin password (overrides `postgresql.postgresqlPassword`)                | `""` WARNING: A complex value must be provided for security |
| `global.postgresql.servicePort`             | PostgreSQL port (overrides `postgresql.service.port`)                                | `nil` |
| For more *PostgreSQL* detail and configuration options please visit the official [Bitnami Chart repository](https://github.com/bitnami/charts/tree/master/bitnami/postgresql). |||
| `global.storageClass`                       | Global storage class for dynamic provisioning                                        | `nil` |
| `postgresql.enabled`                         | Deploy PostgreSQL as part of this Charts deployment, else provide external ref.      | `true` |
| `postgresqlExternalHostname`                | Hostname of an external database if `postgresql.enabled`=`false`                      | `nil` |
| `postgresqlExternalIPs`                     | Hostname of an external database if `postgresql.enabled`=`false`                      | `nil` |
| `xnat-web.volumes.archive.existingClaim`    | | |
| `xnat-web.volumes.prearchive.existingClaim` | | |

## Pipeline reconciler

The optional pipeline reconciler synchronises pipeline commands from the AIS
pipeline catalogue into XNAT. It is disabled by default.

The pipeline reconciler requires:

- Kubernetes 1.21+
- The XNAT Container Service plugin and a configured Container Service backend
- An XNAT account with permission to manage Container Service commands
- Outbound access to `github.com`, release-download redirect hosts, and `ghcr.io`

| Parameter (under `xnat-web.pipelineReconciler`) | Description | Default |
| --- | --- | --- |
| `enabled` | Render the CronJob and its configuration ConfigMap | `false` |
| `image.repository` | Reconciler container image | `ghcr.io/australian-imaging-service/pipelines-reconciler` |
| `image.tag` | Reconciler image tag | `"26.10.0"` |
| `schedule` | Cron schedule, in the controller's timezone | `"0 2 * * 0"` |
| `xnatHost` | XNAT URL override, reachable from the Pod | `http://<xnat-web Service name>:<service.port>` |
| `existingSecret` | Required Secret containing `XNAT_USER` and `XNAT_PASS` | `""` |
| `config` | YAML configuration: `include`, `exclude`, and `enablement` | `{}` |

Enable the Container Service plugin in the XNAT values file:

```yaml
xnat-web:
  plugins:
    container-service: []
```

Create a Secret containing the XNAT credentials in the same namespace as the
XNAT release:

```bash
$ read -r -p "XNAT username: " XNAT_USER
$ read -r -s -p "XNAT password: " XNAT_PASS
$ printf '\n'

$ kubectl --namespace xnat apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: xnat-reconciler-auth
type: Opaque
stringData:
  XNAT_USER: "${XNAT_USER}"
  XNAT_PASS: "${XNAT_PASS}"
EOF

$ unset XNAT_USER XNAT_PASS
```

Configure the pipeline reconciler in the XNAT values file:

```yaml
xnat-web:
  plugins:
    container-service: []
  pipelineReconciler:
    enabled: true
    image:
      tag: "26.10.0"
    schedule: "0 2 * * 0"
    existingSecret: xnat-reconciler-auth
    config:
      enablement: approval
```

The default schedule checks the pipeline catalogue each Sunday at 02:00 in the
Kubernetes controller's timezone. The `approval` enablement setting imports new
commands without enabling them. Set it to `auto` to enable imported commands
automatically.

The `config.include` and `config.exclude` values are lists of pipeline ID glob
patterns. If neither value is specified, all catalogue pipelines are selected.

To run the reconciler immediately and follow its logs:

```bash
$ CRONJOB_NAME="$(kubectl --namespace xnat get cronjob \
  --selector app.kubernetes.io/component=pipeline-reconciler \
  --output jsonpath='{.items[0].metadata.name}')"
$ JOB_NAME="${CRONJOB_NAME}-manual-$(date +%s)"
$ kubectl --namespace xnat create job \
  --from="cronjob/${CRONJOB_NAME}" \
  "${JOB_NAME}"
$ kubectl --namespace xnat logs --follow --pod-running-timeout=2m "job/${JOB_NAME}"
```
