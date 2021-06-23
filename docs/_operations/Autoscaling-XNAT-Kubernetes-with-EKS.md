---
layout: default
title: "Autoscaling XNAT on Kubernetes with EKS"
#permalink: /Autoscaling-XNAT-Kubernetes-with-EKS/
---

# Autoscaling XNAT on Kubernetes

There are three types of autoscaling that Kubernetes offers:  

1. Horizontal Pod Autoscaling  
Horizontal Pod Autoscaling (HPA) is a technology that scales up or down the number of replica pods for an application based on resource limits specified in a values file.

2. Vertical Pod Autoscaling  
Vertical Pod Autoscaling increases or decreases the resources to each pod when it gets to a certain percentage to help you best deal with your resources.
After some testing this is legacy and HPA is preferred and also built into the Helm chart so we won't be utilising this technology.  

3. Cluster-autoscaling  
Cluster-autoscaling is where the Kubernetes cluster itself spins up or down new Nodes (think EC2 instances in this case) to handle capacity.


You can't use HPA and VPA together so we will use HPA and Cluster-Autoscaling.


## Prerequisites  

### Running Kubernetes Cluster and XNAT Helm Chart AIS Deployment  
### AWS Application Load Balancer (ALB) as an Ingress Controller with some specific annotations  
### Resources (requests and limits) need to specified in your values file  
### Metrics Server  
### Cluster-Autoscaler  


### AWS Application Load Balancer (ALB) as an Ingress Controller with some specific annotations  

You can find more information on applying ALB implementation for the AIS Helm Chart deployment in the ALB-Ingress-Controller document in this repo, so will not be covering that here, save to say there are some specific annotations that are required for autoscaling to work effectively.  

Specific annotations required:  
```
alb.ingress.kubernetes.io/target-group-attributes: "stickiness.enabled=true,stickiness.lb_cookie.duration_seconds=1800,load_balancing.algorithm.type=least_outstanding_requests"
alb.ingress.kubernetes.io/target-type: ip
```

Let's breakdown and explain the sections.

**Change the stickiness of the Load Balancer:**  
It is important to set a stickiness time on the load balancer or you can get an issue where the Database thinks you have logged in but the pod you connect to knows you haven’t so you can’t login and it keeps logging you out all the time. Setting stickiness reasonably high – say 30 minutes, can get round this.  
```
stickiness.enabled=true,stickiness.lb_cookie.duration_seconds=1800
```

**Change the Load Balancing Algorithm for best performance:** 
```
load_balancing.algorithm.type=least_outstanding_requests
```

**Change the Target type:**  
Not sure why but if target-type is set to ***instance*** and not ***ip***, it disregards the stickiness rules.  
```
alb.ingress.kubernetes.io/target-type: ip
```

### Resources (requests and limits) need to specified in your values file

In order for HPA and Cluster-autoscaling to work, you need to specify resources - requests and limits, in the AIS Helm chart values file, or it won't know when to scale.  
This makes sense because how can you know when you are running out of resources to start scaling up if you don't know what your resources are to start with?  

In your values file add the following lines below the xnat-web section:  

```
  resources:
    limits:
      cpu: 1000m
      memory: 3000Mi
    requests:
      cpu: 1000m
      memory: 3000Mi
```

You can read more about what this means here:

https://kubernetes.io/docs/tasks/configure-pod-container/assign-cpu-resource/  

From my research with HPA, I discovered a few important facts.  
1. Horizontal Podautoscaler doesn't care about limits, it bases autoscaling on requests. Requests are meant to be the minimum needed to safely run a pod and limits are the maximum. However, this is completely irrelevant for HPA as it ignores the limits altogether so I specify the same resaources for requests and limits. See this issue for more details:  

https://github.com/kubernetes/kubernetes/issues/72811  

2. XNAT is extremely memory hungry, and any pod will use approximately 750MB of RAM without doing anything. This is important as when the requests are set below that, you will have a lot of pods scale up, then scale down and no consistency for the user experience. This will play havoc with user sessions and annoy everyone a lot. Applications - specifically XNAT Desktop can use a LOT of memory for large uploads (I have seen 12GB RAM used on an instance) so try and specify as much RAM as you can for the instances you have. In the example above I have specified 3000MB of RAM and 1 vCPU. The worker node instance has 4 vCPUs and 4GB. You would obviously use larger instances if you can. You will have to do some testing to work out the best POD / Instance ratio for your environment.  



### Metrics Server

Download the latest Kubernetes Metrics server yaml file. We will need to edit it before applying the configuration or HPA won't be able to see what resources are being used and none of this will work.  

