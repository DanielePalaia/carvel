set -exo pipefail

GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NO_COLOR='\033[0m'

BUNDLE_VERSION="$1"
if [ -z "$BUNDLE_VERSION" ]; then
  echo 'Please provide the semantic version of the PackageRepo you want to deploy, for example 1.2.0'
  exit 1
fi

NAMESPACE=${2:-"rabbitmq-system"}

DOCKER_REGISTRY_USERNAME=${DOCKER_REGISTRY_USERNAME:-$(lpass show "Shared-RabbitMQ for Kubernetes/pivnet-dev-registry-ci" --notes | jq -r .name)}
DOCKER_REGISTRY_PASSWORD=${DOCKER_REGISTRY_PASSWORD:-$(lpass show "Shared-RabbitMQ for Kubernetes/pivnet-dev-registry-ci" --notes | jq -r .token)}
PIVNET_API_TOKEN=${PIVNET_API_TOKEN:-$(lpass show "Shared-RabbitMQ for Kubernetes/pivnet-api-token" --password)}
TANZU_NET_USER=${TANZU_NET_USER:-$(lpass show "Shared-RabbitMQ for Kubernetes/Pivnet user - shared" --username)}
TANZU_NET_PASSWORD=${TANZU_NET_PASSWORD:-$(lpass show "Shared-RabbitMQ for Kubernetes/Pivnet user - shared" --password)}
TCE_VERSION=${TCE_VERSION:-1.1.0}

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
