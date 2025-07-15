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

{{- define "xnat-web.postgresql.database" -}}
{{- if and (.Values.postgresql.auth.existingSecret.secretName)
           (.Values.postgresql.auth.existingSecret.database) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .Values.postgresql.auth.existingSecret.secretName }}"
    key: "{{ .Values.postgresql.auth.existingSecret.database }}"
{{- else if .Values.postgresql.auth.database -}}
value: "{{ .Values.postgresql.auth.database }}"
{{- else -}}
value: {{ required "A valid postgresql.auth.database is required!" .Values.global.postgresql.auth.database }}
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.host" -}}
{{- if and (.Values.postgresql.auth.existingSecret.secretName)
           (.Values.postgresql.auth.existingSecret.host) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .Values.postgresql.auth.existingSecret.secretName }}"
    key: "{{ .Values.postgresql.auth.existingSecret.host }}"
{{- else if .Values.postgresql.auth.host }}
value: "{{ .Values.postgresql.auth.host }}"
{{- else if .Values.global.postgresql.host }}
value: "{{ .Values.global.postgresql.host }}"
{{- else }}
value: {{ include "xnat-web.postgresql.fullname" . | quote }}
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.password" -}}
{{- if and (.Values.postgresql.auth.existingSecret.secretName)
           (.Values.postgresql.auth.existingSecret.password) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .Values.postgresql.auth.existingSecret.secretName }}"
    key: "{{ .Values.postgresql.auth.existingSecret.password }}"
{{- else if .Values.postgresql.auth.password -}}
value: "{{ .Values.postgresql.auth.password }}"
{{- else -}}
value: {{ required "A valid postgresql.auth.password is required!" .Values.global.postgresql.auth.password }}
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.port" -}}
{{- if and (.Values.postgresql.auth.existingSecret.secretName)
           (.Values.postgresql.auth.existingSecret.port) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .Values.postgresql.auth.existingSecret.secretName }}"
    key: "{{ .Values.postgresql.auth.existingSecret.port }}"
{{- else -}}
value: "5432"
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.user" -}}
{{- if and (.Values.postgresql.auth.existingSecret.secretName)
           (.Values.postgresql.auth.existingSecret.username) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .Values.postgresql.auth.existingSecret.secretName }}"
    key: "{{ .Values.postgresql.auth.existingSecret.username }}"
{{- else if .Values.postgresql.auth.username -}}
value: {{ .Values.postgresql.auth.username }}
{{- else -}}
value: {{ required "A valid postgresql.auth.username is required!" .Values.global.postgresql.auth.username }}
{{- end }}
{{- end -}}
