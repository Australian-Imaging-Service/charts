{{- define "xnat-web.auth.openid.providers" -}}
{{- $openid_providers := dict -}}
{{- range $provider, $p := . -}}
  {{- if $p.clientID -}}
    {{- $_ := set $openid_providers $provider $p -}}
  {{- end -}}
{{- end -}}
{{- $openid_providers -}}
{{- end -}}

{{- define "xnat-web.plugin.openid" }}
{{- range $provider, $c := (index .Values "xnat-web" "plugin" "plugins" "openid" "providers") }}
{{- if empty $c.clientId }}
{{- else }}
openid-provider-{{ $provider }}.properties: |
  name=OpenID Authentication Provider
  auth.method=openid
  type=openid
  provider.id={{ $provider }}
  visible=true
  auto.enabled=true
  auto.verified=true
  disableUsernamePasswordLogin=false
  siteUrl={{ index .ingress.hosts 0 }}
  preEstablishedRedirUri=/openid-login
  {{- if eq $provider "aaf" }}
  {{- include "xnat-web.plugin.openid.provider.aaf" . | indent 2 }}
  {{- end }}
  {{- if eq $provider "google" }}
  {{- include "xnat-web.plugin.openid.provider.google" . | indent 2 }}
  {{- end }}
  openid.{{ $provider }}.scopes=openid,profile,email
  openid.{{ $provider }}.link=<p>To sign-in as an <b>external user</b> using your {{ upper $provider }} credentials, please click on the button below.</p><p><a href="/openid-login?providerId={{ $provider }}"><img src="/images/{{ $provider }}_service_223x54.png" /></a></p>
  openid.{{ $provider }}.forceUserCreate=true
  openid.{{ $provider }}.userAutoEnabled=true
  openid.{{ $provider }}.userAutoVerified=true
  openid.{{ $provider }}.emailProperty=email
  openid.{{ $provider }}.givenNameProperty=given_name
  openid.{{ $provider }}.familyNameProperty=family_name
{{- end }}
{{- end }}
{{- end }}

{{/*
openid aaf configuration
*/}}
{{- define "xnat-web.plugin.openid.provider.aaf" }}
{{- with (index .Values "xnat-web") -}}
{{- if .plugin.plugins.openid.providers.aaf.userAuthUri }}
openid.aaf.clientSecret={{ .plugin.plugins.openid.providers.aaf.userAuthUri }}
{{- end }}
{{- if .plugin.plugins.openid.providers.aaf.accessTokenUrl }}
openid.aaf.clientSecret={{ .plugin.plugins.openid.providers.aaf.accessTokenUrl }}
{{- end }}
{{- if .plugin.plugins.openid.providers.aaf.clientId }}
openid.aaf.clientId={{ .plugin.plugins.openid.providers.aaf.clientId }}
{{- end }}
{{- if .plugin.plugins.openid.providers.aaf.clientSecret }}
openid.aaf.clientSecret={{ .plugin.plugins.openid.providers.aaf.clientSecret }}
{{- end }}
{{- if .plugin.plugins.openid.providers.aaf.allowedEmailDomains }}
openid.aaf.shouldFilterEmailDomains=true
openid.aaf.allowedEmailDomains={{ .plugin.plugins.openid.providers.aaf.allowedEmailDomains }}
{{- else }}
openid.aaf.shouldFilterEmailDomains=false
{{- end }}
{{- end }}
{{- end }}

{{/*
openid google configuration
*/}}
{{- define "xnat-web.plugin.openid.provider.google" }}
{{- with (index .Values "xnat-web") -}}
{{- if .plugin.plugins.openid.providers.google.userAuthUri }}
openid.google.clientSecret={{ .plugin.plugins.openid.providers.google.userAuthUri }}
{{- end }}
{{- if .plugin.plugins.openid.providers.google.accessTokenUrl }}
openid.google.clientSecret={{ .plugin.plugins.openid.providers.google.accessTokenUrl }}
{{- end }}
{{- if .plugin.plugins.openid.providers.google.clientId }}
openid.google.clientId={{ .plugin.plugins.openid.providers.google.clientId }}
{{- end }}
{{- if .plugin.plugins.openid.providers.google.clientSecret }}
openid.google.clientSecret={{ .plugin.plugins.openid.providers.google.clientSecret }}
{{- end }}
{{- if .plugin.plugins.openid.providers.google.allowedEmailDomains }}
openid.google.shouldFilterEmailDomains=true
openid.google.allowedEmailDomains={{ .plugin.plugins.openid.providers.google.allowedEmailDomains }}
{{- else}}
openid.google.shouldFilterEmailDomains=false
{{- end }}
{{- end }}
{{- end }}
