---
title: "ALB Ingress Controller"
weight: 10
---

## Creating an Application Load Balancer to connect to the AIS Helm chart XNAT Implementation

We will be following this AWS Guide:

https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html
 
{{% alert title="Before we begin" %}}
One thing that you need to know when we want to create new ALB from EKS is service spec type can only support LoadBalancer and NodePort. It won't support `ClusterIP`.
{{% /alert %}}

The Charts Repo has the service defined as `ClusterIP` so some changes need to be made to make this work. We will get to that later after we have created the ALB and policies.

In this document we create a Cluster called xnat in ap-southeast-2. Please update these details for your environment.
 
Create an IAM OIDC provider and associate with cluster:  
```bash
eksctl utils associate-iam-oidc-provider --region ap-southeast-2 --cluster xnat --approve
```
 
Download the IAM Policy:  
```bash
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
```
 
Create the IAM policy and take a note of the ARN:  
```bash
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam-policy.json
```
 
Create the service account using ARN from the previous command (substitute your ARN for the XXX):  
```bash
eksctl create iamserviceaccount --cluster=xnat --namespace=kube-system --name=aws-load-balancer-controller --attach-policy-arn=arn:aws:iam::XXXXXXXXX:policy/AWSLoadBalancerControllerIAMPolicy --override-existing-serviceaccounts --approve
```
 
Install `TargetGroupBinding`:
```bash
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"
```

Download the EKS Helm Chart and update repo information:    
```
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```
 
Install the AWS Load Balancer Controller:  
```bash
helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller --set clusterName=xnat --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller -n kube-system
```
 
Confirm it is installed:  
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```
 
You should see - `READY 1/1` if it is installed properly

 
In order to apply this to the XNAT Charts Helm template update the `charts/xnat/values.yaml` file to remove the Nginx ingress parts and add the ALB ingress parts.


Added to values file:  
```yaml
      kubernetes.io/ingress.class: alb
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/group.name: xnat
      alb.ingress.kubernetes.io/target-type: ip
```
 
{{% alert %}}
NB. Although you can specify ip or instance for the target-type, you need to specify ip or autoscaling won't function correctly. This is because stickiness isn't honoured for target-type instance so you have the known issue where XNAT database thinks you are logged in but instance / pod knows you are not and then it logs you out again.
{{% /alert %}}

For more ALB annotations / options, please see article at the bottom of the page.

Commented out / removed:  
```yaml
      kubernetes.io/ingress.class: "nginx"
      kubernetes.io/tls-acme: "true"
      nginx.ingress.kubernetes.io/whitelist-source-range: "130.95.0.0/16 127.0.0.0/8"
      nginx.ingress.kubernetes.io/proxy-connect-timeout: "150"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "100"
      nginx.ingress.kubernetes.io/proxy-read-timeout: "100"
      nginx.ingress.kubernetes.io/proxy-buffers-number: "4"
      nginx.ingress.kubernetes.io/proxy-buffer-size: "32k"
``` 
 
As pointed out `ClusterIP` as service type does not work with ALB. So you will have to make some further changes to `charts/xnat/charts/xnat-web/values.yaml`:

Change:
```yaml
service:
  type: ClusterIP
  port: 80
```
to:
```yaml
service:
  type: NodePort
  port: 80
```

In `xnat/charts/xnat-web/templates/service.yaml` remove the line:  
  
```yaml
clusterIP: None
```

Then create the Helm chart with the usual command (after building dependencies - just follow README.md). If you are updating an existing xnat installation it will fail so you will need to create a new application. 

```bash
helm upgrade xnat . -nxnat
```

It should now create a Target Group and Application Load Balancer in AWS EC2 Services. I had to make a further change to get this to work.
 
On the Target Group I had to change health check code from **`200`** to **`302`** to get a healthy instance because it redirects.
 
You can fix this by adding the following line to values file:  
```yaml
      # Specify Health Checks
      alb.ingress.kubernetes.io/healthcheck-path: "/"
      alb.ingress.kubernetes.io/success-codes: "302"
