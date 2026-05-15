{{/*
  Banking Demo - Helm chart helpers (Phase 2). Templates dùng chung; values theo từng service trong charts/<name>/values.yaml
*/}}
{{- define "banking.namespace" -}}
{{- .Release.Namespace -}}
{{- end -}}

{{- define "banking.labels" -}}
app.kubernetes.io/name: banking
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "banking.selectorLabels" -}}
app.kubernetes.io/name: banking
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "banking.corsOrigins" -}}
{{- default "http://localhost:3000" .Values.global.corsOrigins -}}
{{- end -}}

{{- define "banking.secretName" -}}
{{- default "banking-db-secret" .Values.global.secretName -}}
{{- end -}}

{{/* --- Component helpers (values from .Values.<component>) --- */}}
{{- define "banking.postgres.fullname" -}}{{- .Values.postgres.fullnameOverride | default "postgres" -}}{{- end -}}
{{- define "banking.postgres.labels" -}}
app.kubernetes.io/name: {{ include "banking.postgres.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: postgres
{{- end -}}
{{- define "banking.postgres.selectorLabels" -}}
app.kubernetes.io/name: {{ include "banking.postgres.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "banking.redis.fullname" -}}{{- .Values.redis.fullnameOverride | default "redis" -}}{{- end -}}
{{- define "banking.redis.labels" -}}
app.kubernetes.io/name: {{ include "banking.redis.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: redis
{{- end -}}
{{- define "banking.redis.selectorLabels" -}}
app.kubernetes.io/name: {{ include "banking.redis.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "banking.kong.fullname" -}}{{- .Values.kong.fullnameOverride | default "kong" -}}{{- end -}}
{{- define "banking.kong.configMapName" -}}{{- .Values.kong.configMapName | default "kong-config" -}}{{- end -}}
{{- define "banking.kong.labels" -}}
app.kubernetes.io/name: {{ include "banking.kong.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: kong
{{- end -}}
{{- define "banking.kong.selectorLabels" -}}
app.kubernetes.io/name: {{ include "banking.kong.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "banking.auth-service.fullname" -}}{{- (index .Values "auth-service").fullnameOverride | default "auth-service" -}}{{- end -}}
{{- define "banking.auth-service.labels" -}}
app.kubernetes.io/name: {{ include "banking.auth-service.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: auth-service
{{- end -}}
{{- define "banking.auth-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "banking.auth-service.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "banking.account-service.fullname" -}}{{- (index .Values "account-service").fullnameOverride | default "account-service" -}}{{- end -}}
{{- define "banking.account-service.labels" -}}
app.kubernetes.io/name: {{ include "banking.account-service.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: account-service
{{- end -}}
{{- define "banking.account-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "banking.account-service.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "banking.transfer-service.fullname" -}}{{- (index .Values "transfer-service").fullnameOverride | default "transfer-service" -}}{{- end -}}
{{- define "banking.transfer-service.labels" -}}
app.kubernetes.io/name: {{ include "banking.transfer-service.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: transfer-service
{{- end -}}
{{- define "banking.transfer-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "banking.transfer-service.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "banking.notification-service.fullname" -}}{{- (index .Values "notification-service").fullnameOverride | default "notification-service" -}}{{- end -}}
{{- define "banking.notification-service.labels" -}}
app.kubernetes.io/name: {{ include "banking.notification-service.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: notification-service
{{- end -}}
{{- define "banking.notification-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "banking.notification-service.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "banking.frontend.fullname" -}}{{- .Values.frontend.fullnameOverride | default "frontend" -}}{{- end -}}

{{- define "banking.api-producer.fullname" -}}{{- (index .Values "api-producer").fullnameOverride | default "api-producer" -}}{{- end -}}
{{- define "banking.api-producer.labels" -}}
app.kubernetes.io/name: {{ include "banking.api-producer.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: api-producer
{{- end -}}
{{- define "banking.api-producer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "banking.api-producer.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "banking.rabbitmq.fullname" -}}{{- (index .Values "rabbitmq").fullnameOverride | default "rabbitmq" -}}{{- end -}}
{{- define "banking.rabbitmq.labels" -}}
app.kubernetes.io/name: {{ include "banking.rabbitmq.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: rabbitmq
{{- end -}}
{{- define "banking.rabbitmq.selectorLabels" -}}
app.kubernetes.io/name: {{ include "banking.rabbitmq.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "banking.frontend.labels" -}}
app.kubernetes.io/name: {{ include "banking.frontend.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: frontend
{{- end -}}
{{- define "banking.frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "banking.frontend.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

