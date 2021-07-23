---
title: "Azure Setup Full"
weight: 10
---

## Create an AKS Cluster

One of the great things about Azure is the Azure Cli. Specify Bash and then you can run all commands through your web browser and all tools and kubectl / az commands are already installed and available without having to create them on your workstation or spin up a VM instance for the sole purpose of controlling the cluster.  

You can do this via the console if you want. By Azure cli, see below. Create a resource group first.  


Specify your Resource Group, cluster name (in our case xnat but please update if your Cluster is name differently), node count and VM instance size:


```bash
az aks create \
--resource-group <Resource Group Name> \
--name xnat \
--node-count 3 \
--generate-ssh-keys \
--node-vm-size Standard_B2s \
--enable-managed-identity
```


Get AZ AKS credentials to run kubectl commands against your Cluster

```bash
az aks get-credentials --name xnat --resource-group <Resource Group Name>
```


Confirm everything is setup correctly:

```bash
kubectl get nodes -o wide
kubectl cluster-info
```



### Download and install AIS Chart 

```bash
git clone https://github.com/Australian-Imaging-Service/charts.git
```

Add the AIS repo and update Helm:  

```bash
helm repo add ais https://australian-imaging-service.github.io/charts
helm repo update
```

Change to the correct directory and update dependencies. This will download and install the Postgresql Helm Chart. You don't need to do this if you want to connect to an external Postgresql DB.

```bash
cd ~/charts/release/xnat
helm dependency update
```

Create the namespace and install the chart, then watch it be created.  

```bash
kubectl create namespace xnat
helm upgrade xnat ais/xnat --install -nxnat
watch kubectl -nxnat get all
```

It will complain that the Postgresql password is empty and needs updating.
Create an override values file (in this case values-aks.yaml but feel free to call it what you wish) and add the following inserting your own desired values:

```yaml
xnat-web:
  postgresql:
    postgresqlDatabase: <your database>
    postgresqlUsername: <your username>
    postgresqlPassword: <your password>
```

### Update volume / persistence information
It turns out that there is an issue with Storage classes that means that the volumes are not created automatically.
We need to make a small change to the storageClass configuration for the ReadWriteOnce volumes and create new external volumes for the ReadWriteMany ones.

Firstly, we create our own Azure files volumes for archive and prearchive and make a slight adjustment to the values configuration and apply as an override.

Follow this document for the details of how to do that:  

https://docs.microsoft.com/en-us/azure/aks/azure-files-volume

Firstly, export some values that will be used to create the Azure files volumes. Please substitute the details of your environment here.

```ini
AKS_PERS_STORAGE_ACCOUNT_NAME=<your storage account name>
AKS_PERS_RESOURCE_GROUP=<your resource group>
AKS_PERS_LOCATION=<your region>
AKS_PERS_SHARE_NAME=archive-xnat-xnat-web
```

***archive-xnat-xnat-web*** will need to be used or the Helm chart won't be able to find the mount.

Create a storage account:  
```bash
az storage account create -n $AKS_PERS_STORAGE_ACCOUNT_NAME -g $AKS_PERS_RESOURCE_GROUP -l $AKS_PERS_LOCATION --sku Standard_LRS
```

Export the connection string as an environment variable, this is used when creating the Azure file share:  
```bash
export AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string -n $AKS_PERS_STORAGE_ACCOUNT_NAME -g $AKS_PERS_RESOURCE_GROUP -o tsv)
```

Create the file share:  
```bash
az storage share create -n $AKS_PERS_SHARE_NAME --connection-string $AZURE_STORAGE_CONNECTION_STRING
```

Get storage account key:  
```bash
STORAGE_KEY=$(az storage account keys list --resource-group $AKS_PERS_RESOURCE_GROUP --account-name $AKS_PERS_STORAGE_ACCOUNT_NAME --query "[0].value" -o tsv)
```

Echo storage account name and key:  
```bash
echo Storage account name: $AKS_PERS_STORAGE_ACCOUNT_NAME
echo Storage account key: $STORAGE_KEY
```

Make a note of the Storage account name and key as you will need them.

Now repeat this process but update the Share name to prearchive-xnat-xnat-web. Run this first and then repeat the rest of the commands:  
```bash
AKS_PERS_SHARE_NAME=prearchive-xnat-xnat-web***
```


