---
title: "Logging With EFK"
weight: 10
---

## EFK centralized logging collecting and monitoring
For AIS deployment, we use EFK stack on Kubernetes for log aggregation, monitoring and anyalysis. EFK is a suite of 3 different tools combining Elasticsearch, Fluentd and Kibana. 

Elasticsearch nodes form a cluster as the core. You can run single node Elasticsearch. However, a high availablity Elasticsearch cluster requires 3 master nodes as a minimum. If there is one node fails, the Elasticsearch cluster still functions and can self heal. 

Kibana instance is used as the visualisation tool for users to interact with the Elasticsearch cluster. 

Fluentd is used as the log collector.

In the following guide, we leverage Elastic and Fluentd's official Helm charts before using Kustomize to customize other required K8s resources. 

### Creating a new namespace for EFK
```bash
$ kubectl create ns efk
```

### Add official Helm repos

For both Elasticsearch and Kibana:

```
$ helm repo add elastic https://helm.elastic.co
```
As of this writing, the latest helm repo supports Elasticsearch 7.17.3. It doesn't work with the latest Elasticsearch v8.3 yet. 

For Fluentd:
```
$ helm repo add fluent https://fluent.github.io/helm-charts
```

### Install Elaticsearch

Adhere to the Elasticsearch security principles, all traffic between nodes in Elasticsearch cluster and traffic between the clients to the cluster needs to be encrypted. You use self signed certicate in this guide. 

#### Generating self signed CA and certificates

* Below we use elasticsearch-certutil to generate password protected self signed CA and certificates, then use openssl tool to convert it to pem formatted certificate

```
$ docker rm -f elastic-helm-charts-certs || true
$ rm -f elastic-certificates.p12 elastic-certificate.pem elastic-certificate.crt elastic-stack-ca.p12 || true
$ docker run --name elastic-helm-charts-certs -i -w /tmp docker.elastic.co/elasticsearch/elasticsearch:7.16.3 \
/bin/sh -c " \
  elasticsearch-certutil ca --out /tmp/elastic-stack-ca.p12 --pass 'Changeme' && \
  elasticsearch-certutil cert --name security-master --dns security-master --ca /tmp/elastic-stack-ca.p12 --pass 'Changeme' --ca-pass 'Changeme' --out /tmp/elastic-certificates.p12" && \
docker cp elastic-helm-charts-certs:/tmp/elastic-stack-ca.p12 ./ && \
docker cp elastic-helm-charts-certs:/tmp/elastic-certificates.p12 ./ && \
docker rm -f elastic-helm-charts-certs && \
openssl pkcs12 -nodes -passin pass:'Changeme' -in elastic-certificates.p12 -out elastic-certificate.pem
openssl pkcs12 -nodes -passin pass:'Changeme' -in elastic-stack-ca.p12 -out elastic-ca-cert.pem

```

* Convert the generated CA and certificates to based64 encoded format. These will be used to create the secrets in K8s. Alternatively, you can use kubectl to create the secrets directly

```
$ base64 -i elastic-certificates.p12 -o elastic-certificates-base64
$ base64 -i elastic-stack-ca.p12 -o elastic-stack-ca-base64
```

* Generate base64 encoded format for passwords for keystore and truststore. 
```
$ echo -n Changeme | base64 > store-password-base64
```

#### Create Helm custom values file elasticsearch.yml

* Creating 3 master nodes Elasticsearch cluster named "elasticsearch". 
```
clusterName: elasticsearch
replicas: 3
minimumMasterNodes: 2
```

* Specify the compute resources you allocate to Elasticsearch pod
```
resources:
  requests:
    cpu: "1000m"
    memory: "2Gi"
  limits:
    cpu: "1000m"
    memory: "2Gi"
```
* Specify the password for the default super user 'elastic'
```
secret:
  enabled: false
  password: Changeme
```

* Specify the protocol used for readniess probe. Use https for all traffic to the cluster on encypted link
```
protocol: https
```

* Disable the SSL certificate auto creation, we'll use self signed certificate created earlier
```
createCert: false
```

* Configuration for the volumeClaimTemplate for Elasticsearch statefulset. A customised storage class 'es-ais' will be defined by Kustomize
```
volumeClaimTemplate:
  accessModes: ["ReadWriteMany"]
  resources:
    requests:
      storage: 50Gi
  storageClassName: es-ais
```

* Mount the secret
```
secretMounts:
  - name: elastic-certificates
    secretName: elastic-certificates
    path: /usr/share/elasticsearch/config/certs
```

