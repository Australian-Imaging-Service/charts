---
title: "Istio Setup"
weight: 10
---

## Deploying Istio Service Mesh for our XNAT environment


### What is a Service Mesh?

From this article:  
https://www.redhat.com/en/topics/microservices/what-is-a-service-mesh


"A service mesh, like the open source project Istio, is a way to control how different parts of an application share data with one another. Unlike other systems for managing this communication, a service mesh is a dedicated infrastructure layer built right into an app. This visible infrastructure layer can document how well (or not) different parts of an app interact, so it becomes easier to optimize communication and avoid downtime as an app grows."  

OK so a service mesh helps secure our environment and the communication between different namespaces and apps in our cluster (or clusters).

Istio is one of the most popular Service Mesh software providers so we will deploy and configure this for our environment.  
OK so let's get to work.  

There are several different ways to install Istio - with the Istioctl Operator, Istioctl, even on Virtual machines, but we will install the Helm version as AIS uses a Helm deployment and it seems nice and neat.  
Following this guide to perform the helm install:  
https://istio.io/latest/docs/setup/install/helm/  

For our installation we won't be installing the Istio Ingress Gateway or Istio Egress Gateway controller for our AWS environment.     
This is because AWS Cluster Autoscaler requires Application Load Balancer type to be IP whereas the Ingress Gateway controller does not work with that target type - only target type: Instance.  
This catch 22 forces us to use only istio and istiod to perform the service mesh and keep our existing AWS ALB Ingress controller. The standard install of Istio is to create an Istio Ingress Gateway, point it to a virtual service and then that virtual service points to your actual service.  

For more information on how to install and configure the Istio Ingress Gateway please follow this guide:  
https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/  





### Install Istio
Download Latest version of istioctl:  
```
curl -L https://istio.io/downloadIstio | sh -
```

Copy binary to /usr/local/bin (change to istio-install directory first - i.e. istio-1.11.X):  
```
sudo cp bin/istioctl /usr/local/bin/
```

Confirm it is working:  
```
istioctl version
```

Create namespace:  
```
kubectl create ns istio-system
```

Install Istio base (must be in istio install directory):  
```
helm install istio-base manifests/charts/base -n istio-system
```

Install Istiod:  
```
helm install istiod manifests/charts/istio-control/istio-discovery \
    -n istio-system
```

Now Istio is installed, we need to apply the configuration to our XNAT namespace to add the Istio sidecars - this is how Istio applies the policies.  
For more information on Sidecars, see this article:  
https://istio.io/latest/docs/reference/config/networking/sidecar/  

Label the namespaces you want the Istio sidecars to install into - in our case XNAT:  
```
kubectl label namespace xnat istio-injection=enabled
```

Confirm it has been successfully applied:  
```
kubectl get ns xnat --show-labels
```

At this point you may need to redeploy your pods if there are no sidecars present. When Istio is properly deployed, instead of xnat pods saying 1/1 they will say 2/2 - example:
```
kubectl get -nxnat all
NAME                    READY   STATUS    RESTARTS   AGE
pod/xnat-postgresql-0   2/2     Running   0          160m
pod/xnat-xnat-web-0     2/2     Running   0          160m
```

### Note about Cluster Austoscaler / Horizontal Pod Autoscaler as it applies to Istio
When using Kubernetes Horizontal Pod Autoscaling (HPA) to scale out pods automatically, you need to make adjustments for Istio. After enabling Istio for some deployments HPA wasn’t scaling as expected and in some cases not at all.  
It turns out that HPA uses the sum of all CPU requests for a pod when determining using CPU metrics when to scale. By adding a istio-proxy sidecar to a pod we were changing the total amount of CPU & memory requests thereby effectively skewing the scale out point. So for example, if you have HPA configured to scale at 70% targetCPUUtilizationPercentage and your application requests 100m, you are scaling at 70m. When Istio comes into the picture, by default it requests 100m as well. So with istio-proxy injected now your scale out point is 140m ((100m + 100m) * 70% ) , which you may never reach. We have found that istio-proxy consumes about 10m in our environment. Even with an extra 10m being consumed by istio-proxy combined with the previous scale up trigger of 70m on the application container is well short (10m + 70m) of the new target of 140m
We solved this by calculating the correct scale out point and setting targetAverageValue to it.

