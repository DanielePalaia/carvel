#!/usr/bin/env bash

set -exo pipefail

GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NO_COLOR='\033[0m'

BUNDLE_VERSION="$1"
if [ -z "$BUNDLE_VERSION" ]; then
  echo 'Please provide the semantic version of the PackageRepo you want to deploy, for example 1.2.0'
  exit 1
fi

NAMESPACE="$2"
if [ -z "$NAMESPACE" ]; then
  echo 'Please provide the Kubernetes namespace  where you want to deploy the PackageRepo'
  exit 1
fi

ENVIRONMENT=${3:-"tanzu"}

DOCKER_REGISTRY_USERNAME=${DOCKER_REGISTRY_USERNAME:-$(lpass show "Shared-RabbitMQ for Kubernetes/pivnet-dev-registry-ci" --notes | jq -r .name)}
DOCKER_REGISTRY_PASSWORD=${DOCKER_REGISTRY_PASSWORD:-$(lpass show "Shared-RabbitMQ for Kubernetes/pivnet-dev-registry-ci" --notes | jq -r .token)}

if [[ "$ENVIRONMENT" != "openshift" ]]; then

    PIVNET_API_TOKEN=${PIVNET_API_TOKEN:-$(lpass show "Shared-RabbitMQ for Kubernetes/pivnet-api-token" --password)}
    TANZU_NET_USER=${TANZU_NET_USER:-$(lpass show "Shared-RabbitMQ for Kubernetes/Pivnet user - shared" --username)}
    TANZU_NET_PASSWORD=${TANZU_NET_PASSWORD:-$(lpass show "Shared-RabbitMQ for Kubernetes/Pivnet user - shared" --password)}
    TCE_VERSION=${TCE_VERSION:-1.1.0}

    #Install Tanzu Cluster Essentials
    PLATFORM=$(uname)
    platform=$(echo $PLATFORM | tr A-Z a-z)
    printf "%bInstalling Tanzu Cluster Essentials...%b\n" "$GREEN" "$NO_COLOR"
    mkdir -p "$(pwd)"/tmp/tanzu-cluster-essentials

    install="$(pwd)"/tmp/tanzu-cluster-essentials/install.sh
    if [[ -f "$install" ]]; then
        printf "%bInstall script found, skipping download...%b\n" "$GREEN" "$NO_COLOR"
    else
        pivnet login --api-token="$PIVNET_API_TOKEN"
        pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version="$TCE_VERSION" --glob="tanzu-cluster-essentials-$platform-amd64-*.tgz" -d "$(pwd)/tmp"

        tar -xvf "$(pwd)/tmp/tanzu-cluster-essentials-$platform-amd64-$TCE_VERSION.tgz" -C "$(pwd)"/tmp/tanzu-cluster-essentials
    fi

    pushd "$(pwd)"/tmp/tanzu-cluster-essentials
    export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle:"$TCE_VERSION"
    export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
    export INSTALL_REGISTRY_USERNAME="$TANZU_NET_USER"
    export INSTALL_REGISTRY_PASSWORD="$TANZU_NET_PASSWORD"
    ./install.sh --yes
    popd

    else
      overlay_path=$(dirname -- "$0";)/openshift-overlay
      ytt -f https://github.com/vmware-tanzu/carvel-kapp-controller/releases/latest/download/release.yml -f $overlay_path/kapp-overlay.yml > $overlay_path/kapp.yml
      ytt -f https://github.com/vmware-tanzu/carvel-secretgen-controller/releases/latest/download/release.yml -f $overlay_path/secretgen-overlay.yml > $overlay_path/overlay/secretgen.yml
      kapp deploy -y -a kc -f $overlay_path/kapp.yml
      kapp deploy -y -a sg -f $overlay_path/secretgen.yml

fi

printf "%bCreating imagePullSecret & SecretExport...%b\n" "$GREEN" "$NO_COLOR"
kubectl create namespace secrets-ns
kubectl create secret docker-registry reg-creds -n secrets-ns --docker-server "dev.registry.tanzu.vmware.com" --docker-username "$DOCKER_REGISTRY_USERNAME" --docker-password "$DOCKER_REGISTRY_PASSWORD"
cat << EOF | kapp deploy -a registry-creds-export -f- -y
---
apiVersion: secretgen.carvel.dev/v1alpha1
kind: SecretExport
metadata:
  name: reg-creds
  namespace: secrets-ns
spec:
  toNamespaces:
  - "*"
EOF

printf "%bCreating ServiceAccount...%b\n" "$GREEN" "$NO_COLOR"
cat << EOF | kapp deploy -a tanzu-service-account -f- -y
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tanzu
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tanzu-rabbitmq-crd-install
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tanzu-rabbitmq-crd-install-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tanzu-rabbitmq-crd-install
subjects:
- kind: ServiceAccount
  name: tanzu
  namespace: default
EOF

printf "%bInstalling tanzu-rabbitmq repo...%b\n" "$GREEN" "$NO_COLOR"
cat << EOF | kapp deploy -a tanzu-rabbitmq-repo -f- -y
---
apiVersion: packaging.carvel.dev/v1alpha1
kind: PackageRepository
metadata:
  name: tanzu-rabbitmq-repo
spec:
  fetch:
    imgpkgBundle:
      image: dev.registry.tanzu.vmware.com/p-rabbitmq-for-kubernetes/tanzu-rabbitmq-package-repo:${BUNDLE_VERSION}
EOF
