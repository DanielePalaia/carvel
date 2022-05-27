#!/usr/bin/env bash

set -exo pipefail

GREEN='\033[0;32m'
ORANGE='\033[0;33m'
RED='\033[0;31m'
NO_COLOR='\033[0m'

NAMESPACE=${1:-"rabbitmq-system"}
ENVIRONMENT=${ENVIRONMENT:-"openshift"}

printf "%bCreating RabbitmqCluster...%b\n" "$GREEN" "$NO_COLOR"
if [[ "$ENVIRONMENT" != "openshift" ]]; then
cat << EOF | kapp deploy -a my-tanzu-rabbit -f- -y
---
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: my-tanzu-rabbit
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  imagePullSecrets:
  - name: tanzu-rabbitmq-registry-creds
EOF
else
cat << EOF | kapp deploy -a my-tanzu-rabbit -f- -y
---
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: my-tanzu-rabbit
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  imagePullSecrets:
  - name: tanzu-rabbitmq-registry-creds
  override:
    statefulSet:
      spec:
        template:
          spec:
            containers: []
            securityContext: {}
EOF
fi

printf "%bWaiting for RabbitmqCluster to report AllReplicasReady...%b\n" "$GREEN" "$NO_COLOR"
kubectl -n "$NAMESPACE" wait --for=condition=AllReplicasReady rabbitmqcluster/my-tanzu-rabbit --timeout=20m

