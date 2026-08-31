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
    key: {{ .Values.activemq.auth.secretKeys.brokerUrlKey }}
{{- end }}

{{/*
*/}}
{{- define "xnat.activemq.password" -}}
valueFrom:
  secretKeyRef:
    name: {{ include "xnat.activemq.existingSecret" . }}
    key: {{ .Values.activemq.auth.secretKeys.passwordKey }}
{{- end }}

{{/*
*/}}
{{- define "xnat.activemq.username" -}}
valueFrom:
  secretKeyRef:
    name: {{ include "xnat.activemq.existingSecret" . }}
    key: {{ .Values.activemq.auth.secretKeys.usernameKey }}
{{- end }}
