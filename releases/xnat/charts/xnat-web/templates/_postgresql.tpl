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
{{- if and .Values.postgresql.existingSecret .Values.postgresql.existingSecret.name .Values.postgresql.existingSecret.key }}
{{- $s := lookup "v1" "Secret" .Release.Namespace .Values.postgresql.existingSecret.name }}
{{- if and $s (hasKey $s.data .Values.postgresql.existingSecret.key) }}
{{- index $s.data .Values.postgresql.existingSecret.key | b64dec }}
{{- else }}
{{- .Values.postgresql.postgresqlPassword }}
{{- end }}
{{- else if .Values.global.postgresql.postgresqlPassword }}
{{- .Values.global.postgresql.postgresqlPassword }}
{{- else if and .Values.global.postgresql.auth .Values.global.postgresql.auth.password }}
{{- .Values.global.postgresql.auth.password }}
{{- else }}
{{- .Values.postgresql.postgresqlPassword }}
{{- end }}
{{- end -}}
