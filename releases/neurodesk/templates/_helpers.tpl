{{/*
Common template helpers for the neurodesk chart.
*/}}

{{/* Chart name, overridable. */}}
{{- define "neurodesk.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified app name. */}}
{{- define "neurodesk.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Chart label value (name-version). */}}
{{- define "neurodesk.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Namespace the chart deploys into. */}}
{{- define "neurodesk.namespace" -}}
{{- default .Release.Namespace .Values.namespace.name -}}
{{- end -}}

{{/* Standard labels applied to all in-house resources. */}}
{{- define "neurodesk.labels" -}}
helm.sh/chart: {{ include "neurodesk.chart" . }}
{{ include "neurodesk.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: neurodesk
{{- end -}}

{{- define "neurodesk.selectorLabels" -}}
app.kubernetes.io/name: {{ include "neurodesk.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Effective StorageClass for an in-house PVC: explicit arg, else
global.storageClassName, else "" (cluster default).
Usage: {{ include "neurodesk.storageClass" (list . .Values.cvmfs.squid.storageClassName) }}
*/}}
{{- define "neurodesk.storageClass" -}}
{{- $root := index . 0 -}}
{{- $explicit := index . 1 -}}
{{- if $explicit -}}
{{- $explicit -}}
{{- else -}}
{{- $root.Values.global.storageClassName -}}
{{- end -}}
{{- end -}}

{{/* CVMFS_HTTP_PROXY value: squid service when enabled, else DIRECT.
     (The cvmfs-csi default.local ConfigMap renders the same expression inline
     from global.cvmfs.squidEnabled; this helper mirrors it for any parent use.) */}}
{{- define "neurodesk.cvmfsHttpProxy" -}}
{{- if .Values.global.cvmfs.squidEnabled -}}
http://cvmfs-squid.{{ include "neurodesk.namespace" . }}.svc.cluster.local:3128;DIRECT
{{- else -}}
DIRECT
{{- end -}}
{{- end -}}

{{/*
XNAT host as seen from inside the cluster: xnat.server.host, or the in-cluster
Service of the AIS xnat chart installed in the SAME release (the AIS umbrella
names it <release>-xnat-web).
*/}}
{{- define "neurodesk.xnatHost" -}}
{{- .Values.xnat.server.host | default (printf "%s-xnat-web" .Release.Name) -}}
{{- end -}}

{{/* ServiceAccount the z2jh hub runs as (for RBAC this chart adds). */}}
{{- define "neurodesk.hubServiceAccount" -}}
{{- /* The ServiceAccount the hub Deployment runs as: z2jh's own helper, called
       with a context that looks like the jupyterhub subchart's (its values,
       Chart.Name "jupyterhub"). z2jh's parent-chart shortcut is not enough: with
       fullnameOverride null it would use this chart's name, not "jupyterhub". */ -}}
{{- include "jupyterhub.hub-serviceaccount.fullname" (dict "Values" .Values.jupyterhub "Chart" (dict "Name" "jupyterhub") "Release" .Release) -}}
{{- end -}}

{{- /* integration.json for the hub (servers launched from XNAT, AAF login), or
       "" when both are off. Shared by the ConfigMap and the hub reload hook. */ -}}
{{- define "neurodesk.hubIntegrationConfig" -}}
{{- $x := .Values.xnat | default dict -}}
{{- $xj := dig "jupyterhub" (dict) $x -}}
{{- $xnatHub := and .Values.jupyterhub.enabled $x.enabled (dig "enabled" false $xj) -}}
{{- $aaf := dig "aaf" (dict) (.Values.auth | default dict) -}}
{{- $aafOn := and .Values.jupyterhub.enabled (dig "enabled" false $aaf) -}}
{{- $ns := include "neurodesk.namespace" . -}}
{{- $host := include "neurodesk.xnatHost" . -}}
{{- if or $xnatHub $aafOn }}
{{- $cfg := dict -}}
{{- if $xnatHub }}
{{- $_ := set $cfg "xnat" (dict
      "url" ($xj.url | default (printf "http://%s" $host))
      "namespace" $ns
      "credentialsSecret" ($xj.credentialsSecret | default (printf "%s-xnat-web-admin" .Release.Name))
      "usernameKey" ($xj.usernameKey | default "username")
      "passwordKey" ($xj.passwordKey | default "password")
      "archivePvc" ($xj.archivePvc | default (printf "%s-xnat-web-archive" .Release.Name))
      "archiveMountPath" ($xj.archiveMountPath | default "/data/xnat/archive")
      "archiveGid" (int (dig "archiveGid" 65534 $xj))
      "homeMountPath" (dig "singleuser" "storage" "homeMountPath" "/home/jovyan" (.Values.jupyterhub | default dict))
      "uid" (int ($xj.uid | default 1000))
      "gid" (int ($xj.gid | default 100))
      "requestTimeoutSeconds" (int ($xj.requestTimeoutSeconds | default 10))
      "failOpen" (dig "failOpen" false $xj)) -}}
{{- end }}
{{- if $aafOn }}
{{- $_ := set $cfg "aaf" (dict
      "clientId" $aaf.clientId
      "callbackUrl" $aaf.callbackUrl
      "usernamePrefix" (dig "usernamePrefix" "aaf_" $aaf)
      "usernameClaim" (dig "usernameClaim" "sub" $aaf)
      "allowAll" (dig "allowAll" true $aaf)
      "issuer" (dig "issuer" "https://central.aaf.edu.au" $aaf)) -}}
{{- end }}
{{- toJson $cfg -}}
{{- end }}
{{- end -}}

{{- /* Fingerprint of everything the hub reads only at start-up: the integration
       settings and the shipped Python. "none" when the integrations are off. */ -}}
{{- define "neurodesk.hubIntegrationChecksum" -}}
{{- $cfg := include "neurodesk.hubIntegrationConfig" . -}}
{{- if $cfg -}}
{{- printf "%s\n%s" $cfg (.Files.Get "files/hub/neurodesk_integrations.py") | sha256sum | trunc 16 -}}
{{- else -}}
none
{{- end -}}
{{- end -}}
