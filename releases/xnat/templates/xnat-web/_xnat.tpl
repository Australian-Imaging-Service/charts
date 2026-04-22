{{- define "xnat-web.xnat.archivePath" -}}
{{- with (index .Values "xnat-web") -}}
{{- if (kindIs "slice" .volumes) -}}
{{ .archivePath }}
{{- else -}}
{{- if .volumes.archive.mountPath -}}
{{ .volumes.archive.mountPath }}
{{- else -}}
/data/xnat/archive
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "xnat-web.xnat.prearchivePath" -}}
{{- with (index .Values "xnat-web") -}}
{{- if (kindIs "slice" .volumes) -}}
{{ .prearchivePath }}
{{- else -}}
{{- if .volumes.prearchive.mountPath -}}
{{ .volumes.prearchive.mountPath }}
{{- else -}}
/data/xnat/prearchive
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "xnat-web.xnat.siteUrl" -}}
{{- with (index .Values "xnat-web") -}}
{{- if .ingress.enabled -}}
{{- $proto := (ternary "http" "https" (empty .ingress.tls)) -}}
{{ printf "%s://%s" $proto (index .ingress.hosts 0 "host") }}
{{- else -}}
http://localhost:8080
{{- end }}
{{- end }}
{{- end -}}
