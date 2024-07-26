#!/usr/bin/env bash
set -euxo pipefail

kubectl get event -w &
eventPid=$!
trap "kill $eventPid" EXIT
kubectl rollout status --timeout=10m sts cjoc
kubectl exec cjoc-0 -- cat /var/login/password
echo 'install suggested plugins; now you should be able to create a managed controller and a Pipeline on it like:'
echo "podTemplate {node(POD_LABEL) {sh 'cat /etc/os-release'}}"