* Add configuration file elasticsearch.yaml. Enable transport TLS for internode encrypted communication and HTTP TLS for client encryped communication. Previously generated certificates are used, they are passed in from the mounted Secrets
```
esConfig:
  elasticsearch.yml: |
    xpack.security.enabled: true
    xpack.security.transport.ssl.enabled: true
    xpack.security.transport.ssl.verification_mode: certificate
    xpack.security.transport.ssl.client_authentication: required
    xpack.security.transport.ssl.keystore.path: /usr/share/elasticsearch/config/certs/elastic-certificates.p12
    xpack.security.transport.ssl.truststore.path: /usr/share/elasticsearch/config/certs/elastic-certificates.p12
    xpack.security.http.ssl.enabled: true
    xpack.security.http.ssl.keystore.path: /usr/share/elasticsearch/config/certs/elastic-certificates.p12
```

* Map secrets into the keystore
```
keystore:
  - secretName: transport-ssl-keystore-password
  - secretName: transport-ssl-truststore-password
  - secretName: http-ssl-keystore-password
```

* Supply extra environment varialbes. 
```
extraEnvs:
  - name: "ELASTIC_PASSWORD"
    value: Changeme
```

#### Kustomize for Elasticsearch
* Create Kustomize file kustomization.yaml
```
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - all.yaml
  - storageclass.yaml
  - secrets.yaml
```

* Create storageclass.yaml as referenced above. Below is the example when using AWS EFS as the persistent storage. You can adjust to suit your storage infrastructure. 
```
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: es-ais
provisioner: efs.csi.aws.com
mountOptions:
- tls
parameters:
  provisioningMode: efs-ap
  fileSystemId: YourEFSFileSystemId
  directoryPerms: "1000"
```

* Create secrets.yaml as referenced. Secrets created are used in the custom values file
```
apiVersion: v1
data:
  elastic-certificates.p12: CopyAndPasteValueOf-elastic-certificates-base64
kind: Secret
metadata:
  name: elastic-certificates
  namespace: efk
type: Opaque
---
apiVersion: v1
data:
  xpack.security.transport.ssl.keystore.secure_password: CopyAndPasteValueOf-store-password-base64
kind: Secret
metadata:
  name: transport-ssl-keystore-password
  namespace: efk
type: Opaque
---
apiVersion: v1
data:
  xpack.security.transport.ssl.truststore.secure_password: CopyAndPasteValueOf-store-password-base64
kind: Secret
metadata:
  name: transport-ssl-truststore-password
  namespace: efk
type: Opaque
---
apiVersion: v1
data:
  xpack.security.http.ssl.keystore.secure_password: CopyAndPasteValueOf-store-password-base64
kind: Secret
metadata:
  name: http-ssl-keystore-password
  namespace: efk
type: Opaque
```

#### Install Elasticsearch Helm chart
Change to where your Kustomize directory for Elasticsearch and run
```
$ helm upgrade -i -n efk es elastic/elasticsearch -f YourCustomValueDir/elasticsearch.yml --post-renderer ./kustomize
```

Wait till you will see all elasticsearch pods are in "running" status
```
$ kubectl get po -n efk -l app=elasticsearch-master
```

##
### Install Kibana
Kibana enables the visual analysis of data from Elasticsearch indecies. In this guide, we use single instance.

#### Create Helm custom values file kibana.yaml
* Specify the URL to connect to Elasticsearch. We use the service name and port configured in Elaticsearch
```
elasticsearchHosts: "https://elasticsearch-master:9200"
```

* Specify the protocol for Kibana's readiness check
```
protocol: https
```

* Add below kibana.yml configuration file that enables Kinana to talk to Elasticsearch on encrypted connection.
For xpack.security.encryptionKey, you can use any text string that is at least 32 characters. Certificates are mounted from the secret resource
```
kibanaConfig:
  kibana.yml: |
    server.ssl:
      enabled: true
      key: /usr/share/kibana/config/certs/elastic-certificate.pem
      certificate: /usr/share/kibana/config/certs/elastic-certificate.pem
    xpack.security.encryptionKey: Changeme
    elasticsearch.ssl:
      certificateAuthorities: /usr/share/kibana/config/certs/elastic-ca-cert.pem
      verificationMode: certificate
    elasticsearch.hosts: https://elasticsearch-master:9200
```

* Supply PEM formated Elastic certificate. These certificates will be used in kibana.yml in previous step
```
secretMounts:
  - name: elastic-certificates-pem
    secretName: elastic-certificates-pem
    path: /usr/share/kibana/config/certs
```

* Configure extra environment variables to pass to Kibana container on starting up. 
```
extraEnvs:
  - name: "KIBANA_ENCRYPTION_KEY"
    valueFrom:
      secretKeyRef:
        name: kibana
        key: encryptionkey
  - name: "ELASTICSEARCH_USERNAME"
    value: elastic
  - name: "ELASTICSEARCH_PASSWORD"
    value: changeme
```

* We expose Kibana as the NodePort service. 
```
service:
  type: NodePort
```

