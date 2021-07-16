---
title: "Windows 10+Multipass"
author: "Dean Taylor <dean.taylor@uwa.edu.au>"
weight: 10
---
# Development workstation with [Multipass](https://multipass.run/) on Windows 10

Requirements:

* An enabled Hypervisor, either Hyper-V (recommended) or VirtualBox (introduces certain networking issues, if you are using VirtualBox on Windows 10 then use the VirtualBox UI directly or another package such as [Vagrant](https://www.vagrantup.com/))
  * [Install Hyper-V on Windows 10](https://docs.microsoft.com/en-us/virtualization/hyper-v-on-windows/quick-start/enable-hyper-v)
  * [Oracle VirtualBox install on Windows hosts](https://www.virtualbox.org/manual/UserManual.html#installation_windows)
    * [Oracle VirtualBox Downloads](https://www.virtualbox.org/wiki/Downloads)
* Administrative access to Windows 10 workstation. This is required for:
  * Enabling Hyper-V if not already configured, or installing Oracle VirtualBox
  * Installing Multipass
  * Altering the local DNS override file `c:\Windows\Ssytem32\drivers\etc\hosts`

### Windows PowerShell console as Administrator

Right click `Windows PowerShell` and select `Run as Administrator`, enter your Admin credentials. From the `Administrator: Windows PowerShell` console perform the following.

* Open the DNS `hosts` file for editing.
  * *WARNING* edit this file with care and ensure that you only append entries while leaving the original entries intact.
  * *WARNING* also be aware that you have started Notepad as an Administrator allowing this application to be able to edit any file on your system. Close the editor and PowerShell console if you intend to leave your workstation!

```console
PS C:\> notepad.exe C:\Windows\System32\drivers\etc\hosts
```

* Verify Hyper-V state; the bellow shows that Hyper-V is Enabled on this workstation

```console
PS C:\> Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online

FeatureName      : Microsoft-Hyper-V-All
DisplayName      : Hyper-V
Description      : Provides services and management tools for creating and running virtual machines and their
                   resources.
RestartRequired  : Possible
State            : Enabled
CustomProperties :
```

  If this is not the case!

```console
PS C:\> Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

## Download, install and setup Multipass

From the [Multipass website](https://multipass.run/), verify that your Windows 10 workstation meets the minimum requirements and then download the Windows installation file.

1. Select `Start` button and then select Settings.
2. In `Settings`, select `System > About` or type about in the search box.
3. Under `Windows specifications` verify `Edition` and `Version`

Follow the installation instructions from the Multipass site selecting the preferred Hypervisor.

*NB:* The Environment variable that configure the search PATH to find the Multipass binaries will not be available until you `logout` and log back in.

## Edit the workstations local DNS lookup/override file

This is required to direct your workstations browser and other clients to the development VM which runs your CTP and/or XNAT service.

For each service requiring a DNS entry you will need to add an entry into your `hosts` file. From your Notepad application opened as an Administrator you will need to enter the following.

```C:\Windows\System32\drivers\etc\hosts
IP_Address_of_the_VM	fqdn.service.name fqdn2.service.name
```

Get the IP address of your VM

```console
PS C:\> multipass exec vm-name -- ip addr
```

So if your VM's IP address is `192.168.11.93` and your service FQDN is `xnat.cmca.dev.local` add the following entry into `C:\Windows\System32\drivers\etc\hosts` file and save.

```C:\Windows\System32\drivers\etc\hosts
192.168.11.93	xnat.cmca.dev.local
```
## Launch Ubuntu 20.04 LTS (Focal) with AIS development tools

NB: This may take some time

```console
PS C:\Users\00078081\ais> Invoke-WebRequest https://raw.githubusercontent.com/Australian-Imaging-Service/charts/main/contrib/cloud-init/user-data-dev-microk8s.yaml -OutFile user-data-dev-microk8s.yaml
PS C:\Users\00078081\ais> multipass launch --cpus 4 --mem 2G -nais-dev --cloud-init .\user-data-dev-microk8s.yaml
```