```
Troubleshooting and make sure ALB is created:  
```bash
watch kubectl -n kube-system get all
```
 
Find out controller name in pod. In this case - `pod/aws-load-balancer-controller-98f66dcb8-zkz8k`
 
Make sure all are up.
 
Check logs:  
```bash
kubectl logs -n kube-system aws-load-balancer-controller-98f66dcb8-zkz8k
```
 
When updating ALB is often doesn't update properly so you will need to delete and recreate the ALB:  
```bash
kubectl delete deployment -n kube-system aws-load-balancer-controller
helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller --set clusterName=xnat --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller -n kube-system
```
 
Change the stickiness of the Load Balancer:  
It is important to set a stickiness time on the load balancer or you can get an issue where the Database thinks you have logged in but the pod you connect to knows you haven’t so you can’t login. Setting stickiness reasonably high – say 30 minutes, can get round this.  
```yaml
alb.ingress.kubernetes.io/target-group-attributes: stickiness.enabled=true,stickiness.lb_cookie.duration_seconds=1800
```

Change the Load Balancing Algorithm:  
```yaml
alb.ingress.kubernetes.io/target-group-attributes: load_balancing.algorithm.type=least_outstanding_requests
```

Increase the timeout to 5 minutes from 1. When using the Compressed Image Uploader you can sometimes get a 504 Gateway timeout error message. This will fix that issue.  
You can read more about it here:  
https://aws.amazon.com/premiumsupport/knowledge-center/eks-http-504-errors/

```yaml
alb.ingress.kubernetes.io/load-balancer-attributes: "idle_timeout.timeout_seconds=300"  
```


## Add SSL encryption to your Application Load Balancer

Firstly, you need to add an SSL certificate to your ALB annotations. Kubernetes has a built in module: Cert Manager, to deal with cross clouds / infrastructure.

https://cert-manager.io/docs/installation/kubernetes/

However, in this case, AWS has a built in Certificate Manager that creates and a renews SSL certificates for free so we will be using this technology. 

You can read more about it here:

https://aws.amazon.com/certificate-manager/getting-started/#:~:text=To%20get%20started%20with%20ACM,certificate%20from%20your%20Private%20CA.

This assumes you have a valid certificate created through AWS Certificate Manager and you know the ARN. 


These are additional annotations to add to values file and explanations above:  

Listen on port 80 and 443:
```yaml
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS":443}]'
```

Specify the ARN of your SSL certificate from AWS Certificate Manager (change for your actual ARN):
```yaml
      alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:XXXXXXX:certificate/XXXXXX"
```

Specify AWS SSL Policy:  
```yaml
      alb.ingress.kubernetes.io/ssl-policy: "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"
```

For more details see here of SSL policy options:

https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-https-listener.html

Finally, for this to successfully work you need to change the host path to allow any path or the Tomcat URL will be sent to a 404 by the Load Balancer. Put a wildcard in the paths to allow any eventual URL (starting with xnat.example.com in this case):

```yaml
    hosts:
      - host: xnat.example.com
        paths: [ "/*" ]
```

### Redirect HTTP to HTTPS:

This does not work on Kubernetes 1.19 or above as the “use-annotation” command does not work. There is seemingly no documentation on the required annotations to make this work.

Add the following annotation to your values file below the ports to listen on (see above):

```yaml
     alb.ingress.kubernetes.io/actions.ssl-redirect: '{"Type": "redirect", "RedirectConfig": {"Protocol": "HTTPS", "Port": "443", "StatusCode": "HTTP_301"}}'
```
 
You must then update the Rules section of `ingress.yaml` found within the `releases/xnat/charts/xnat-web/templates` directory to look like this:

```yaml
  rules:
    {{- range .Values.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            backend:
              serviceName: {{ $fullName }}
              servicePort: {{ $svcPort }}
          {{- end }}
    {{- end }}
  
```

This will redirect HTTP to HTTPS on Kubernetes 1.18 and below.

Full `values.yaml` file ingress section:

```yaml
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: alb
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS":443}]'
      alb.ingress.kubernetes.io/actions.ssl-redirect: '{"Type": "redirect", "RedirectConfig": {"Protocol": "HTTPS", "Port": "443", "StatusCode": "HTTP_301"}}'
      alb.ingress.kubernetes.io/healthcheck-path: "/"
      alb.ingress.kubernetes.io/success-codes: "302"
      alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:XXXXXXX:certificate/XXXXXX"
      alb.ingress.kubernetes.io/ssl-policy: "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"
      alb.ingress.kubernetes.io/target-group-attributes: "stickiness.enabled=true,stickiness.lb_cookie.duration_seconds=1800,load_balancing.algorithm.type=least_outstanding_requests"
```

Further Reading:

* https://medium.com/devops-dudes/running-the-latest-aws-load-balancer-controller-in-your-aws-eks-cluster-9d59cdc1db98
 
Troubleshooting EKS Load Balancers:  

* https://aws.amazon.com/premiumsupport/knowledge-center/eks-load-balancers-troubleshooting/
* https://medium.com/@ManagedKube/kubernetes-troubleshooting-ingress-and-services-traffic-flows-547ea867b120
 
ALB annotations:  

* https://kubernetes-sigs.github.io/aws-load-balancer-controller/guide/ingress/annotations/


