---
linkTitle: "Kustomize"
title: "Using Kustomize as a Post renderer for the AIS XNAT Helm Chart"
weight: 10
---

## Kustomize
Using a Helm Chart is a pretty awesome way to deploy Kubernetes infrastructure in a neatly packaged, release versioned way.  
They can be updated from the upstream repo with a single line of code and for any customisations you want to add into the deployment you specify it in a values.yaml file.  

Or at least that's how it should work. As Helm is based on templates, sometimes a value is hardcoded into the template and you can't change it in the values file.  
Your only option would have been to download the git repo that the Helm chart is based on, edit the template file in question and run it locally.  

The problem with this approach is that when a new Helm Chart is released, you have to download the chart again and then apply all of your updates.  
This becomes cumbersome and negates the advantages of Helm.  

Enter Kustomize. Kustomize can work in several ways but in this guide I will show you how to apply Kustomize as a post-renderer to update the template files to fit our environment.  
This allows you to continue to use the Helm Charts from the repo AND customise the Helm Chart templates to allow successful deployment.  

{{< alert >}}
You can read more about the Kustomize project here:  
https://kustomize.io/  
{{< /alert >}}


## Install Kustomize
Kustomize can be run as its own program using the `kustomize build` command or built into `kubectl` using `kubectl kustomize`. We are going to use the `kustomize` standalone binary.

Go here to install:  
https://kubectl.docs.kubernetes.io/installation/kustomize/binaries/  

Direct install:  
```bash
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash
```
This downloads to whatever directory you are in for whatever Operating System you are using. Copy it to `/usr/local/bin` to use it system wide:  
```bash
sudo cp kustomize /usr/local/bin
```

### How Kustomize works
When using Kustomize as a post renderer, Kustomize inputs all of the Helm Charts configuration data for a particular Chart in conjunction with the values file you specify with your cluster specific details and then amends the templates and applies them on the fly afterwards. This is why it is called a post renderer.  

Let's break this down.  

### 1. Helm template
In order to extract all of the Helm chart information, you can use the `helm template` command. In the case of our XNAT/AIS Helm chart, to extract all of this data into a file called `all.yaml` (can be any filename) you would run this command:  
```bash
helm template xnat ais/xnat > all.yaml
```

You now have the complete configuration of your Helm Chart including all template files in one file - `all.yaml`.  



### 2. `kustomization.yaml`
The next step is a `kustomization.yaml` file. This file must be called `kustomization.yaml` or Kustomize doesn't work.  
You create this and in it you specify your resources (inputs) - in our example, the resource will be `all.yaml`. The fantastic thing about Kustomize is you can add more resources in as well which combines with the Helm Chart to streamline deployment.  

For instance, in my `kustomization.yaml` file I also specify a `pv.yaml` as another resource. This has information about creating Persistent Volumes for the XNAT deployment and creates the volumes with the deployment so I don't have to apply this separately. You can do this for any resources you want to add to your deployment not included in the Helm chart.  
Example using `all.yaml` and `pv.yaml` in the `kustomization.yaml` file:  
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- all.yaml
- pv.yaml
```

The second part of the `Kustomization.yaml` file is where you specify the files that patch the templates you need to change.  
You need to specify Filename and path, name of the original template, type and version. It should be pointed out there are a lot of other ways to use Kustomize - you can read about them in some of the included articles at the end of this guide.  

Example:  
```yaml
patches:
- path: service-patch.yaml
  target:
    kind: Service
    name: xnat-xnat-web
    version: v1
```

In the above example, the file is `service-patch.yaml` and is in the same directory as `kustomization.yaml`, the name is `xnat-xnat-web`, the kind is `Service` and version is `v1`.  
Now lets look at the original `service.yaml` file to get a better idea. It is located in `charts/releases/xnat/charts/xnat-web/templates/service.yaml`: 
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "xnat-web.fullname" . }}
  labels:
    {{- include "xnat-web.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  #clusterIP: None
  ports:
    - port: {{ .Values.service.port }}
      targetPort: 8080
      protocol: TCP
      name: http
  selector:
    {{- include "xnat-web.selectorLabels" . | nindent 4 }}
  sessionAffinity: "ClientIP"
{{- if .Values.dicom_scp.recievers }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "xnat-web.fullname" . }}-dicom-scp
  labels:
    {{- include "xnat-web.labels" . | nindent 4 }}
  {{- with .Values.dicom_scp.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ .Values.dicom_scp.serviceType | quote }}
  ports:
    {{- $serviceType := .Values.dicom_scp.serviceType }}
    {{- range .Values.dicom_scp.recievers }}
    - port: {{ .port }}
      targetPort: {{ .port }}
      {{- if and (eq $serviceType "NodePort") .nodePort }}
      nodePort: {{ .nodePort }}
      {{- end }}
      {{- if and (eq $serviceType "LoadBalancer") .loadBalancerIP }}
      loadBalancerIP: {{ .loadBalancerIP }}
      {{- end }}
    {{- end }}
  selector:
    {{- include "xnat-web.selectorLabels" . | nindent 4 }}
  sessionAffinity: "ClientIP"
{{- end }}
```

### 3. The Patch file

OK, so let's have a look at our patch file and see what it is actually doing.

```yaml
- op: remove
  path: "/spec/sessionAffinity"
```

Pretty simple really. `- op: remove` just removes whatever we tell it to in our service.yaml file. If we look through our file, we find `spec` and then under that we find `sessionAffinity` and then remove that.  
In this case if we remove all the other code to simplify things you get this:  
```yaml
spec:
  sessionAffinity: "ClientIP"
```
As `sessionAffinity` is under spec by indentation it will remove the line:  
```yaml
sessionAffinity: "ClientIP"
```

