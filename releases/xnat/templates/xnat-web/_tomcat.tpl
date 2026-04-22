{{- define "xnat-web.tomcat.uid" -}}
{{- with (index .Values "xnat-web") -}}
{{- if .securityContext.runAsUser -}}
{{ .securityContext.runAsUser }}
{{- else if .podSecurityContext.runAsUser -}}
{{ .podSecurityContext.runAsUser }}
{{- else -}}
1000
{{- end }}
{{- end }}
{{- end -}}
