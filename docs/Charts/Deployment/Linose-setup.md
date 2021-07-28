**High Level Steps for XNAT LKE Deployment**

1. Creation of LKE Cluster using
         a) Linode Cloud Manager - To get the basic understanding initially - https://www.linode.com/docs/guides/deploy-and-manage-a-cluster-with-linode-kubernetes-engine-a-tutorial/
         b) Terraform - At a later point of time to make things easier - https://www.linode.com/docs/guides/how-to-deploy-an-lke-cluster-using-terraform/

2. Deploy the XNAT app manually using the Helm Charts in AIS repo

3. Look out for persistent volumes or storage issues after the initial deployment.
         StorageClass - linode-block-storage-retain
         Reference Link - https://www.linode.com/docs/guides/deploy-volumes-with-the-linode-block-storage-csi-driver/

4. Create custom persistent Volumes for Linode after Step 3 and upgrade the deployment

5. Implement Ingress Controller using helm & provision Loadbalancer(Nodebalancers in Linode) and manage DNS mapping
         Reference Link - https://www.linode.com/docs/guides/how-to-deploy-nginx-ingress-on-linode-kubernetes-engine/
         
6. HTTP to HTTPS in the external load balancer and the ingress routing using Kubernetes cert-manager & Lets-encrypt
         Reference Link - https://www.linode.com/docs/guides/how-to-configure-load-balancing-with-tls-encryption-on-a-kubernetes-cluster/
         

**Possible Concerns**

1. Linode PV support only ReadWriteOnce accessmode - Don't think its of a concern at least at this point of time of XNAT deployment - Dean to confirm
2. Note sure about the availability of Node Autoscaling in LKE - Have to investigage more
3. How do I use the already available On-Prem storage as PV 