```
wget https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Add the following line:  
```
        - --kubelet-insecure-tls
```

to here:  
```
    spec:
      containers:
      - args:

```

Completed section should look like this:
```
    spec:
      containers:
      - args:
        - --kubelet-insecure-tls
        - --kubelet-preferred-address-types=InternalIP,ExternalIP
        - --cert-dir=/tmp
        - --secure-port=443
        - --kubelet-use-node-status-port
        - --metric-resolution=15s
```

Now apply it to your CLuster:  
```
k -nkube-system apply -f components.yaml
```

Congratulations - you now have an up and running Metrics server.  
You can read more about Metrics Server here:

```
https://github.com/kubernetes-sigs/metrics-server
```


### Cluster-Autoscaler  

There are quite a lot of ways to use the Cluster-autoscaler - single zone node clusters deployed in single availability zones (no AZ redundancy), single zone node clusters deployed in multiple Availability zones or single Cluster-autoscalers that deploy in multiple Availability Zones. In this example we will be deploying in the autoscaler in multiple Availability Zones (AZ's).

In order to do this, a change needs to be made to the StorageClass configuration used.

Delete whatever StorageClasses you have and then recreate them changing the VolumeBindingMode. At a minimum you will need to change the GP2 / EBS StorageClass VolumeBindingMode but if you are using a persistent volume for archive / prearchive, that will also need to be updated.  

Change this:  
```
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/aws-ebs
volumeBindingMode: Immediate
parameters:
  fsType: ext4
  type: gp2
```

to this:

```
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/aws-ebs
volumeBindingMode: WaitForFirstConsumer
parameters:
  fsType: ext4
  type: gp2
```

The run the following commands (assuming the file above is called storageclass.yaml):  
```
kubectl delete sc --all
kubectl apply -f storageclass.yaml
```

This stops pods trying to bind to volumes in different AZ's.  

You can read more about this here:  
https://aws.amazon.com/blogs/containers/amazon-eks-cluster-multi-zone-auto-scaling-groups/  

**Relevant section:**    
If you need to run a single ASG spanning multiple AZs and still need to use EBS volumes you may want to change the default VolumeBindingMode to WaitForFirstConsumer as described in the documentation here. Changing this setting “will delay the binding and provisioning of a PersistentVolume until a pod using the PersistentVolumeClaim is created.” This will allow a PVC to be created in the same AZ as a pod that consumes it.

If a pod is descheduled, deleted and recreated, or an instance where the pod was running is terminated then WaitForFirstConsumer won’t help because it only applies to the first pod that consumes a volume. When a pod reuses an existing EBS volume there is still a chance that the pod will be scheduled in an AZ where the EBS volume doesn’t exist.

You can refer to AWS documentation for how to install the EKS Cluster-autoscaler:  

https://docs.aws.amazon.com/eks/latest/userguide/cluster-autoscaler.html

This is specific for your deployment IAM roles, clusternames etc, so will not specified here.


### Configure Horizontal Pod Autoscaler

Add the following lines into your values file under the xnat-web section:  
```
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 100
    targetCPUUtilizationPercentage: 80
    targetMemoryUtilizationPercentage: 80
```

Tailor it your own environment. this will create 2 replicas (pods) at start up and will scale up pods when 80% CPU and 80% Memory are utilised - read more about that again here:  
https://kubernetes.io/docs/tasks/configure-pod-container/assign-cpu-resource/  

This is the relevant parts of my environment when running the get command:  

```
k -nxnat get horizontalpodautoscaler.autoscaling/xnat-xnat-web
NAME            REFERENCE                   TARGETS           MINPODS   MAXPODS   REPLICAS   AGE
xnat-xnat-web   StatefulSet/xnat-xnat-web   34%/80%, 0%/80%   2         100       2          3h29m
```

As you can see 34% of memory is used and 0% CPU. Example of get command for pods - no restarts and running nicely.
```
k -nxnat get pods
NAME                  READY   STATUS    RESTARTS   AGE
pod/xnat-xnat-web-0   1/1     Running   0          3h27m
pod/xnat-xnat-web-1   1/1     Running   0          3h23m
```


## Troubleshooting

Check Metrics server is working (assuming in the xnat namespace) and see memory and CPU usage:  
```
kubectl top pods -nxnat
kubectl top nodes
```

Check Cluster-Autoscaler logs:  
```
kubectl logs -f deployment/cluster-autoscaler -n kube-system
```

Check the HPA:  
```
kubectl -nxnat describe horizontalpodautoscaler.autoscaling/xnat-xnat-web
```






