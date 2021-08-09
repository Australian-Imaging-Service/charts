**High Level Steps for XNAT LKE Deployment**


         

**1.LKE Cluster Setup:**\
                                    Set up the Linode LKE cluster using the link https://www.linode.com/docs/guides/how-to-deploy-an-lke-cluster-using-terraform/ **(Please note that a separate documentation for setting up LKE Cluster using Terraform will be coming up soon)**

**2.Preparing for Tweaks pertaining to Linode:**\
                           As we are tweaking XNAT Values related to PV access modes, let us check out the charts repo rather than using the adding
AIS helm chart repository.
                          
         git clone https://github.com/Australian-Imaging-Service/charts.git

**3.Actual Tweaks:**\
                           Replace the access modes of all Volumes from "ReadWriteMany" to "ReadWriteOnce" in charts/releases/xnat/charts/xnat-web
This is because Linode storage only supports "ReadWriteOnce" at this point of time.

**4.Dependency Update:**\
                           Update the dependency by switching to charts/releases/xnat and execute the following
            
         helm dependency update

**5.XNAT Initial Installation:**\
                           Go to charts/releases and install xnat using helm.

           kubectl create namespace xnat

           helm install xnat-deployment xnat --values YOUR-VALUES-FILE --namespace=xnat

   The XNAT & POSTGRES service should be up & running fine. Linode Storage Class "linode-block-storage-retain" should have automatically
   come in place & PVs will be auto created to be consumed by our mentioned PVCs.

**6.Ingress Controller/Load balancer Installation:**\
                           Install Ingress Controller and provision a Load balancer (Nodebalancer in Linode) by executing these commands

            helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

            helm repo update

            helm install ingress-nginx ingress-nginx/ingress-nginx

You may see an output like below

>NAME: ingress-nginx\
LAST DEPLOYED: Mon Aug  2 11:51:32 2021\
NAMESPACE: default\
STATUS: deployed\
REVISION: 1\
TEST SUITE: None\
NOTES:\
The ingress-nginx controller has been installed.\
It may take a few minutes for the LoadBalancer IP to be available.

**7.Domain Mapping:**\
                           Get the External IP address of the Loadbalancer by running the below command and assign it to any domain or subdomain.
   Example: xnat-test.neura.edu.au is the subdomain for which the loadbalancer IP is assigned in my case

            kubectl --namespace default get services -o wide -w ingress-nginx-controller

**8.HTTP Traffic Routing via Ingress:**\
                           It is time to create a Ingress object that directs the traffic based on the host/domain to the already available XNAT service.
   Get the XNAT service name by issuing the below command and choose the service name that says TYPE as ClusterIP

          kubectl get svc -nxnat -l "app.kubernetes.io/name=xnat-web"

   Example: xnat-deployment-xnat-web

   Using the above service name, write an ingress object to route the external traffic based on the domain name.

         apiVersion: networking.k8s.io/v1
         kind: Ingress
         metadata:
           name: xnat-ingress
           namespace: xnat
           annotations:
             kubernetes.io/ingress.class: nginx
         spec:
           rules:
           - host: cloud.neura.edu.au
             http:
               paths:
               - pathType: Prefix
                 path: "/"
                 backend:
                   service:
                     name: xnat-deployment-xnat-web
                     port:
                       number: 80

**9.Delete the HTTP Ingress project:**\
                           After the creation of this Ingress object, make sure cloud.neura.edu.au is routed to the XNAT application over HTTP successfully.Let us delete the ingress object after checking because we will be creating another one with TLS to use HTTPS.

        kubectl delete ingress xnat-ingress -nxnat

**10.Install cert-manager for Secure Connection HTTPS**\
                           Install cert-manager’s CRDs.

         kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.3.1/cert-manager.crds.yaml

Create a cert-manager namespace.

         kubectl create namespace cert-manager
Add the Helm repository which contains the cert-manager Helm chart.

         helm repo add jetstack https://charts.jetstack.io
Update your Helm repositories.

         helm repo update
Install the cert-manager Helm chart.

         helm install \
         cert-manager jetstack/cert-manager \
         --namespace cert-manager \
         --version v1.3.1
Verify that the corresponding cert-manager pods are now running.

         kubectl get pods --namespace cert-manager
You should see a similar output:

>NAME                                       READY   STATUS    RESTARTS   AGE\
cert-manager-579d48dff8-84nw9              1/1     Running   3          1m\
cert-manager-cainjector-789955d9b7-jfskr   1/1     Running   3          1m\
cert-manager-webhook-64869c4997-hnx6n      1/1     Running   0          1m

**11.Creation of ClusterIssuer to Issue certificates:**\
                           Create a manifest file named acme-issuer-prod.yaml that will be used to create a ClusterIssuer resource on your cluster. Ensure you replace user@example.com with your own email address.

         
         apiVersion: cert-manager.io/v1
         kind: ClusterIssuer
         metadata:
           name: letsencrypt-prod
           namespace: xnat
         spec:
           acme:
             email: user@example.com
             server: https://acme-v02.api.letsencrypt.org/directory
             privateKeySecretRef:
               name: letsencrypt-secret-prod
             solvers:
             - http01:
                 ingress:
                   class: nginx

**12.HTTPS Routing with Ingress object leveraging ClusterIssuer:**\
Provision a new Ingress object to use the clusterIssuer for the generation of the certificate and use it

         apiVersion: networking.k8s.io/v1
         kind: Ingress
         metadata:
           name: xnat-ingress-https
           namespace: xnat
           annotations:
             kubernetes.io/ingress.class: "nginx"
             cert-manager.io/cluster-issuer: "letsencrypt-prod"
         spec:
           tls:
           - hosts:
             - cloud.neura.edu.au
             secretName: xnat-tls
           rules:
           - host: cloud.neura.edu.au
             http:
               paths:
               - pathType: Prefix
                 path: "/"
                 backend:
                   service:
                     name: xnat-deployment-xnat-web
                     port:
                       number: 80


After the creation of the above ingress https://cloud.neura.edu.au/ should bring up the XNAT application in the web browser


**Reference Links**\
         LKE set up using Cloud Manager   - https://www.linode.com/docs/guides/deploy-and-manage-a-cluster-with-linode-kubernetes-engine-a-tutorial/ \
         LKE set up using Terraform       - https://www.linode.com/docs/guides/how-to-deploy-an-lke-cluster-using-terraform/ \
         Linode Storage Class             - https://www.linode.com/docs/guides/deploy-volumes-with-the-linode-block-storage-csi-driver/ \
         Ingress Controller & Loadbalancer- https://www.linode.com/docs/guides/how-to-deploy-nginx-ingress-on-linode-kubernetes-engine/ \
         HTTP to HTTPS using cert-manager - https://www.linode.com/docs/guides/how-to-configure-load-balancing-with-tls-encryption-on-a-kubernetes-cluster
