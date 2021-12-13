---
linkTitle: "XNAT-Release-Testing"
title: "XNAT Release Testing as a preqrequisite to AIS 1.0"
weight: 10
draft: true
---

# XNAT Release Testing


## Introduction

### Test Plan Objectives
The aim of this document is to specify a basic framework of manual tests to be completed successfully as a pre-requisite to releasing the AIS first Helm Chart release - 1.0.  
This will provide a checklist of the majority of functions XNAT requires to work properly.
In future, automated testing is to be implmented where possible and integrated into the Helm Chart using Unit tests.


### Plugin Tests
The core plugins that AIS supports must work correctly for AIS 1.0 to be released.  

#### OpenID Plugin  
Login Successfully with AAF or Google credentials
Administer OpenID and non OpenID users (as an OpenID Administrator)  
Access projects and perform all the same procedures as local users - i.e.  
Delete sessions  
Create Sessions  
Create Projects  
Manage Projects (Define Quarantine Settings, specify Anonmyisation Settings, DICOM configuration etc)  
Manage custom variables  
Send Emails  
Add Users to a Project (Project > Access)  
Add Project roles to users (Administrator > Users)  
Add new local users and update permissions for all users


#### OHIF Viewer Plugin
View all subjects and sessions  
Play  
Magnify  
Draw / Contour  
Rotate  


#### Container Plugin  
This requires a previously working Docker Swarm or Docker host.    
The Docker Host / Swarm need access to the same shared filesystem (/data/xnat) AND specifically /data/xnat/build to process the images.  

Add Docker Server  
Add Docker Swarm Setup  
Confirm Docker Swarm and Image Hosts status is OK  
Add container image and edit images  
Edit / Add Command Configurations  
Edit / Add Command Automation  
Confirm the configuration successfully processes the images as per the directive of the commands at a project level  


#### Batch Launch Plugin
Please add any information about this plugin  

#### XSync Plugin
Successfully setup syncing between projects  
Confirm regular syncing between projects  



### Admin Tests
Administer all users  
Access projects  
Delete sessions  
Create Sessions  
Create Projects  
Manage Projects (Define Quarantine Settings, specify Anonmyisation Settings, DICOM configuration etc)  
Manage custom variables  
Send Emails  
Add Users to a Project (Project > Access)  
View OHIF images  
Delete subjects and sessions  
Container service works  
XNAT Desktop Uploader / Downloader works  
Compressed Uploader works  
DICOM SCP Receiver works  
Session snapshot creation works  
CTP HTTP Export works  (dependent on functioning CTP)  
Prearchive successfully receives images  
Prearchive can successfully archive images to Projects  


### Backend Administrator Menu Tasks
Add Project roles to users (Administrator > Users)  
Add new local users and update permissions for all users  
Email works (send email and email notifications for events) - dependent on functioning SMTP server details put into Site Administration  
Can create / Edit / Enable DICOM SCP Receivers  
Create and edit DICOM Routing  
Update Data Types  
Update Event Service  
Update Pipelines  
Update all parts of Site Administration  
Java Melody displays metrics  
REST API commands works  


### Performance Testing with JMeter 
Please add any information about this process  

