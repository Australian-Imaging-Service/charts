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
{{- if and (.Values.postgresql.auth.existingSecret)
           (.Values.postgresql.auth.secretKeys.database) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .Values.postgresql.auth.existingSecret }}"
    key: "{{ .Values.postgresql.auth.secretKeys.database }}"
{{- else if .Values.postgresql.auth.database -}}
value: "{{ .Values.postgresql.auth.database }}"
{{- else if .Values.global.postgresql.auth.database -}}
value: {{ .Values.global.postgresql.auth.database }}
{{- else if (get .Values.postgresql "postgresqlDatabase") -}}
value: {{ get .Values.postgresql "postgresqlDatabase" }}
{{- else -}}
value: {{ required "A valid postgresql.auth.database is required!" (get .Values.global.postgresql "postgresqlDatabase") }}
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.host" -}}
{{- if and (.Values.postgresql.auth.existingSecret)
           (.Values.postgresql.auth.secretKeys.host) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .Values.postgresql.auth.existingSecret }}"
    key: "{{ .Values.postgresql.auth.secretKeys.host }}"
{{- else if .Values.postgresql.auth.host }}
value: "{{ .Values.postgresql.auth.host }}"
{{- else }}
value: {{ include "xnat-web.postgresql.fullname" . | quote }}
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.password" -}}
{{- if and (.Values.postgresql.auth.existingSecret)
           (.Values.postgresql.auth.secretKeys.password) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .Values.postgresql.auth.existingSecret }}"
    key: "{{ .Values.postgresql.auth.secretKeys.password }}"
{{- else if .Values.postgresql.auth.password -}}
value: "{{ .Values.postgresql.auth.password }}"
{{- else if .Values.global.postgresql.auth.password -}}
value: {{ .Values.global.postgresql.auth.password }}
{{- else if (get .Values.postgresql "postgresqlPassword") -}}
value: {{ get .Values.postgresql "postgresqlPassword" }}
{{- else -}}
value: {{ required "A valid postgresql.auth.password is required!" (get .Values.global.postgresql "postgresqlPassword") }}
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
{{- else if .Values.global.postgresql.auth.username -}}
value: {{ .Values.global.postgresql.auth.username }}
{{- else if (get .Values.postgresql "postgresqlUsername") -}}
value: {{ get .Values.postgresql "postgresqlUsername" }}
{{- else -}}
value: {{ required "A valid postgresql.auth.username is required!" (get .Values.global.postgresql "postgresqlUsername") }}
{{- end }}
{{- end -}}
