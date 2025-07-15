{{- define "xnat-web.tomcat.uid" -}}
{{- if .Values.securityContext.runAsUser -}}
{{ .Values.securityContext.runAsUser }}
{{- else if .Values.podSecurityContext.runAsUser -}}
{{ .Values.podSecurityContext.runAsUser }}
{{- else -}}
1000
{{- end }}
{{- end -}}
