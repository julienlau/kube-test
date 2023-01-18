#!/bin/bash

usage () {
    echo "Usage: $0 [-n spark -s admin-sa]"
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
rm -f ${cacrt} 2>/dev/null
cluster=satest-cluster
ctx=satest-context
endpoint=`grep -B 1 "name: $(kubectx -c)" ~/.kube/config | grep server | awk '{print $NF}'`
echo "endpoint : $endpoint"
if [[ -z $endpoint ]]; then
    echo "ERROR ! endpoint is empty"
    exit 9
fi
# kubectx $ctx=$(kubectx -c)

kubectl config delete-context ${ctx}
kubectl config delete-cluster ${cluster}

tokenname=`kubectl -n ${ns} get serviceaccount/${sa} -o jsonpath='{.secrets[0].name}'`
token=`kubectl -n ${ns} get secret ${tokenname} -o jsonpath='{.data.token}'| base64 --decode`
kubectl -n ${ns} get secret ${tokenname} -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${cacrt}
cat ${cacrt} | grep CERTIFICATE
kubectl config set-cluster ${cluster} --server=${endpoint}
kubectl config set-credentials ${sa} --token=$token
kubectl config set-context ${ctx} --user=${sa} --cluster=${cluster}
kubectl config set-cluster ${cluster} --embed-certs --certificate-authority <(cat ${cacrt})
# kubectl config use-context ${ctx}
kubectx ${ctx}

rm -f ${cacrt}
