{{- define "xnat-web.plugin.values" -}}
{{- $ := index . 0 }}
{{- $plugin := index . 2 }}

{{- with index . 1 }}
{{- if eq $plugin "ldap-auth-plugin" }}
  {{- eq .address "" |ternary dict (merge . $.Values.plugin_defaults.ldap) |toJson }}
{{- else if eq $plugin "openid-auth-plugin" }}
  {{- eq .siteUrl "" |ternary dict (merge . $.Values.plugin_defaults.openid) |toJson }}
{{- else }}
  {{- . |toJson }}
{{- end }}
{{- end }}
{{- end -}}
