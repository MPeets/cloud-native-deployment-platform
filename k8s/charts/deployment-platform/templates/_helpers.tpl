{{/*
Chart name, truncated to the 63-character DNS label limit.
*/}}
{{- define "dp.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified release name. fullnameOverride wins when set.
*/}}
{{- define "dp.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := include "dp.name" . }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Standard labels. Selector labels stay limited to name and instance.
*/}}
{{- define "dp.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "dp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Labels used to select pods. Only name and instance, so version changes do not retarget them.
*/}}
{{- define "dp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
