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
{{- range $provider, $c := .Values.plugin.plugins.openid.providers }}
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
  siteUrl={{ index $.Values.ingress.hosts 0 }}
  preEstablishedRedirUri=/openid-login
  {{- if eq $provider "aaf" }}
  {{- include "xnat-web.plugin.openid.provider.aaf" $ | indent 2 }}
  {{- end }}
  {{- if eq $provider "google" }}
  {{- include "xnat-web.plugin.openid.provider.google" $ | indent 2 }}
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
{{- if .Values.plugin.plugins.openid.providers.aaf.userAuthUri }}
openid.aaf.clientSecret={{ .Values.plugin.plugins.openid.providers.aaf.userAuthUri }}
{{- end }}
{{- if .Values.plugin.plugins.openid.providers.aaf.accessTokenUrl }}
openid.aaf.clientSecret={{ .Values.plugin.plugins.openid.providers.aaf.accessTokenUrl }}
{{- end }}
{{- if .Values.plugin.plugins.openid.providers.aaf.clientId }}
openid.aaf.clientId={{ .Values.plugin.plugins.openid.providers.aaf.clientId }}
{{- end }}
{{- if .Values.plugin.plugins.openid.providers.aaf.clientSecret }}
openid.aaf.clientSecret={{ .Values.plugin.plugins.openid.providers.aaf.clientSecret }}
{{- end }}
{{- if .Values.plugin.plugins.openid.providers.aaf.allowedEmailDomains }}
openid.aaf.shouldFilterEmailDomains=true
openid.aaf.allowedEmailDomains={{ .Values.plugin.plugins.openid.providers.aaf.allowedEmailDomains }}
{{- else }}
openid.aaf.shouldFilterEmailDomains=false
{{- end }}
{{- end }}

{{/*
openid google configuration
*/}}
{{- define "xnat-web.plugin.openid.provider.google" }}
{{- if .Values.plugin.plugins.openid.providers.google.userAuthUri }}
openid.google.clientSecret={{ .Values.plugin.plugins.openid.providers.google.userAuthUri }}
{{- end }}
{{- if .Values.plugin.plugins.openid.providers.google.accessTokenUrl }}
openid.google.clientSecret={{ .Values.plugin.plugins.openid.providers.google.accessTokenUrl }}
{{- end }}
{{- if .Values.plugin.plugins.openid.providers.google.clientId }}
openid.google.clientId={{ .Values.plugin.plugins.openid.providers.google.clientId }}
{{- end }}
{{- if .Values.plugin.plugins.openid.providers.google.clientSecret }}
openid.google.clientSecret={{ .Values.plugin.plugins.openid.providers.google.clientSecret }}
{{- end }}
{{- if .Values.plugin.plugins.openid.providers.google.allowedEmailDomains }}
openid.google.shouldFilterEmailDomains=true
openid.google.allowedEmailDomains={{ .Values.plugin.plugins.openid.providers.google.allowedEmailDomains }}
{{- else}}
openid.google.shouldFilterEmailDomains=false
{{- end }}
{{- end }}
