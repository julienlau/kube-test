#!/bin/bash

# If you want to configure kube-apiserver access from within a pod, please prefer using 
# either the proxy sidecar pod method 
# either the pod configuration spec.serviceAccountName=spark-sa and spec.automountServiceAccountToken=True

usage () {
    echo "Usage: $0 [-n spark -s admin-sa -t admintoken-secret)]"
    echo "Examples:"
    echo "# namespace name:"
    echo " $0 -n spark"
    echo "# serviceaccount name:"
    echo " $0 -s admin-sa"
    echo "";
}

while getopts "n:s:h" ARGOPTS ; do
    case ${ARGOPTS} in
        n) ns=$OPTARG
            ;;
        s) sa=$OPTARG
            ;;
        t) tokenname=$OPTARG
            ;;
        h) usage; exit;
            ;;
        ?) usage; exit;
            ;;
    esac
done
if [[ -z $ns || -z $sa ]]; then
    echo "2 inputs are needed : "
    echo "name of serviceaccount"
    echo "namespace"
    usage
    exit 9
fi

cacrt=tmp-kubectl_sa-cacert.pem
cluster=satest-cluster
ctx=satest-context
endpoint=https://kubernetes.default.svc:443
endpoint=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
echo "endpoint : $endpoint"
if [[ -z $endpoint ]]; then
    echo "ERROR ! endpoint is empty"
    exit 9
fi
# kubectl ctx $ctx=$(kubectx -c)

kubectl config delete-context ${ctx}
kubectl config delete-cluster ${cluster}
set -e

minVer=$(kubectl version -o json | jq '.serverVersion.minor' | tr -d '"')

# In the K8s version before 1.24, every time we would create a service account, a non-expiring secret token (Mountable secrets & Tokens) was created by default. However, from version 1.24 onwards, it was disbanded and no secret token is created by default when we create a service account. However, we can create it when need be.
if [[ $minVer -le 23 ]]; then
    tokenname=`kubectl -n ${ns} get serviceaccount/${sa} -o jsonpath='{.secrets[0].name}'`
elif [[ -z $tokenname ]]; then
    kubectl -n ${ns} create -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${sa}-token
  annotations:
    kubernetes.io/service-account.name: ${sa}
type: kubernetes.io/service-account-token
EOF
    tokenname=${sa}-token
fi

token=`kubectl -n ${ns} get secret ${tokenname} -o jsonpath='{.data.token}'| base64 --decode`
kubectl -n ${ns} get secret ${tokenname} -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${cacrt}
cat ${cacrt} | grep CERTIFICATE
kubectl config set-cluster ${cluster} --server=${endpoint}
kubectl config set-credentials ${sa} --token=$token
kubectl config set-context ${ctx} --user=${sa} --cluster=${cluster}
kubectl config set-cluster ${cluster} --embed-certs --certificate-authority <(cat ${cacrt})
rm -f ${cacrt}

# kubectl config use-context ${ctx}
kubectl ctx ${ctx}
kubectl config view --minify
