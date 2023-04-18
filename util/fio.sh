#!/bin/bash
# This script can be used to run several fio jobs on a k8s cluster in parallel, sequential or single mode.
# One pod will be assigned to each worker nodes.
# One PVC will be created for each jobs.

ns=default
mode=run
wait=0
single=0

# Be aware : storage class needs VOLUMEBINDINGMODE=WaitForFirstConsumer to ensure PVC and POD in the same AZ.
sc=vpcblock-wfc


usage () {
    echo "Usage: $0 [-c -s -n fio-ns -o 10.26.197.39]"
    echo "Examples:"
    echo " $0 -n fio-ns # to run in a specific namespace"
    echo " $0 -s # enable sequential mode"
    echo " $0 -o 10.26.197.39 # run only one test on one node"
    echo " $0 -c # clean a previous run"
    echo "";
}

while getopts "n:o:csh" ARGOPTS ; do
    case ${ARGOPTS} in
        c) mode=clean
            ;;
        o) single=$OPTARG
            ;;
        s) wait=1
            ;;
        n) ns=$OPTARG
            ;;
        h) usage; exit;
            ;;
        ?) usage; exit;
            ;;
    esac
done

nodes=`kubectl get nodes --no-headers | awk '{print $1}'`
if [[ "$single" != "0" ]]; then
  nodes=$single
fi
nodes=($nodes)
nreplica=`echo $nodes | wc -w`

if [[ "$mode" = "run" ]]; then
  set -e
  echo "create configmap"
  kubectl apply -n ${ns} -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: fio-config
  labels:
    app: fio
data:
  fio.cfg: |-
    ; -- start job file --
    [global]
    ioengine=libaio
    verify=0
    gtod_reduce=1
    disable_lat=0
    bs=16k
    direct=1
    buffered=0
    iodepth=256
    numjobs=1
    size=10G
    time_based=1
    runtime=120
    overwrite=1
    group_reporting=1
    ; space used by each test is : numjobs x size
    ; it is not cleaned after each job

    [randwrite16k]
    name=randwrite
    rw=randwrite
    bs=16k
    numjobs=4
    size=2G
    stonewall

    [randwrite256k]
    name=randwrite256k
    rw=randwrite
    bs=256k
    numjobs=4
    size=4G
    stonewall

    [randwrite10m]
    name=randwrite10m
    rw=randwrite
    bs=10m
    numjobs=4
    size=4G
    stonewall
    ; -- end job file --
EOF

  for ((i = 0 ; i < $nreplica ; i++)); do
    uid=`echo ${nodes[$i]} | tr -s '.' '-'`

    echo "create pvc fio-pvc-${uid}"
    kubectl apply -n ${ns} -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fio-pvc-${uid}
  labels:
    app: fio
spec:
  storageClassName: ${sc}
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${size_gigabyte}G
EOF

  selector="kubernetes.io/hostname: ${nodes[$i]}"
  #selector="kubernetes.io/os: linux"
  echo "run fio with selector : ${selector}"

  kubectl apply -n ${ns} -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  labels:
    app: fio
  name: fio-test-${uid}
spec:
  parallelism: 1
  completions: 1
  template:
    metadata:
      labels:
        app: fio
    spec:
      nodeSelector:
        ${selector}
      containers:
      - name: fio
        image: xridge/fio:latest
        imagePullPolicy: IfNotPresent
        command:
        - /bin/sh
        - -c
        - |
          echo "run : fio /opt/fio.cfg"
          cd /mnt && fio /opt/fio.cfg
        volumeMounts:
        - mountPath: /opt/
          name: fio-config-volume
          readOnly: true
        - mountPath: /mnt/
          name: fio-vol
          readOnly: false
      dnsPolicy: ClusterFirst
      restartPolicy: Never
      imagePullSecrets: 
        - name: mySecretRegistry
      volumes:
      - name: fio-vol
        persistentVolumeClaim:
          claimName: fio-pvc-${uid}
      - configMap:
          defaultMode: 420
          name: fio-config
        name: fio-config-volume
EOF

  if [[ "${wait}" != "0" ]]; then
    echo "waiting for fio job/fio-test-${uid} to complete"
    kubectl wait --for=condition=complete job/fio-test-${uid} -n ${ns} --timeout=15m
  fi
  set +e

  done


echo "kubectl logs -n ${ns} -l app=fio --tail 10000"
kubectl logs -n ${ns} -l app=fio

echo ""
echo "check logs with :"
echo 'kubectl get nodes -o custom-columns=IP:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,ZONE:".metadata.labels.ibm-cloud\.kubernetes\.io/zone",FLAVOR:".metadata.labels.ibm-cloud\.kubernetes\.io/machine-type,POOL:.metadata.labels.ibm-cloud\.kubernetes\.io/worker-pool-name,IBMID:.metadata.labels.ibm-cloud\.kubernetes\.io/instance-id" >> fio.log'
echo "kubectl get pv >> fio.log"
echo "kubectl get volumeattachments >> fio.log"
echo "for pod in \$(kubectl get pods -o custom-columns=IP:.metadata.name --no-headers -n ${ns} -l app=fio); do
echo 'podName: '\${pod} >> fio.log
kubectl get pod -n ${ns} \${pod} -o=custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName,IP:.status.podIP >> fio.log
kubectl logs -n ${ns} \${pod} >> fio.log
done
"
# grep -A 1 'randwrite16k: (grou' fio*.log | grep BW | sed 's:IOPS=: :g' | tr -s ',' ' ' | awk '{print $3}'
# grep -A 1 'randwrite256k: (grou' fio*.log | grep BW | sed 's:MB/s: :g' | tr -s '()' ' ' | awk '{print $5}'

else
  kubectl delete job -n ${ns} -l app=fio
  kubectl delete pvc -n ${ns} -l app=fio
  kubectl delete cm -n ${ns} -l app=fio
fi
