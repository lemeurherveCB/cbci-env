{{- define "fullname" -}}
{{ printf "%s-%s" .Values.name .Values.namespace | trunc 63 | trimSuffix "-" -}}
{{- end -}}
