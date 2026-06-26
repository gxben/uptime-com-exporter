{{/*
Expand the name of the chart.
*/}}
{{- define "uptime-com-exporter.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "uptime-com-exporter.fullname" -}}
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

{{/*
Create chart label.
*/}}
{{- define "uptime-com-exporter.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "uptime-com-exporter.labels" -}}
helm.sh/chart: {{ include "uptime-com-exporter.chart" . }}
{{ include "uptime-com-exporter.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "uptime-com-exporter.selectorLabels" -}}
app.kubernetes.io/name: {{ include "uptime-com-exporter.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "uptime-com-exporter.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "uptime-com-exporter.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Secret name holding the API key.
*/}}
{{- define "uptime-com-exporter.secretName" -}}
{{- if .Values.uptime.existingSecret }}
{{- .Values.uptime.existingSecret }}
{{- else }}
{{- include "uptime-com-exporter.fullname" . }}
{{- end }}
{{- end }}

{{/*
Secret key holding the API key.
*/}}
{{- define "uptime-com-exporter.secretKey" -}}
{{- if .Values.uptime.existingSecret }}
{{- .Values.uptime.existingSecretKey }}
{{- else }}
api-key
{{- end }}
{{- end }}
