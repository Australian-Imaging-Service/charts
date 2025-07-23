{{- define "xnat-web.xnat.archivePath" -}}
{{- if .Values.volumes.archive.mountPath -}}
{{ .Values.volumes.archive.mountPath }}
{{- else -}}
/data/xnat/archive
{{- end -}}
{{- end -}}

{{- define "xnat-web.xnat.prearchivePath" -}}
{{- if .Values.volumes.prearchive.mountPath -}}
{{ .Values.volumes.prearchive.mountPath }}
{{- else -}}
/data/xnat/prearchive
{{- end -}}
{{- end -}}

{{- define "xnat-web.xnat.siteUrl" -}}
http://localhost:8080
{{- end -}}
