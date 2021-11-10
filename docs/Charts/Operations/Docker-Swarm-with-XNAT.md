---
title: "Docker Swarm with XNAT"
weight: 10
---

# Setting up Docker Swarm
A complete explanation of how to setup Docker Swarm is outside the scope of this document but you can find some useful articles here:  
https://scalified.com/2018/10/08/building-jenkins-pipelines-docker-swarm/  
https://docs.docker.com/engine/swarm/swarm-tutorial/create-swarm/  
https://docs.docker.com/engine/swarm/ingress/  

Setting up with AWS:  
https://semaphoreci.com/community/tutorials/bootstrapping-a-docker-swarm-mode-cluster


## Pipelines
XNAT uses pipelines to perform various different processes - mostly converting image types to other image types (DICOM to NIFTI for example).  
In the past this was handled on the instance as part of the XNAT program, then as a docker server on the instance and finally, externally as an external docker server, either directly or using Docker swarm.  
XNAT utilises the Container service which is a plugin to perform docker based pipelines. In the case of Kubernetes, docker MUST be run externally so Docker swarm is used as it provides load balancing.  
Whilst the XNAT team work on replacing the Container service on Docker Swarm with a Kubernetes based Container service, Docker swarm is the most appropriate stop gap option.


## Prerequisites
You will require the Docker API endpoint opened remotely so that XNAT can access and send pipeline jobs to it. For security, this should be done via HTTPS (not HTTP).  
Standard port is TCP 2376. With Docker Swarm enabled you can send jobs to any of the manager or worker nodes and it will automatically internally load balance. I chose to use the Manager node's IP and pointed DNS to it.  
You should lock access to port 2376 to the Kubernetes XNAT subnets only using firewalls or Security Group settings. You can also use an external Load balancer with certificates which maybe preferred.  
If the certificates are not provided by a known CA, you will need to add the certificates (server, CA and client) to your XNAT container build so choosing a proper certificate from a known CA will make your life easier.  
If you do use self signed certificates, you will need create a folder, add the certificates and then specify that folder in the XNAT GUI > Administer > Plugin Settings > Container Server Setup > Edit Host Name. In our example case:

```
Certificate Path: /usr/local/tomcat/certs
```
Access from the Docker Swarm to the XNAT shared filesystem - at a minimum Archive and build. The AIS Helm chart doesn't have /data/xnat/build setup by default but without this Docker Swarm can't write the temporaray files it needs and fails.


### Setup DNS and external certificates
Whether you will need to create self signed certificates or public CA verified ones, you will need a fully qualified domain name to create them against.  
I suggest you set an A record to point to the Manager node IP address, or a Load Balancer which points to all nodes. Then create the certificates against your FQDN - e.g. swarm.example.com.


### Allow remote access to Docker API endpoint on TCP 2376
To enable docker to listen on port 2376 edit the service file or create /etc/docker/daemon.json.  

We will edit the docker service file. Remember to specify whatever certificates you will be using in here. They will be pointing to your FQDN - in our case above, swarm.example.com.  
```
systemctl edit docker
```

```
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H tcp://0.0.0.0:2376 --tlsverify --tlscacert /root/.docker/ca.pem --tlscert /root/.docker/server-cert.pem -tlskey /root/.docker/server-key.pem -H unix:///var/run/docker.sock
```

```
systemctl restart docker
```
Repeat on all nodes. Docker Swarm is now listening remotely on TCP 2376.  


### Secure access to TCP port 2376
Add a firewall rule to only allow access to TCP port 2376 from the Kubernetes subnets.  


### Ensure Docker Swarm nodes have access to the XNAT shared filesystem
Without access to the Archive shared filesystem Docker cannot run any pipeline conversions. This seems pretty obvious. Less obvious however is that the XNAT Docker Swarm requires access to the Build shared filesystem to run temporary jobs before writing back to Archive upon completion.  
This presents a problem as the AIS Helm Chart does not come with a persistent volume for the Build directory, so we need to create one.  
Create a volume outside the Helm Chart and then present it in your values file. In this example I created a custom class. Make sure accessMode is ReadWriteMany so Docker Swarm nodes can access.  

```
  volumes:
    build:
      accessMode: ReadWriteMany
      mountPath: /data/xnat/build
      storageClassName: "custom-class"
      volumeMode: Filesystem
      persistentVolumeReclaimPolicy: Retain
      persistentVolumeClaim:
        claimName: "build-xnat-xnat-web"
      size: 10Gi
```
You would need to create the custom-class storageclass and apply it first or the volume won't be created. In this case, create a file - storageclass.yaml and add the followinng contents:  

```
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: custom-class
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
```

You can then apply it:  
```
kubectl apply -f storageclass.yaml
```

Of course you may want to use an existing Storage Class so this maybe unnecessary, it is just an example.


Apply the Kubernetes volume file first and then apply the Helm chart and values file. You should now see something like the following:  

