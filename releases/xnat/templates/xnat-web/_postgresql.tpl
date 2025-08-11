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
{{- index .Values "xnat-web" "postgresql" "postgresqlDatabase" }}
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.postgresqlUsername" -}}
{{- if .Values.global.postgresql.postgresqlUsername }}
{{- .Values.global.postgresql.postgresqlUsername }}
{{- else }}
{{- index .Values "xnat-web" "postgresql" "postgresqlUsername" }}
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.postgresqlPassword" -}}
{{- if .Values.global.postgresql.postgresqlPassword }}
{{- .Values.global.postgresql.postgresqlPassword }}
{{- else }}
{{- index .Values "xnat-web" "postgresql" "postgresqlPassword" }}
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.database" -}}
{{- with (index .Values "xnat-web") -}}
{{- if and (.postgresql.auth.existingSecret)
           (.postgresql.auth.secretKeys.database) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .postgresql.auth.existingSecret }}"
    key: "{{ .postgresql.auth.secretKeys.database }}"
{{- else if .postgresql.auth.database -}}
value: "{{ .postgresql.auth.database }}"
{{- else -}}
value: {{ required "A valid postgresql.auth.database is required!" $.Values.global.postgresql.auth.database }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.host" -}}
{{- with (index .Values "xnat-web") -}}
{{- if and (.postgresql.auth.existingSecret)
           (.postgresql.auth.secretKeys.host) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .postgresql.auth.existingSecret }}"
    key: "{{ .postgresql.auth.secretKeys.host }}"
{{- else if .postgresql.auth.host }}
value: "{{ .postgresql.auth.host }}"
{{- else }}
value: {{ include "xnat-web.postgresql.fullname" $ | quote }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.password" -}}
{{- with (index .Values "xnat-web") -}}
{{- if and (.postgresql.auth.existingSecret)
           (.postgresql.auth.secretKeys.password) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .postgresql.auth.existingSecret }}"
    key: "{{ .postgresql.auth.secretKeys.password }}"
{{- else if .postgresql.auth.password -}}
value: "{{ .postgresql.auth.password }}"
{{- else -}}
value: {{ required "A valid postgresql.auth.password is required!" $.Values.global.postgresql.auth.password }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.port" -}}
{{- with (index .Values "xnat-web") -}}
{{- if and (.postgresql.auth.existingSecret)
           (.postgresql.auth.secretKeys.port) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .postgresql.auth.existingSecret }}"
    key: "{{ .postgresql.auth.secretKeys.port }}"
{{- else -}}
value: "5432"
{{- end }}
{{- end }}
{{- end -}}

{{- define "xnat-web.postgresql.user" -}}
{{- with (index .Values "xnat-web") -}}
{{- if and (.postgresql.auth.existingSecret)
           (.postgresql.auth.secretKeys.username) -}}
valueFrom:
  secretKeyRef:
    name: "{{ .postgresql.auth.existingSecret }}"
    key: "{{ .postgresql.auth.secretKeys.username }}"
{{- else if .postgresql.auth.username -}}
value: {{ .postgresql.auth.username }}
{{- else -}}
value: {{ required "A valid postgresql.auth.username is required!" $.Values.global.postgresql.auth.username }}
{{- end }}
{{- end }}
{{- end -}}
