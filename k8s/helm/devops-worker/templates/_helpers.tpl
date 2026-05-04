{{- define "devops-worker.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "devops-worker.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "devops-worker.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "devops-worker.labels" -}}
helm.sh/chart: {{ include "devops-worker.chart" . }}
{{ include "devops-worker.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "devops-worker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "devops-worker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "devops-worker.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "devops-worker.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Secret name for DATABASE_URL: reference an existing Secret, or the chart-managed Secret when databaseUrl.url is set.
*/}}
{{- define "devops-worker.databaseSecretName" -}}
{{- if .Values.databaseUrl.existingSecret }}
{{- .Values.databaseUrl.existingSecret }}
{{- else if .Values.databaseUrl.url }}
{{- printf "%s-database" (include "devops-worker.fullname" .) }}
{{- end }}
{{- end }}
