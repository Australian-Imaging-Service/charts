# XNAT-web

## Parameters

The following tables list the configuration parameters of the XNAT-web Chart and their default values.

| Parameter                                   | Description                                                                          | Default |
| ------------------------------------------- | ------------------------------------------------------------------------------------ | --- |
| `global.imageRegistry`                      | Global Docker Image registry                                                         | `nil` |
| `global.imagePullSecrets`                   | Global Docker registry secret names as an array                                      | `[]` (does not add image pull secrets to deployed pods) |
| `global.postgresql.postgresqlDatabase`      | PostgreSQL database (overrides `postgresql.postgresqlDatabase`)                      | `nil` |
| `global.postgresql.postgresqlUsername`      | PostgreSQL username (overrides `postgresql.postgresqlUsername`)                      | `nil` |
| `global.postgresql.postgresqlPassword`      | PostgreSQL admin password (overrides `postgresql.postgresqlPassword`)                | `nil` |
| `global.postgresql.servicePort`             | PostgreSQL port (overrides `postgresql.service.port`)                                | `nil` |
| For more PostgreSQL detail and configuration options please visit the official [Bitnami Chart repository](https://github.com/bitnami/charts/tree/master/bitnami/postgresql). |||
| `global.storageClass`                       | Global storage class for dynamic provisioning                                        | `nil` |
| `volumes.archive.existingClaim`    | | |
| `volumes.archive.mountPath`        | Archive path propagated to XNAT setup (`archivePath`)                                | `/data/xnat/archive` |
| `volumes.prearchive.existingClaim` | | |
| `volumes.prearchive.mountPath`     | Prearchive path propagated to XNAT setup (`prearchivePath`)                          | `/data/xnat/prearchive` |
| `persistence.cache.mountPath`      | Cache path propagated to XNAT setup (`cachePath`)                                    | `/data/xnat/cache` |
| `dicom_scp.serviceType                      | DICOM C-STORE Service Class Provider (SCP) service type (NodePort|LoadBalancer)      | `NodePort` |
| `dicom_scp.recievers.ae_title`              |                                                                                      | `XNAT` |
| `dicom_scp.recievers.port`                  |                                                                                      | `8104` |
| `dicom_scp.recievers.nodePort`              |                                                                                      | `nil` |
