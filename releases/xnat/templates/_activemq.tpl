{{/*
*/}}
{{- define "xnat.activemq.brokerUrl" -}}
valueFrom:
  secretKeyRef:
    name: {{ .Values.activemq.auth.existingSecret }}
    key: {{ .Values.activemq.auth.secretKeys.brokerUrlKey }}
{{- end }}

{{/*
*/}}
{{- define "xnat.activemq.password" -}}
valueFrom:
  secretKeyRef:
    name: {{ .Values.activemq.auth.existingSecret }}
    key: {{ .Values.activemq.auth.secretKeys.passwordKey }}
{{- end }}

{{/*
*/}}
{{- define "xnat.activemq.username" -}}
valueFrom:
  secretKeyRef:
    name: {{ .Values.activemq.auth.existingSecret }}
    key: {{ .Values.activemq.auth.secretKeys.usernameKey }}
{{- end }}
