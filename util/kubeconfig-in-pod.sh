#!/bin/bash
# This script should be launched from a running pod with sudo permissions

KUBERNETES_SERVICE_HOST=kubernetes.default.svc
KUBERNETES_SERVICE_PORT=443

usage () {
    echo "Usage: $0 [-u kubernetes.default.svc -p 443]"
    echo "";
}

while getopts "p:u:h" ARGOPTS ; do
    case ${ARGOPTS} in
        p) KUBERNETES_SERVICE_PORT=$OPTARG
            ;;
        u) KUBERNETES_SERVICE_HOST=$OPTARG
            ;;
        h) usage; exit;
            ;;
        ?) usage; exit;
            ;;
    esac
done

SERVICE_ACCOUNT_DIR="/var/run/secrets/kubernetes.io/serviceaccount"
KUBERNETES_SERVICE_SCHEME=$(case $KUBERNETES_SERVICE_PORT in 80|8080|8081) echo "http";; *) echo "https"; esac)
KUBERNETES_SERVER_URL="$KUBERNETES_SERVICE_SCHEME"://"$KUBERNETES_SERVICE_HOST":"$KUBERNETES_SERVICE_PORT"
KUBERNETES_CLUSTER_CA_FILE="$SERVICE_ACCOUNT_DIR"/ca.crt
KUBERNETES_NAMESPACE=$(cat "$SERVICE_ACCOUNT_DIR"/namespace)
KUBERNETES_USER_TOKEN=$(cat "$SERVICE_ACCOUNT_DIR"/token)
KUBERNETES_CONTEXT="inCluster"

mkdir -p "$HOME"/.kube
cat << EOF > "$HOME"/.kube/config
apiVersion: v1
kind: Config
preferences: {}
current-context: $KUBERNETES_CONTEXT

clusters:
- cluster:
    server: $KUBERNETES_SERVER_URL
    caFile: $KUBERNETES_CLUSTER_CA_FILE
  name: inCluster

users:
- name: podServiceAccount
  user:
    token: $KUBERNETES_USER_TOKEN

contexts:
- context:
    cluster: inCluster
    user: podServiceAccount
    namespace: $KUBERNETES_NAMESPACE
  name: $KUBERNETES_CONTEXT
EOF

sudo cp ${KUBERNETES_CLUSTER_CA_FILE} /usr/local/share/ca-certificates/kube.crt
sudo update-ca-certificates