In this particular case my AWS Cluster needs Service Type to be NodePort so this particular line causes the XNAT deployment to fail, hence the requirement to remove it.  
OK so far so good. You can also use `add` and `replace` operations so let's try an add command example as that is slightly more complicated.

#### Add and Replace commands example
OK continuing with our AWS NodePort example we will add a redirect from port 80 to 443 in the Ingress and replace the existing entry.    
In order to do that we need to add a second host path to the `charts/releases/xnat/charts/xnat-web/templates/ingress.yaml`. Lets look at the original file:  
```yaml
{{- if .Values.ingress.enabled -}}
{{- $fullName := include "xnat-web.fullname" . -}}
{{- $svcPort := .Values.service.port -}}
apiVersion: networking.k8s.io/v1beta1
{{- end }}
kind: Ingress
metadata:
  name: {{ $fullName }}
  labels:
    {{- include "xnat-web.labels" . | nindent 4 }}
  {{- with .Values.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if .Values.ingress.tls }}
  tls:
    {{- range .Values.ingress.tls }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      secretName: {{ .secretName }}
    {{- end }}
  {{- end }}
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
  {{- end }}
```

This is what we need in our values file to be reflected in the `ingress.yaml` file:  
```yaml
    hosts:
      - host: "xnat.example.com"
        paths: 
        - path: "/*"
          backend:
            serviceName: ssl-redirect
            servicePort: use-annotation
        - path: "/*"
          backend:
            serviceName: "xnat-xnat-web"
            servicePort: 80
```

And this is what we have at the moment in that file:  
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
```

As you can see, we are missing a second backend to allow the redirection from http to https.  
In `kustomization.yaml` add the following:  
```yaml
- path: ingress-patch.yaml
  target:
    group: networking.k8s.io
    kind: Ingress
    name: xnat-xnat-web 
    version: v1beta1
```

```yaml
# ingress-patch.yaml
#
- op: replace
  path: /spec/rules/0/http/paths/0/backend/serviceName
  value: 'ssl-redirect'
- op: replace
  path: /spec/rules/0/http/paths/0/backend/servicePort
  value: 'use-annotation'
- op: add
  path: /spec/rules/0/http/paths/-
  value: 
    path: '/*'
    backend: 
      serviceName: 'xnat-xnat-web'
      servicePort: 80
```

OK, so let's break this down. The top command replaces this:  
```yaml
serviceName: {{ $fullName }}
```
In this path:
```yaml
  rules:
      http:
        paths:
            backend:
```

With a hardcoded `serviceName` value:  
```yaml
serviceName: 'ssl-redirect'
```
I removed the extra lines to show you only the relevant section.  

The second command replaces:  
```yaml
servicePort: {{ $svcPort }}
```
In the same path, with the hardcoded value:  
```yaml
servicePort: 'use-annotation'
```

Now for the `add` command.  
```yaml
- op: add
  path: /spec/rules/0/http/paths/-
```

This will add the values in normal yaml syntax here:  
```yaml
spec:
  rules:
      http:
        paths:
          - 
```

{{% alert %}}
NB. I have removed irrelevant lines to simplify the example. If there were already two sets of path directive, replacing or adding to the second one would require this path:  
```yaml
path: /spec/rules/1/http/paths/-
```
{{% /alert %}}

OK so the resultant transformation of the `ingress.yaml` file will change it to look like this:  
```yaml
spec:
  rules:
      http:
        paths: 
          backend:
            serviceName: ssl-redirect
            servicePort: use-annotation
        - path: '/*'
          backend:
            serviceName: 'xnat-xnat-web'
            servicePort: 80
```

Let's look at our full `kustomization.yaml` file with resources and service and ingress patches.  
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- all.yaml
- pv.yaml
patches:
- path: service-patch.yaml
  target:
    kind: Service
    name: xnat-xnat-web
    version: v1
- path: ingress-patch.yaml
  target:
    group: networking.k8s.io
    kind: Ingress
    name: xnat-xnat-web 
    version: v1beta1
```

We are now ready to apply our kustomizations!  

### 4. Bringing it all together

Create a new fle called whatever you like - and make it executable, in my case we will call it `hook.sh`.  
```bash
vi hook.sh
chmod 755 hook.sh
```

```bash
#!/bin/bash
# hook.sh
#
cat <&0 > all.yaml
kustomize build && rm all.yaml
```

This takes the contents of `all.yaml` and kustomizes it using the `kustomization.yaml` file with the resources and patches I have previously described. Finally, it deletes `all.yaml`.  
When you run `kustomize build` it will look for a file called `kustomization.yaml` to apply the transformations. As the `kustomization.yaml` file is in the same directory as hook.sh only the `kustomize build` command is needed, no further directive is required.  



### 5. Deploy the Helm Chart with Kustomize post-renderer
OK to bring it all together and upgrade the XNAT AIS helm chart with your values file as `values.yaml` in the namespace `xnat`, run this command:
```bash
helm template xnat ais/xnat > all.yaml && \
  helm upgrade xnat ais/xnat -i -f values.yaml -nxnat --post-renderer=./hook.sh
```

In this case, you need to make sure that the following files are in the same directory:  
```
values.yaml  
hook.sh  
kustomization.yaml  
ingress-patch.yaml
service-patch.yaml
pv.yaml
```


## Further Reading
There are a lot of configuration options for Kustomize and this just touched on the basics.  
Kustomize is also really useful for creating dev, staging and production implementations using the same chart.  See these articles:  

* https://austindewey.com/2020/07/27/patch-any-helm-chart-template-using-a-kustomize-post-renderer/
* https://learnk8s.io/templating-yaml-with-code#using-templates-with-search-and-replace  

Nice Tutorial:  
* https://povilasv.me/helm-kustomize-better-together/