```
kubectl get -nxnat pvc,pv
NAME                                             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
persistentvolumeclaim/archive-xnat-xnat-web      Bound    archive-xnat-xnat-web                      10Gi       RWX            custom-class   5d1h
persistentvolumeclaim/build-xnat-xnat-web        Bound    build-xnat-xnat-web                        10Gi       RWX            custom-class   5d1h
persistentvolumeclaim/cache-xnat-xnat-web-0      Bound    pvc-b5b72b92-d15f-4a22-9b88-850bd726d1e2   10Gi       RWO            gp2            5d1h
persistentvolumeclaim/prearchive-xnat-xnat-web   Bound    prearchive-xnat-xnat-web                   10Gi       RWX            custom-class   5d1h

NAME                                                        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                           STORAGECLASS   REASON   AGE
persistentvolume/archive-xnat-xnat-web                      10Gi       RWX            Retain           Bound    xnat/archive-xnat-xnat-web      custom-class            5d1h
persistentvolume/build-xnat-xnat-web                        10Gi       RWX            Retain           Bound    xnat/build-xnat-xnat-web        custom-class            5d1h
persistentvolume/prearchive-xnat-xnat-web                   10Gi       RWX            Retain           Bound    xnat/prearchive-xnat-xnat-web   custom-class            5d1h
persistentvolume/pvc-b5b72b92-d15f-4a22-9b88-850bd726d1e2   10Gi       RWO            Delete           Bound    xnat/cache-xnat-xnat-web-0      gp2                     5d1h
```

As you can see, the build directory is now a mounted volume. You are now ready to mount the volumes on the Docker swarm nodes.

Depending how you presented your shared filesystem, just create the directories on the Docker swarm nodes and manager (if the manager is also a worker), add to /etc/fstab and mount the volumes.  
To make your life easier use the same file structure for the mounts - i.e build volume mounted in /data/xnat/build and archive volume mounted in /data/xnat/archive. If you don't do this you will need to specify the Docker swarm mounted XNAT directories in the XNAT GUI.


## Add your Docker Swarm to XNAT Plugin Settings
You can read about the various options in the official XNAT documentation on their website here:  
https://wiki.xnat.org/container-service/installing-and-enabling-the-container-service-in-xnat-126156821.html  
https://wiki.xnat.org/container-service/configuring-a-container-host-126156926.html  



In the XNAT GUI, go to Administer > Plugin Settings > Container Server Setup and under Docker Server setup select > New Container host.  
In our above example, for host name you would select swarm.example.com, URL would be https://swarm.example.com:2376 and certificate path would be /usr/local/tomcat/certs. As previously mentioned, it is desirable to have public CA and certificates to avoid the needs for specifying certificates at all here.  
Select Swarm Mode to "ON".  

You will need to select Path Translation if you DIDN'T mount the Docker swarm XNAT directories in the same place.  
The other options are optional.  

Once applied make sure that Status is "Up".
The Image hosts section should also now have a status of Up.  

You can now start adding your Images & Commands in the Administer > Plugin Settings > Images & Commands section.


## Troubleshooting
If you have configured docker swarm to listen on port 2376 but status says down, firstly check you can telnet or netcat to the port first locally, then remotely. From one of the nodes:  
```
nc -zv 127.0.0.1 2376
```
or 

```
telnet 127.0.0.1 2376
```

If you can, try remotely from a location that has firewall ingress access. In our example previously, try:  
```
nc -zv swarm.example.com 2376
telnet swarm.example.com 2376
```

Make sure the correct ports are open and accessible on the Docker swarm manager:

The network ports required for a Docker Swarm to function correctly are:  
TCP port 2376 for secure Docker client communication. This port is required for Docker Machine to work. Docker Machine is used to orchestrate Docker hosts.  
TCP port 2377. This port is used for communication between the nodes of a Docker Swarm or cluster. It only needs to be opened on manager nodes.  
TCP and UDP port 7946 for communication among nodes (container network discovery).  
UDP port 4789 for overlay network traffic (container ingress networking).  

Make sure docker service is started on all docker swarm nodes.  

If Status is set to Up and the container automations are failing, confirm the archive AND build shared filesystems are properly mounted on all servers - XNAT and Docker swarm. A Failed (Rejected) status for a pipeline is likely due to this error.  

In this case, as a service can't be created you won't have enough time to see the service logs with the usual:  
```
docker service ls
```
command followed by looking at the service in question, so stop the docker service on the Docker swarm node and start in the foreground, using our service example above:  
```
dockerd -H tcp://0.0.0.0:2376 --tlsverify --tlscacert /root/.docker/ca.pem --tlscert /root/.docker/server-cert.pem --tlskey /root/.docker/server-key.pem -H unix:///var/run/docker.sock
```

Then upload some dicoms and watch the processing run in the foreground.

Docker Swarm admin guide:  

https://docs.docker.com/engine/swarm/admin_guide/





