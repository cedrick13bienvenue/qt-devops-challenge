{{- define "projecthub.labels" -}}
app.kubernetes.io/part-of: projecthub
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end }}

{{- define "projecthub.componentLabels" -}}
{{ include "projecthub.labels" .root }}
app: {{ .component }}
{{- end }}

{{- define "projecthub.selectorLabels" -}}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app: {{ .component }}
{{- end }}

{{- define "projecthub.image" -}}
{{ printf "%s/%s:%s" .root.Values.image.registry .name .root.Values.image.tag }}
{{- end }}

{{- define "projecthub.mongoUri" -}}
{{- $user := .Values.secrets.mongoRootUsername -}}
{{- $pass := required "secrets.mongoRootPassword is required" .Values.secrets.mongoRootPassword -}}
{{ printf "mongodb://%s:%s@mongodb-0.mongodb.%s.svc.cluster.local:27017/?authSource=admin" $user $pass .Release.Namespace }}
{{- end }}