Referenced from this article:  
https://engineering.hellofresh.com/everything-we-learned-running-istio-in-production-part-2-ff4c26844bfb





### Apply our Istio Policies

#### mTLS
We are going to enable Mutual TLS for the entire mesh.  
This policy will do that - call it istio-mtls.yaml:  

```
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
```

Now apply the policy:  
```
kubectl apply -f istio-mtls.yaml
```

Check that mTLS is enabled for all namespaces:  
```
kubectl get peerauthentication --all-namespaces
NAMESPACE      NAME      MODE     AGE
default        default   STRICT   16h
istio-system   default   STRICT   28m
xnat           default   STRICT   16h
```

Now if we try to access our XNAT server we will get 502 Bad Gateway as the XNAT app can't perform mTLS. Please substitute your XNAT URL below:  

```
curl -X GET https://xnat.example.com
<html>
<head><title>502 Bad Gateway</title></head>
<body>
<center><h1>502 Bad Gateway</h1></center>
</body>
</html>
```

So next we want to allow traffic on port 8080 going to our xnat-xnat-web app only and apply mTLS for everything else, so amend istio-mtls.yaml:  

```
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
      mode: STRICT
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: xnat
spec:
  selector:
    matchLabels:
      app: xnat-xnat-web
  mtls:
    mode: STRICT
  portLevelMtls:
    8080:
      mode: DISABLE
```

Now apply again:  
```
kubectl apply -f istio-mtls.yaml
```

If we now run our curl command again:  
```
curl -X GET https://xnat.example.com
```
It completes successfully.  




#### Authorization Policy
You can also specify what commands we can run on our xnat-xnat-web app with Authorization policies and even specify via source from specific namespaces and even apps. This gives you the ability to completely lock down the environment.  
You can for instance allow a certain source POST access whilst another source only has GET and HEAD access.  

Let's create the following Authorization policy to allow all GET and HEAD commands to our xnat-xnat-web app called istio-auth-policy.yaml:  

```
apiVersion: "security.istio.io/v1beta1"
kind: "AuthorizationPolicy"
metadata:
     name: "xnat-all"
     namespace: xnat
spec:
    selector:
      matchLabels:
           app: xnat-xnat-web
   rules:
   - to:
     - operation:
           methods: ["GET", "HEAD"]
```

If you wanted to specify a source you would add a from value under rules and source.  
Please follow this guide for more details:  
https://istio.io/latest/docs/tasks/security/authorization/authz-http/  

Before you apply the policy, we need to add a destination rule to allow the traffic out. Create a file called istio-destination.yaml:  

```
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
   name: "xnat-xnat-web"
spec:
    host: xnat-xnat-web.xnat.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
    portLevelSettings:
    - port:
        number: 8080
      tls:
        mode: DISABLE
```

Apply both policies:  

```
kubectl apply -f istio-auth-policy.yaml
kubectl apply -f istio-destination.yaml
```

Now let's see it in action.  
```
curl -X GET https://xnat.example.com  
```

This completes fine. Now let's try wtih a POST command not included in the authorization policy:

```
curl -X POST https://xnat.example.com  
RBAC: access denied
```

So our policy is working correctly. However, as XNAT relies rather heavily on POST we will add it in to the policy and try again.  
Amend the yaml file to this:  

```
apiVersion: "security.istio.io/v1beta1"
kind: "AuthorizationPolicy"
metadata:
     name: "xnat-all"
     namespace: xnat
spec:
    selector:
      matchLabels:
           app: xnat-xnat-web
   rules:
   - to:
     - operation:
           methods: ["GET", "POST", "HEAD"]
```

Now re-apply the policy:  
```
kubectl apply -f istio-auth-policy.yaml
```

And curl again:  
```
curl -X POST https://xnat.example.com  
```

This time it works. OK so we have a working Istio service mesh with correctly applied Mutual TLS and Authorization Policies.  
This is only a tiny fraction of what Istio can do, so please go to their website for more information.  

https://istio.io/latest/docs/




### Kiali Installation  
Kiali is a fantastic visualisation tool for Istio that helps you see at a glance what your namespaces are up to, if they are protected and allows you to add and update Istio configuration policies right through the web GUI.   
In combination with Prometheus and Jaeger, it allows to show traffic metrics, tracing and much more.  

