{{- define "xnat.postgresql.fullname" -}}
{{- printf "%s-%s" .Release.Name "postgresql" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "xnat.postgresql.databaseKey" -}}
{{- coalesce .Values.global.postgresql.auth.secretKeys.databaseKey
             .Values.postgresql.auth.secretKeys.databaseKey
             | default "" -}}
{{- end -}}

{{- define "xnat.postgresql.hostKey" -}}
{{- coalesce .Values.global.postgresql.auth.secretKeys.hostKey
             .Values.postgresql.auth.secretKeys.hostKey
             | default "" -}}
{{- end -}}

{{- define "xnat.postgresql.passwordKey" -}}
{{- coalesce .Values.global.postgresql.auth.secretKeys.userPasswordKey
             .Values.postgresql.auth.secretKeys.userPasswordKey
             | default "" -}}
{{- end -}}

{{- define "xnat.postgresql.portKey" -}}
{{- coalesce .Values.global.postgresql.auth.secretKeys.portKey
             .Values.postgresql.auth.secretKeys.portKey
             | default "" -}}
{{- end -}}

{{- define "xnat.postgresql.usernameKey" -}}
{{- coalesce .Values.global.postgresql.auth.secretKeys.usernameKey
             .Values.postgresql.auth.secretKeys.usernameKey
             | default "" -}}
{{- end -}}

{{- define "xnat.postgresql.existingSecret" -}}
{{- coalesce .Values.global.postgresql.auth.existingSecret
             .Values.postgresql.auth.existingSecret
             | default "" -}}
{{- end -}}

{{- define "xnat.postgresql.database" -}}
{{- $existingSecret := include "xnat.postgresql.existingSecret" . -}}
{{- $databaseKey := include "xnat.postgresql.databaseKey" . -}}
{{- if and $existingSecret $databaseKey -}}
valueFrom:
  secretKeyRef:
    name: {{ $existingSecret | quote }}
    key: {{ $databaseKey | quote }}
{{- else -}}
{{- $postgresql := index .Values "xnat-web" "postgresql" | default dict -}}
value: {{ coalesce .Values.global.postgresql.postgresqlDatabase $postgresql.postgresqlDatabase
                   .Values.global.postgresql.auth.database .Values.postgresql.auth.database }}
{{- end }}
{{- end -}}

{{- define "xnat.postgresql.host" -}}
{{- $existingSecret := include "xnat.postgresql.existingSecret" . -}}
{{- $hostKey := include "xnat.postgresql.hostKey" . -}}
{{- if and $existingSecret $hostKey -}}
valueFrom:
  secretKeyRef:
    name: {{ $existingSecret | quote }}
    key: {{ $hostKey | quote }}
{{- else -}}
value: {{ coalesce .Values.postgresqlExternalName
                   .Values.global.postgresql.auth.host .Values.postgresql.auth.host
                   (include "xnat.postgresql.fullname" .) }}
{{- end }}
{{- end -}}

{{- define "xnat.postgresql.password" -}}
{{- $existingSecret := (include "xnat.postgresql.existingSecret" .) -}}
{{- if $existingSecret -}}
valueFrom:
  secretKeyRef:
    name: {{ $existingSecret }}
    key: {{ include "xnat.postgresql.passwordKey" . }}
{{- else -}}
valueFrom:
  secretKeyRef:
    name: {{ include "xnat.postgresql.fullname" . }}
    key: {{ include "xnat.postgresql.passwordKey" . }}
{{- end }}
{{- end -}}

{{- define "xnat.postgresql.port" -}}
{{- $existingSecret := include "xnat.postgresql.existingSecret" . -}}
{{- $portKey := include "xnat.postgresql.portKey" . -}}
{{- if and $existingSecret $portKey -}}
valueFrom:
  secretKeyRef:
    name: {{ $existingSecret | quote }}
    key: {{ $portKey | quote }}
{{- else -}}
value: {{ coalesce .Values.global.postgresql.auth.port
                   .Values.postgresql.auth.port
                   "5432"
                   | quote }}
{{- end }}
{{- end -}}

{{- define "xnat.postgresql.user" -}}
{{- $existingSecret := include "xnat.postgresql.existingSecret" . -}}
{{- $usernameKey := include "xnat.postgresql.usernameKey" . -}}
{{- if and $existingSecret $usernameKey -}}
valueFrom:
  secretKeyRef:
    name: {{ $existingSecret | quote }}
    key: {{ $usernameKey | quote }}
{{- else -}}
{{- $postgresql := index .Values "xnat-web" "postgresql" | default dict -}}
value: {{ coalesce .Values.global.postgresql.postgresqlUsername $postgresql.postgresqlUsername
                   .Values.global.postgresql.auth.username .Values.postgresql.auth.username }}
{{- end }}
{{- end -}}
