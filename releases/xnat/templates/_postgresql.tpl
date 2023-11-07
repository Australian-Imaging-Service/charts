{{/*
Create the name of the PostgreSQL service account to use
*/}}
{{- define "xnat.postgresql.fullname" -}}
{{- printf "%s-%s" .Release.Name "postgresql" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "xnat.postgresql.database" -}}
{{- if .Values.global.postgresql.auth.database }}
{{- .Values.global.postgresql.auth.database }}
{{- else if .Values.global.postgresql.postgresqlDatabase }}
{{- .Values.global.postgresql.postgresqlDatabase }}
{{- else }}
{{- .Values.postgresql.postgresqlDatabase }}
{{- end }}
{{- end -}}

{{- define "xnat.postgresql.PGPASSWORD" -}}
{{- if .Values.global.postgresql.auth.existingSecret -}}
valuesFrom:
  secretKeyRef:
    name: {{ .Values.global.postgresql.auth.existingSecret }}
    key: {{ .Values.global.postgresql.auth.secretKeys.userPasswordKey }}
{{- else -}}
value: {{ template "xnat.postgresql.password" . }}
{{- end -}}
{{- end -}}

{{- define "xnat.postgresql.password" -}}
{{- if .Values.global.postgresql.auth.existingSecret }}
${PGPASSWORD}
{{- else if .Values.global.postgresql.auth.password }}
{{- .Values.global.postgresql.auth.password }}
{{- else if .Values.global.postgresql.postgresqlPassword }}
{{- .Values.global.postgresql.postgresqlPassword }}
{{- else }}
{{- .Values.postgresql.postgresqlPassword }}
{{- end }}
{{- end -}}

{{- define "xnat.postgresql.port" -}}
{{- if .Values.global.postgresql.service.ports.postgresql }}
{{- .Values.global.postgresql.service.ports.postgresql }}
{{- else }}
5432
{{- end }}
{{- end -}}

{{- define "xnat.postgresql.username" -}}
{{- if .Values.global.postgresql.auth.username }}
{{- .Values.global.postgresql.auth.username }}
{{- else if .Values.global.postgresql.postgresqlUsername }}
{{- .Values.global.postgresql.postgresqlUsername }}
{{- else }}
{{- .Values.postgresql.postgresqlUsername }}
{{- end }}
{{- end -}}
