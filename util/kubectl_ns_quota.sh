#!/bin/bash

list=$(kubectl get ns -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)

for ns in $list ; do
    echo "$ns:"
    cat <<EOF | kubectl apply -n $ns -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: storage-quota
spec:
  hard:
    requests.ephemeral-storage: 50Gi
    limits.ephemeral-storage: 50Gi
EOF
done
