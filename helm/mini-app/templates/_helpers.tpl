{{/*
Reusable helpers. None of this renders as a manifest:
it is invoked with  {{ include "mini-app.xxx" . }}  from the other templates.
*/}}

{{/* Short chart name (overridable with nameOverride). */}}
{{- define "mini-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Full resource name.
- If the release already contains the chart name (e.g. release "mini-app"), use
  the release name alone -> resources named "mini-app".
- Otherwise, prefix with the release -> resources named "<release>-mini-app".
- 63 chars is the Kubernetes name limit.
*/}}
{{- define "mini-app.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Name of the Redis StatefulSet/Service: "<fullname>-redis". */}}
{{- define "mini-app.redis.fullname" -}}
{{- printf "%s-redis" (include "mini-app.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Labels common to every resource (app.kubernetes.io/* convention). */}}
{{- define "mini-app.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "mini-app.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Stable subset of labels used in selectors (must never change). */}}
{{- define "mini-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mini-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Name of the Secret holding the Redis password. */}}
{{- define "mini-app.redis.secretName" -}}
{{- printf "%s-redis" (include "mini-app.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
