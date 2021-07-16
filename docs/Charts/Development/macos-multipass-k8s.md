---
linktitle: "MacOS+Multipass"
title: "Development workstation with Multipass on MacOS"
author: "Fang Xu <xu.fang@sydney.edu.au>"
weight: 10
---

## Requirements
* An enabled hypervisor, either HyperKit or Virtualbox. HyperKit is the default hypervisor backend on MacOS Yosemite or later installed on a 2010 or newer Mac.
* Administrative access on Mac.

## Download, install and setup Multipass
There are two ways to install Multipass on MacOS: brew or the installer. Using brew is the simplest:
```console
$ brew install --cask multipass
```

Check Multipass version which you are running:
```console
$ multipass version 
```

Start a Multipass VM, then install Microk8s
Brew is the easiest way to install Microk8s, but it is not so easy to install an older version. At the time of writing, Microk8s latest version v1.20 seems to have problem for Ingress to attach an external IP (127.0.0.1 on Microk8s vm). We recommend manual installation. 
```console
$ multipass launch --name microk8s-vm --cpus 2 --mem 4G --disk 40G 
```

Get a shell inside the newly created VM:
```console
multipass shell microk8s-vm
```

Install Microk8s v1.19 in the VM:
```console
$ sudo snap install microk8s --classic --channel=1.19/stable
$ sudo iptables -P FORWARD ACCEPT
```

List your Multik8s VM:
```console
$ multipass list
```

Shutdown the VM
```console
$ multipass stop microk8s-vm
```

Delete and cleanup the VM:
```console
$ multipass delete microk8s-vm
$ multipass purge
```
