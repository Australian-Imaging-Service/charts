---
title: "External PGSQL DB Connection"
weight: 10
---

# Connecting AIS XNAT Helm Deployment to an External Postgresql Database

By default, the AIS XNAT Helm Deployment creates a Postgresql database in a separate pod to be run locally on the cluster.  
If the deployment is destroyed the data in the database is lost. This is fine for testing purposes but unsuitable for a production environment.  
Luckily a mechanism was put into the Helm template to allow connecting to an External Postgresql Database.  



## Updating Helm charts values files to point to an external Database

Firstly, clone the AIS Charts Helm template:

```bash
git clone https://github.com/Australian-Imaging-Service/charts.git
```




### values-dev.yaml

This file is located in `charts/releases/xnat`

Current default configuration:

```yaml
global:
  postgresql:
    postgresqlPassword: "xnat"

postgresql:
  enabled: true
postgresqlExternalName: ""
postgresqlExternalIPs:
  - 139.95.25.8
  - 130.95.25.9
```

these lines:  

`postgresql:
   enabled: true`

Needs to be changed to `false` to disable creation of the Postgresql pod and create an external database connection.

The other details are relatively straightforward - Generally you would only specify either:  
`postgresqlExternalName` or `postgresqlExternalIPs`  
`postgresqlPassword` will be your database user password.

An example configuration using a sample AWS RDS instance would look like this:

```yaml
global:
  postgresql:
    postgresqlPassword: "yourpassword"

postgresql:
  enabled: false
postgresqlExternalName: "xnat.randomstring.ap-southeast-2.rds.amazonaws.com"
```


### Top level values.yaml

This file is also located in `charts/releases/xnat`

Current default configuration:

```yaml
global:
  postgresql:
    postgresqlDatabase: "xnat"
    postgresqlUsername: "xnat"
    #postgresqlPassword: ""
    #servicePort: ""

postgresql:
  enabled: true
postgresqlExternalName: ""
postgresqlExternalIPs: []
```

An example configuration using a sample AWS RDS instance would look like this:

```yaml
global:
  postgresql:
    postgresqlDatabase: "yourdatabase"
    postgresqlUsername: "yourusername"
    postgresqlPassword: "yourpassword"
    

postgresql:
  enabled: false
postgresqlExternalName: "xnat.randomstring.ap-southeast-2.rds.amazonaws.com"
```

Please change the database, username, password and External DNS (or IP) details to match your environment.


### xnat-web values.yaml

This file is also located in `charts/releases/xnat/charts/xnat-web`


Current default configuration:

```yaml
postgresql:
  postgresqlDatabase: "xnat"
  postgresqlUsername: "xnat"
  postgresqlPassword: "xnat"
```


Change to match your environment as with the other values.yaml.  

You should now be able to connect your XNAT application Kubernetes deployment to your external Postgresql DB to provide a suitable environment for production.

For more details about deployment have a look at the README.md here:  
`https://github.com/Australian-Imaging-Service/charts/tree/main/releases/xnat`



## Creating an encrypted connection to an external Postgresql Database


The database connection string for XNAT is found in the XNAT home directory - usually  
`/data/xnat/home/config/xnat-conf.properties`


By default the connection is unencrypted. If you wish to encrypt this connection you must append to the end of the Database connection string.

Usual string:  
`datasource.url=jdbc:postgresql://xnat-postgresql/yourdatabase`

Options:  
| Option                                               | Description                                        |
|------------------------------------------------------|----------------------------------------------------|
| `ssl=true`                                           | use SSL encryption                                 |
| `sslmode=require`                                    | require SSL encryption                             |
| `sslfactory=org.postgresql.ssl.NonValidatingFactory` | Do not require validation of Certificate Authority |

The last option is useful as otherwise you will need to import the CA cert into your Java keystone on the docker container.  
This means updating and rebuilding the XNAT docker image before being deployed to the Kubernetes Pod and this can be impractical.


Complete string would look like this ( all on one line):  
`datasource.url=jdbc:postgresql://xnat-postgresql/yourdatabase?ssl=true&sslmode=require&sslfactory=org.postgresql.ssl.NonValidatingFactory`


### Update your Helm Configuration:

Update the following line in `charts/releases/xnat/charts/xnat-web/templates/secrets.yaml` from:  

`datasource.url=jdbc:postgresql://{{ template "xnat-web.postgresql.fullname" . }}/{{ template "xnat-web.postgresql.postgresqlDatabase" . }}`  

to:

`datasource.url=jdbc:postgresql://{{ template "xnat-web.postgresql.fullname" . }}/{{ template "xnat-web.postgresql.postgresqlDatabase" . }}?ssl=true&sslmode=require&sslfactory=org.postgresql.ssl.NonValidatingFactory`



Then deploy / redeploy.


{{% alert %}}
It should be noted that the Database you are connecting to needs to be encrypted in the first place for this to be successful.

This is outside the scope of this document.
{{% /alert %}}

