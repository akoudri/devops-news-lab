{{/*
Nom complet d'une ressource (release + composant).
Utilisation : {{ include "devops-news.fullname" (dict "root" . "component" "backend") }}
*/}}
{{- define "devops-news.fullname" -}}
{{- printf "%s-%s" .root.Release.Name .component | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Labels standards Kubernetes recommandes par la communaute.
A inclure dans metadata.labels de toutes les ressources.
Utilisation : {{ include "devops-news.labels" (dict "root" . "component" "backend") }}
*/}}
{{- define "devops-news.labels" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version }}
{{- end }}

{{/*
Selector labels (sous-ensemble des labels, utilise dans spec.selector.matchLabels).
*/}}
{{- define "devops-news.selectorLabels" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end }}

{{/*
Nom du secret Redis.
*/}}
{{- define "devops-news.redisSecretName" -}}
{{- printf "%s-redis-secret" .Release.Name }}
{{- end }}
