{{- define "xnat-web.xnat.archivePath" -}}
{{- if (index .Values "xnat-web" "volumes" "archive" "mountPath") -}}
{{ index .Values "xnat-web" "volumes" "archive" "mountPath" }}
{{- else -}}
/data/xnat/archive
{{- end -}}
{{- end -}}

{{- define "xnat-web.xnat.prearchivePath" -}}
{{- if (index .Values "xnat-web" "volumes" "prearchive" "mountPath") -}}
{{ index .Values "xnat-web" "volumes" "prearchive" "mountPath" }}
{{- else -}}
/data/xnat/prearchive
{{- end -}}
{{- end -}}

{{- define "xnat-web.xnat.siteUrl" -}}
http://localhost:8080
{{- end -}}
