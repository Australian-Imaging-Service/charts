{{/*
Expand the name of the chart.
*/}}
{{- define "xnat-web.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "xnat-web.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "xnat-web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "xnat-web.labels" -}}
helm.sh/chart: {{ include "xnat-web.chart" . }}
{{ include "xnat-web.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "xnat-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "xnat-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
StatefulSet labels
*/}}
{{- define "xnat-web.statefulsetLabels" -}}
{{ include "xnat-web.selectorLabels" . }}
version: {{ .Chart.AppVersion | quote }}
app: {{ include "xnat-web.name" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "xnat-web.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "xnat-web.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Converty yaml to xnat configuration syntax
*/}}
{{- define "xnat-web.envify" -}}
{{- $prefix := index . 0 -}}
{{- $value := index . 1 -}}
{{- if kindIs "map" $value -}}
  {{- range $k, $v := $value -}}
    {{- if $prefix -}}
      {{- template "xnat-web.envify" (list (printf "%s.%s" $prefix $k) $v) -}}
    {{- else -}}
      {{- template "xnat-web.envify" (list (printf "%s" $k) $v) -}}
    {{- end -}}
  {{- end -}}
{{- else -}}
{{ $prefix }}={{ $value }}
{{ end -}}
{{- end -}}
