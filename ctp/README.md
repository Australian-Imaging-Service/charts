# Clinical Trials Processor (CTP)

## Parameters

The following tables list the configuration parameters of the CTP Chart and their default values.

| Parameter                                   | Description                                                                          | Default |
| ------------------------------------------- | ------------------------------------------------------------------------------------ | --- |
| `users`                                     | Dictionary of user accounts                                                          | `{}` | 
| `users.NAME.password`                       | Users password string                                                                | `nil` |
| `users.NAME.roles`                          | List of roles (admin, delete, guest, import, export, proxy, qadmin, shutdown)        | `nil` |
| `timezone`                                  | Local timezone string (e.g., Australia/Perth)                                        | `nil` |
| `pipelines`                                 | Dictionary of configured pipelines                                                   | `{}` |
| `pipelines.NAME.desc`                       | Description of pipeline string
| `pipelines.NAME.stages`                     | List of pipeline stages
| `pipleines.NAME.stages.name`
| `pipleines.NAME.stages.root`
| `pipleines.NAME.stages.port`
| `pipleines.NAME.stages.quarantine`
| `pipleines.NAME.stages.raw_content`         | Raw value to apply as stage tag content | `nil` |
| `proxyServer.ipAddress`
| `proxyServer.port`
| `proxyServer.username`
| `proxyServer.password`
| `volumes`                                   | Dictionary of Persistent Volumes | `roots`, `quarantines` |
| `volumes.NAME.accessMode`
| `volumes.NAME.existingClaim`
| `volumes.NAME.mountPath`
| `volumes.NAME.storageClassName`
| `volumes.NAME.size`

