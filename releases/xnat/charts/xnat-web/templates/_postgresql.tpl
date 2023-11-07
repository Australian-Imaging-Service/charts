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
{{- if .Values.global.postgresql.postgresqlPassword }}
{{- .Values.global.postgresql.postgresqlPassword }}
{{- else }}
{{- .Values.postgresql.postgresqlPassword }}
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.jdbc" -}}
{{- printf "jdbc:postgresql://%s/%s" (include "xnat.postgresql.fullname" .) (include "xnat.postgresql.database" .) -}}
{{- if .Values.postgresql.ssl.enabled -}}
{{- printf "?ssl=true" -}}
{{- if .Values.postgresql.ssl.mode -}}
{{- printf "&sslmode=%s" .Values.postgresql.ssl.mode -}}
{{- end -}}
{{- if .Values.postgresql.ssl.factory -}}
{{- printf "&sslfactory=%s" .Values.postgresql.ssl.factory -}}
{{- end -}}
{{- end -}}
{{- end -}}