#### Kustomize for Kibana
* Define Secrets that is used in kibana.yml
```
apiVersion: v1
data:
  # use base64 format of values of elasticsearch's elastic-certificate.pem and elastic-ca-cert.pem
  elastic-certificate.pem: Changeme
  elastic-ca-cert.pem: Changme
kind: Secret
metadata:
  name: elastic-certificates-pem
  namespace: efk
type: Opaque
---
apiVersion: v1
data:
  # use base64 format of the value you use for xpack.security.encryptionKey 
  encryptionkey: Changeme
kind: Secret
metadata:
  name: kibana
  namespace: efk
type: Opaque
```

* Optional: create an Ingress resource to point to the Kibana serivce

#### Install/update the Kibana chart
Change to where your Kustomize directory for Kibana and run
```
$ helm upgrade -i -n efk kibana elastic/kibana -f YourCustomValueDirForKibana/kibana.yml --post-renderer ./kustomize
```
Wait till you will see the kibana pod is in "running" status
```
$ kubectl get po -n efk -l app=kibana
```

##
### Install Fluentd

#### Create a custom Helm values file fluentd.yaml
* Specify where to output the logs
```
elasticsearch:
  host: elasticsearch-master
```

#### Kustomize for Fluentd
* Create a ConfigMap that includes all Fluentd configuration files as below or you can use your own configuration files. 

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
data:
  01_sources.conf: |-
    ## logs from podman
    <source>
      @type tail
      @id in_tail_container_logs
      @label @KUBERNETES
      # path /var/log/containers/*.log
      path /var/log/containers/*.log
      pos_file /var/log/fluentd-containers.log.pos
      tag kubernetes.*
      read_from_head true
      <parse>
        @type multi_format
        <pattern>
          format json
          time_key time
          time_type string
          time_format "%Y-%m-%dT%H:%M:%S.%NZ"
          keep_time_key true
        </pattern>
        <pattern>
          format regexp
          expression /^(?<time>.+) (?<stream>stdout|stderr)( (.))? (?<log>.*)$/
          time_format '%Y-%m-%dT%H:%M:%S.%NZ'
          keep_time_key true
        </pattern>
      </parse>
      emit_unmatched_lines true
    </source>
  02_filters.conf: |-
    <label @KUBERNETES>
      <match kubernetes.var.log.containers.fluentd**>
        @type relabel
        @label @FLUENT_LOG
      </match>
    
      <match kubernetes.var.log.containers.**_kube-system_**>
        @type null
        @id ignore_kube_system_logs
      </match>

      <match kubernetes.var.log.containers.**_efk_**>
        @type null
        @id ignore_efk_stack_logs
      </match>

      <filter kubernetes.**>
        @type kubernetes_metadata
        @id filter_kube_metadata
        skip_labels true
        skip_container_metadata true
        skip_namespace_metadata true
        skip_master_url true
      </filter>
    
      <match **>
        @type relabel
        @label @DISPATCH
      </match>
    </label>
  03_dispatch.conf: |-
    <label @DISPATCH>
      <filter **>
        @type prometheus
        <metric>
          name fluentd_input_status_num_records_total
          type counter
          desc The total number of incoming records
          <labels>
            tag ${tag}
            hostname ${hostname}
          </labels>
        </metric>
      </filter>
    
      <match **>
        @type relabel
        @label @OUTPUT
      </match>
    </label>
  04_outputs.conf: |-
    <label @OUTPUT>
      <match kubernetes.**>
        @id detect_exception
        @type detect_exceptions
        remove_tag_prefix kubernetes
        message log
        multiline_flush_interval 3
        max_bytes 500000
        max_lines 1000
      </match>
      <match **>
        @type copy
        <store>
          @type stdout
        </store>
        <store>
          @type elasticsearch
          host "elasticsearch-master"
          port 9200
          path ""
          user elastic
          password Changeme
          index_name ais.${tag}.%Y%m%d
          scheme https
          # set to false for self-signed cert
          ssl_verify false
          # supply El's ca certificat if it's trusted
          # ca_file /tmp/elastic-ca-cert.pem
          ssl_version TLSv1_2
          <buffer tag, time>
            # timekey 3600 # 1 hour time slice
            timekey 60 # 1 min time slice
            timekey_wait 10
          </buffer>
        </store>
      </match>
    </label>
```

#### Install/update the Fluentd chart
Change to where your Kustomize directory for Fluentd and run
```
$ helm upgrade -i -n efk fluentd fluent/fluentd --values YourCustomValueDirForFluentd/fluentd.yml --post-renderer ./kustomize
```

Fluentd is created using Daemonset which ensure a Fluentd pod is created on each worker node. Wait till you will see the fluentd pods are in "running" status
```
$ kubectl get po -l app.kubernetes.io/name=fluentd -n efk
```






