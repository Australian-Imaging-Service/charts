High Level Steps for XNAT LKE Deployment

1. Creation of LKE Cluster using
                a) Linode Cloud Manager once - To get the basic understanding initially - https://www.linode.com/docs/guides/deploy-and-manage-a-cluster-with-linode-kubernetes-engine-a-tutorial/
                b) Terraform - At a later point of time to make things easier - https://www.linode.com/docs/guides/how-to-deploy-an-lke-cluster-using-terraform/

2. Deploy the XNAT app manually using the Helm Charts in AIS repo

3. Look out for persistent volumes or storage issues after the initial deployment.
            StorageClass - linode-block-storage-retain
            Reference Link - https://www.linode.com/docs/guides/deploy-volumes-with-the-linode-block-storage-csi-driver/

4. 