### Create a Kubernetes Secret  

In order to mount the volumes, you need to create a secret. As we have created our Helm chart in the xnat namespace, we need to make sure that is added into the following command (not in the original Microsoft guide):  

```bash
kubectl -nxnat create secret generic azure-secret --from-literal=azurestorageaccountname=$AKS_PERS_STORAGE_ACCOUNT_NAME --from-literal=azurestorageaccountkey=$STORAGE_KEY
```


### Create Kubernetes Volumes  
Now we need to create two persistent volumes outside of the Helm Chart which the Chart can mount - hence requiring the exact name.  
Create two files

- `pv_archive.yaml`
- `pv_prearchive.yaml`

{{< code yaml "pv_archive.yaml" >}}
apiVersion: v1
kind: PersistentVolume
metadata:
  name: archive-xnat-xnat-web
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  claimRef:
    name: archive-xnat-xnat-web
    namespace: xnat
  azureFile:
    secretName: azure-secret
    shareName: archive-xnat-xnat-web
    readOnly: false
  mountOptions:
  - dir_mode=0755
  - file_mode=0755
  - uid=1000
  - gid=1000
  - mfsymlinks
  - nobrl
{{</ code >}}

{{< code yaml "pv_prearchive.yaml" >}}
apiVersion: v1
kind: PersistentVolume
metadata:
  name: prearchive-xnat-xnat-web
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  claimRef:
    name: prearchive-xnat-xnat-web
    namespace: xnat
  azureFile:
    secretName: azure-secret
    shareName: prearchive-xnat-xnat-web
    readOnly: false
  mountOptions:
  - dir_mode=0755
  - file_mode=0755
  - uid=1000
  - gid=1000
  - mfsymlinks
  - nobrl
{{</ code >}}

Size doesn't really matter as like EFS, Azure files is completely scaleable. Just make sure it is the same as your values file for those volumes.  

#### Apply the volumes
```bash
kubectl apply -f pv_archive.yaml
kubectl apply -f pv_prearchive.yaml
```

We should now have two newly created volumes our Helm chart can mount.




## Update our override values file for our Helm chart.
Edit your values-aks.yaml file from above and add the following in (postgresl entries already added):  

Paste the following:

```yaml
xnat-web:
  persistence:
    cache:
      accessMode: ReadWriteOnce
      mountPath: /data/xnat/cache
      storageClassName: ""
      size: 10Gi
    work:
      accessMode: ReadWriteOnce
      mountPath: /data/xnat/home/work
      storageClassName: ""
      size: 1Gi
    logs:
      accessMode: ReadWriteOnce
      mountPath: /data/xnat/home/logs
      storageClassName: ""
      size: 1Gi
    plugins:
      accessMode: ReadWriteOnce
      mountPath: /data/xnat/home/plugins
      storageClassName: ""
      size: 0
  volumes:
    archive:
      accessMode: ReadWriteMany
      mountPath: /data/xnat/archive
      storageClassName: ""
      size: 10Gi
    prearchive:
      accessMode: ReadWriteMany
      mountPath: /data/xnat/prearchive
      storageClassName: ""
      size: 10Gi
  postgresql:
    postgresqlDatabase: <your database>
    postgresqlUsername: <your username>
    postgresqlPassword: <your password>
```

You can now apply the helm chart with your override and all the volumes will mount.  
```bash
helm upgrade xnat ais/xnat -i -f values-aks.yaml -nxnat
```

Congratulations! Your should now have a working XNAT environment with properly mounted volumes.

You can check everything is working:
```bash
kubectl -nxnat get ev
kubectl -nxnat get all
kubectl -nxnat get pvc,pv
```


Check that the XNAT service comes up:  
```bash
kubectl -nxnat logs xnat-xnat-web-0 -f
```




### Creat a static public IP, an ingress controller, LetsEncrypt certififcates and point it to our Helm chart  

OK so all good so far but we can't actually access our XNAT environment from outside of our cluster so we need to create an Ingress Controller.

You can follow the URL here from Microsoft for more detailed information:  

https://docs.microsoft.com/en-us/azure/aks/ingress-static-ip

First, find out the resource name of the AKS Cluster:  
```bash
az aks show --resource-group <your resource group> --name <your cluster name> --query nodeResourceGroup -o tsv
```

