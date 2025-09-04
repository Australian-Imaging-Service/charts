{{/*
Create the name of the PostgreSQL service account to use
*/}}
{{- define "xnat-web.postgresql.fullname" -}}
{{- printf "%s-%s" .Release.Name "postgresql" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "xnat-web.postgresql.database" -}}
{{- if and (.Values.postgresql.auth.existingSecret)
           (.Values.postgresql.auth.secretKeys.database) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .Values.postgresql.auth.existingSecret }}"
    key: "{{ .Values.postgresql.auth.secretKeys.database }}"
{{- else if .Values.postgresql.auth.database -}}
value: "{{ .Values.postgresql.auth.database }}"
{{- else if and (index .Values "xnat-web" "postgresql") (index .Values "xnat-web" "postgresql" "postgresqlDatabase") -}}
{{ index .Values "xnat-web" "postgresql" "postgresqlDatabase" }}
{{- else -}}
value: {{ required "A valid postgresql.auth.database is required!" .Values.global.postgresql.auth.database }}
{{- end }}
{{- end }}

{{- define "xnat-web.postgresql.host" -}}
{{- if and (.Values.postgresql.auth.existingSecret)
           (.Values.postgresql.auth.secretKeys.host) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .Values.postgresql.auth.existingSecret }}"
    key: "{{ .Values.postgresql.auth.secretKeys.host }}"
{{- else if .Values.postgresql.auth.host -}}
value: "{{ .Values.postgresql.auth.host }}"
{{- else -}}
value: {{ include "xnat-web.postgresql.fullname" . | quote }}
{{- end }}
{{- end }}

{{- define "xnat-web.postgresql.password" -}}
{{- if and (.Values.postgresql.auth.existingSecret)
           (.Values.postgresql.auth.secretKeys.password) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .Values.postgresql.auth.existingSecret }}"
    key: "{{ .Values.postgresql.auth.secretKeys.password }}"
{{- else if .Values.postgresql.auth.password -}}
value: "{{ .Values.postgresql.auth.password }}"
{{- else if and (index .Values "xnat-web" "postgresql") (index .Values "xnat-web" "postgresql" "postgresqlPassword") -}}
{{ index .Values "xnat-web" "postgresql" "postgresqlPassword" }}
{{- else -}}
value: {{ required "A valid postgresql.auth.password is required!" .Values.global.postgresql.auth.password }}
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.port" -}}
{{- if and (.Values.postgresql.auth.existingSecret)
           (.Values.postgresql.auth.secretKeys.port) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .Values.postgresql.auth.existingSecret }}"
    key: "{{ .Values.postgresql.auth.secretKeys.port }}"
{{- else -}}
value: "5432"
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.user" -}}
{{- if and (.Values.postgresql.auth.existingSecret)
           (.Values.postgresql.auth.secretKeys.username) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .Values.postgresql.auth.existingSecret }}"
    key: "{{ .Values.postgresql.auth.secretKeys.username }}"
{{- else if .Values.postgresql.auth.username -}}
value: {{ .Values.postgresql.auth.username }}
{{- else if and (index .Values "xnat-web" "postgresql") (index .Values "xnat-web" "postgresql" "postgresqlUsername") -}}
{{ index .Values "xnat-web" "postgresql" "postgresqlUsername" }}
{{- else -}}
value: {{ required "A valid postgresql.auth.username is required!" .Values.global.postgresql.auth.username }}
{{- end }}
{{- end -}}
