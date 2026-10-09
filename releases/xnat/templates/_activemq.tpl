{{/*
*/}}
{{- define "xnat.activemq.existingSecret" -}}
{{ printf "%s-apache-artemis" .Release.Name }}
{{- end }}

{{/*
*/}}
{{- define "xnat.activemq.brokerUrl" -}}
valueFrom:
  secretKeyRef:
    name: {{ include "xnat.activemq.existingSecret" . }}
    key: {{ index .Values "apache-artemis" "auth" "secretKeys" "brokerUrlKey" }}
{{- end }}

{{/*
*/}}
{{- define "xnat.activemq.password" -}}
valueFrom:
  secretKeyRef:
    name: {{ include "xnat.activemq.existingSecret" . }}
    key: {{ index .Values "apache-artemis" "auth" "secretKeys" "passwordKey" }}
{{- end }}

{{/*
*/}}
{{- define "xnat.activemq.username" -}}
valueFrom:
  secretKeyRef:
    name: {{ include "xnat.activemq.existingSecret" . }}
    key: {{ index .Values "apache-artemis" "auth" "secretKeys" "usernameKey" }}
{{- end }}

{{/*
*/}}
{{- define "xnat.activemq.configured" -}}
{{- with index .Values "apache-artemis" -}}
{{- if or .enabled .auth.existingSecret -}}true{{- end -}}
{{- end -}}
{{- end -}}
