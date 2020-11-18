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
| `volumes.prearchive.existingClaim` | | |