This will create the output for your next command.  
```bash
az network public-ip create --resource-group <output from previous command> --name <a name for your public IP> --sku Standard --allocation-method static --query publicIp.ipAddress -o tsv
```




#### Point your FQDN to the public IP address you created
For the Letsencrypt certificate issuer to work it needs to be based on a working FQDN (fully qualified domain name), so in whatever DNS manager you use, create a new A record and point your xnat FQDN (xnat.example.com for example) to the IP address you just created.  

Add the ingress-nginx repo:  
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
```

Now create the ingress controller with a DNS Label (doesn't need to be FQDN here) and the IP created in the last command:  

```bash
helm install nginx-ingress ingress-nginx/ingress-nginx --namespace xnat --set controller.replicaCount=2 --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux --set controller.admissionWebhooks.patch.nodeSelector."beta\.kubernetes\.io/os"=linux --set controller.service.loadBalancerIP="1.2.3.4" --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"="xnat-aks"
```

Please ensure to update the details above to suit your environment - including namespace.





### Install Cert-Manager and attach to the Helm chart and Ingress Controller  
```bash
kubectl label namespace xnat cert-manager.io/disable-validation=true
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install   cert-manager   --namespace xnat   --version v1.3.1   --set installCRDs=true   --set nodeSelector."beta\.kubernetes\.io/os"=linux   jetstack/cert-manager
```
You can find a write up of these commands and what they do in the Microsoft article.





#### Create a cluster-issuer.yaml to issue the Letsencrypt certificates  
{{< code "yaml" "cluster-issuer.yaml" >}}
apiVersion: cert-manager.io/v1alpha2
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your@emailaddress.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
          podTemplate:
            spec:
              nodeSelector:
                "kubernetes.io/os": linux
{{</ code >}}

In our case, we want production Letsencrypt certificates hence letsencrypt-prod (mentioned twice here and in values-aks.yaml). If you are doing testing you can use letsencrypt-staging. See Microsoft article for more details.  
Please do not forget to use your email address here.

Apply the yaml file:  
```bash
kubectl apply -f cluster-issuer.yaml -nxnat
```





### Update your override values file to point to your ingress controller and Letsencrypt Cluster issuer  
Add the following to your `values-aks.yaml` file (I have added the volume and postgresql details as well for the complete values file):

{{< code "yaml" "values-aks.yaml" >}}
xnat-web:
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: nginx
      cert-manager.io/cluster-issuer: letsencrypt-prod
    tls:
      - hosts:
          - "yourxnat.example.com"
        secretName: tls-secret
    hosts:
      - "yourxnat.example.com"
    rules:
      - host: "yourxnat.example.com"
        http:
          paths:
            - path: "/"
              backend:
                serviceName: "xnat-xnat-web"
                servicePort: 80
  persistence:
    cache:
      accessMode: ReadWriteOnce
      mountPath: /data/xnat/cache
      storageClassName: ""
      size: 10Gi
    work:
      accessMode: ReadWriteOnce
      mountPath: /data/xnat/home/work
      storageClassName: ""
      size: 1Gi
    logs:
      accessMode: ReadWriteOnce
      mountPath: /data/xnat/home/logs
      storageClassName: ""
      size: 1Gi
    plugins:
      accessMode: ReadWriteOnce
      mountPath: /data/xnat/home/plugins
      storageClassName: ""
      size: 0
  volumes:
    archive:
      accessMode: ReadWriteMany
      mountPath: /data/xnat/archive
      storageClassName: ""
      size: 10Gi
    prearchive:
      accessMode: ReadWriteMany
      mountPath: /data/xnat/prearchive
      storageClassName: ""
      size: 10Gi
  postgresql:
    postgresqlDatabase: <your database>
    postgresqlUsername: <your username>
    postgresqlPassword: <your password>
{{</ code >}}

Change `yourxnat.example.com` to whatever you want your XNAT FQDN to be.  
If you are using Letsencrypt-staging, update the cert-manager.io annotation accordingly.

Now update your helm chart and you should now have a fully working Azure XNAT installation with HTTPS redirection enabled, working volumes and fully automated certificates with automatic renewal.

```bash
helm upgrade xnat ais/xnat -i -f values-aks.yaml -nxnat
```



 



