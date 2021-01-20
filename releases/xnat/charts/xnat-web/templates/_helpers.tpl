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
Create the name of the PostgreSQL service account to use
*/}}
{{- define "xnat-web.postgresql.fullname" -}}
{{- printf "%s-%s" .Release.Name "postgresql" | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- define "xnat-web.postgresql.postgresqlDatabase" -}}
{{- if .Values.global.postgresql.postgresqlDatabase }}
{{- .Values.global.postgresql.postgresqlDatabase }}
{{- else }}
{{- .Values.postgresql.postgresqlDatabase }}
{{- end }}
{{- end -}}
{{- define "xnat-web.postgresql.postgresqlUsername" -}}
{{- if .Values.global.postgresql.postgresqlUsername }}
{{- .Values.global.postgresql.postgresqlUsername }}
{{- else }}
{{- .Values.postgresql.postgresqlUsername }}
{{- end }}
{{- end -}}
{{- define "xnat-web.postgresql.postgresqlPassword" -}}
{{- if .Values.global.postgresql.postgresqlPassword }}
{{- .Values.global.postgresql.postgresqlPassword }}
{{- else }}
{{- .Values.postgresql.postgresqlPassword }}
{{- end }}
{{- end -}}

{{- define "xnat-web.auth.openid.providers" -}}
{{- $openid_providers := dict -}}
{{- range $provider, $p := . -}}
  {{- if $p.clientID -}}
    {{- $_ := set $openid_providers $provider $p -}}
  {{- end -}}
{{- end -}}
{{- $openid_providers -}}
{{- end -}}