You can read more about it here:  
https://kiali.io/#:~:text=Kiali%20is%20a%20management%20console,part%20of%20your%20production%20environment.

There are several ways of installing it with authentication (which for production workloads is a must). We are going to use the token method and using the AWS Classic Load Balancer to access.  

Once you have installed Istio and Istiod, follow this guide to guide to install via helm:  
https://kiali.io/docs/installation/installation-guide/example-install/  




#### Install the Operator via Helm and create Namespace:  

```
helm repo add kiali https://kiali.org/helm-charts
helm repo update kiali
helm repo update 
helm install --namespace kiali-operator --create-namespace kiali-operator kiali/kiali-operator
```

Check everything came up properly:  

```
kubectl get -nkiali-operator all
```



#### Install Prometheus and Jaeger into Istio-System namespace to show metrics and tracing. From your Istio installation directory (i.e. istio-1.11.X):

```
kubectl apply -f samples/addons/jaeger.yaml
kubectl apply -f samples/addons/prometheus.yaml
```

Check they are correctly installed:  

```
kubectl get -nistio-system all
```


#### Create Kiali-CR with authentication strategy token and set to service type LoadBalancer to be able to access outside of the cluster:  

vi kiali_cr.yaml 

```
apiVersion: kiali.io/v1alpha1
kind: Kiali
metadata:
  name: kiali
  namespace: istio-system
spec:
  auth:
    strategy: "token"
  deployment:
    service_type: "LoadBalancer"
    view_only_mode: false
  server:
     web_root: "/kiali"
```

Read more about Token authentication here:  
https://kiali.io/docs/configuration/rbac/

Apply the file:  

```
kubectl apply -f kiali_cr.yaml
```

Watch it complete setup:  
```
kubectl get kiali kiali -n istio-system -o jsonpath='{.status}' | jq
```
 and:
```
kubectl get -nistio-system all
```

Run:
```
kubectl get -nistio-system svc kiali
```
to find the ELB address.   

In your browser, type in the copied and pasted details - for example:    
http://example-elb.ap-southeast-2.elb.amazonaws.com  

Then add :20001/kiali to the end:  
http://example-elb.ap-southeast-2.elb.amazonaws.com:20001/kiali  

It will then ask you for a Token for the service account to be able to login. Find it out with this command and then copy and paste and you now have a fully running kiali installation:  

```
kubectl get secret -n istio-system $(kubectl get sa kiali-service-account -n istio-system -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 -d
```

More details about accessing Kiali via Ingress:
https://kiali.io/docs/installation/installation-guide/accessing-kiali/

At this point I tried to set the AWS Elastic Load Balancer to use SSL and a proper certificate but after 4 hours of investigation it turns out that Kiali ingress requires "class_name" and AWS ELB doesn't have one so that doesn't work. Rather frustratingly I ended up manually updating the LoadBalancer lister details to be SSL over TCP and to specify the SSL Cipher policy and Certificate Manager. You should also point your FQDN to this Load Balancer to work with your custom certificate. No doubt an integration of Nginx and AWS ELB would fix this - Nginx being Kiali's default ingress method. 




### Troubleshooting Istio 
Use these commands for our XNAT environment to help debugging:  

```
istioctl proxy-status
istioctl x describe pod xnat-xnat-web-0.xnat
istioctl proxy-config listeners xnat-xnat-web-0.xnat 
istioctl x authz check xnat-xnat-web-0.xnat
kubectl logs pod/xnat-xnat-web-0 -c istio-proxy -nxnat
kubectl get peerauthentication --all-namespaces
kubectl get destinationrule --all-namespaces
```

#### More Articles on Troubleshooting Istio:  
https://www.istioworkshop.io/12-debugging/01-istioctl-debug-command/  
https://istio.io/latest/docs/ops/common-problems/security-issues/




### Further Reading

Istio AuthorizationPolicy testing / config:  
https://istiobyexample.dev/authorization/  

Istio mTLS status using Kiali:  
https://kiali.io/docs/features/security/  

Istio Workshop:  
https://www.istioworkshop.io  

Istio mTLS Example Setup:  
https://istio.io/latest/docs/tasks/security/authentication/mtls-migration/  