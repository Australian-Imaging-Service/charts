# XNAT-web

## Parameters

## ActiveMQ (Issue #175)

This chart can inject Spring ActiveMQ client configuration into the XNAT web pod.

For Kubernetes ServiceAccount JWT authentication (OAuth/Bearer-style), set:

- `activemq.enabled=true`
- `activemq.auth.mode=serviceAccountJwt`

The chart will mount a projected ServiceAccount token at `activemq.auth.serviceAccountJwt.tokenPath` and start Tomcat with `SPRING_ACTIVEMQ_PASSWORD` loaded from that file.

Notes:
- Kubernetes will automatically rotate the projected token file.
- The application must reconnect/reload credentials to fully benefit from token rotation.


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
| `dicom_scp.serviceType                      | DICOM C-STORE Service Class Provider (SCP) service type (NodePort|LoadBalancer)      | `NodePort` |
| `dicom_scp.recievers.ae_title`              |                                                                                      | `XNAT` |
| `dicom_scp.recievers.port`                  |                                                                                      | `8104` |
| `dicom_scp.recievers.nodePort`              |                                                                                      | `nil` |
