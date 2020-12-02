#!/bin/bash
# Output colors
NORMAL="\033[0;39m"
RED="\e[1;31m"
BLUE="\e[1;34m"

DEFAULT_USER="adamcattermole"
DEFAULT_NAMESPACE="kafka"

#StrIoT
STRIOT_REDIS="conf/striot_redis.yaml"
STRIOT_OPERATOR="conf/striot_operator.yaml"
STRIOT_STORAGE="conf/striot_storage.yaml"

#Strimzi
STRIMZI_OPERATOR="conf/strimzi_operator.yaml"
STRIMZI_KAFKA="conf/strimzi_kafka.yaml"

#Prometheus
PROMETHEUS_OPERATOR="conf/bundle.yaml"
PROMETHEUS_INSTANCE="conf/prometheus.yaml"


get_test() {
  if [ -n "$1" ]; then
    v="$1"
  else
    error "no test selected"
    exit 1
  fi
  echo $v
}

build() {
  t=$(get_test $1) || { help ; exit ; }

  log "Building docker images for $t"
  make -C $t/deploy/docker
}


install() {
  log "Create namespace $DEFAULT_NAMESPACE"
  kubectl create namespace $DEFAULT_NAMESPACE

  log "Create storage in $DEFAULT_NAMESPACE"
  # kubectl create secret generic striot-storage-secret --from-literal=azurestorageaccountname="striotstoragesmb" --from-literal=azurestorageaccountkey="/Vgk28f/CG2Px+/MWMassyTZC4D64hopzvJEfs9+Tp/h22HoAbFye9rkO+9PpVCTc/rttNoBMmkTorMxzvrFPQ==" -n $DEFAULT_NAMESPACE
  kubectl apply -f $STRIOT_STORAGE -n $DEFAULT_NAMESPACE

  log "Deploy Strimzi operator in $DEFAULT_NAMESPACE"
  kubectl apply -f $STRIMZI_OPERATOR -n $DEFAULT_NAMESPACE

  log "Deploy Kafka in $DEFAULT_NAMESPACE"
  kubectl apply -f $STRIMZI_KAFKA -n $DEFAULT_NAMESPACE

  log "Deploy striot operator in $DEFAULT_NAMESPACE"
  kubectl apply -f $STRIOT_OPERATOR -n $DEFAULT_NAMESPACE

  log "Deploy striot-redis in $DEFAULT_NAMESPACE"
  kubectl apply -f $STRIOT_REDIS -n $DEFAULT_NAMESPACE

  log "Deploy prometheus operator in $DEFAULT_NAMESPACE"
  kubectl apply -f $PROMETHEUS_OPERATOR -n $DEFAULT_NAMESPACE

  log "Deploy prometheus in $DEFAULT_NAMESPACE"
  kubectl apply -f $PROMETHEUS_INSTANCE -n $DEFAULT_NAMESPACE

  log "Waiting for resources..."
  kubectl wait kafka/my-cluster --for=condition=Ready --timeout=300s -n kafka

  log "Done."
}

start() {
  t=$(get_test $1) || { help ; exit ; }

  log "Starting test $1 Topology in namespace $DEFAULT_NAMESPACE"
  kubectl apply -f "$1/deploy/kube/striot.org_v1alpha1_topology_cr.yaml" -n $DEFAULT_NAMESPACE
}

extract() {
  t=$(get_test $1) || { help ; exit ; }
  cal=$(date +"%Y-%m-%dT")
  now=$(date +"%H:%M:%S")

  log "Extracting throughput data..."
  curl "http://localhost:9090/api/v1/query_range?query=striot_egress_events_total&start=$cal$2.000Z&end=$cal$now.000Z&step=1s" | jq '.' > $1/data/tp/egress_$cal$now.json
  curl "http://localhost:9090/api/v1/query_range?query=striot_ingress_events_total&start=$cal$2.000Z&end=$cal$now.000Z&step=1s" | jq '.' > $1/data/tp/ingress_$cal$now.json
  
  log "Extracting latency data..."
  kubectl cp -n kafka `kubectl get pods --selector=app=striot-node-3 -n kafka -o jsonpath='{.items[*].metadata.name}'`:/opt/node/output/ $1/data/latency/temp
  mv $1/data/latency/temp/*.txt $1/data/latency/
  rmdir $1/data/latency/temp
  log "Done."
}

stop() {
  t=$(get_test $1) || { help ; exit ; }

  log "Stopping test $1 Topology in namespace $DEFAULT_NAMESPACE"
  kubectl delete -f "$1/deploy/kube/striot.org_v1alpha1_topology_cr.yaml" -n $DEFAULT_NAMESPACE
}

clean() {
  log "Cleanup all components in $DEFAULT_NAMESPACE"

  log "Delete prometheus in $DEFAULT_NAMESPACE"
  kubectl delete -f $PROMETHEUS_INSTANCE -n $DEFAULT_NAMESPACE

  log "Delete prometheus operator in $DEFAULT_NAMESPACE"
  kubectl delete -f $PROMETHEUS_OPERATOR -n $DEFAULT_NAMESPACE

  log "Delete striot-redis in $DEFAULT_NAMESPACE"
  kubectl delete -f $STRIOT_REDIS -n $DEFAULT_NAMESPACE

  log "Delete striot operator in $DEFAULT_NAMESPACE"
  kubectl delete -f $STRIOT_OPERATOR -n $DEFAULT_NAMESPACE

  log "Delete Kafka in $DEFAULT_NAMESPACE"
  kubectl delete -f $STRIMZI_KAFKA -n $DEFAULT_NAMESPACE

  log "Delete Strimzi operator in $DEFAULT_NAMESPACE"
  kubectl delete -f $STRIMZI_OPERATOR -n $DEFAULT_NAMESPACE

  log "Delete storage in $DEFAULT_NAMESPACE"
  kubectl delete -f $STRIOT_STORAGE -n $DEFAULT_NAMESPACE
  # kubectl delete secret striot-storage-secret -n $DEFAULT_NAMESPACE

  log "Delete namespace $DEFAULT_NAMESPACE"
  kubectl delete namespace $DEFAULT_NAMESPACE
}


help() {
  echo "-----------------------------------------------------------------------"
  echo "                      Available commands                              -"
  echo "-----------------------------------------------------------------------"
  echo -e "$BLUE"
  echo "   > build   [test] - Build images for [test]"
  echo "   > install        - Deploy operator and required images"
  echo "   > start   [test] - Deploy [test] topology"
  echo "   > extract [test] - Extract throughput data"
  echo "   > stop    [test] - Remove [test] topology"
  echo "   > clean          - Remove all assets and delete namespace $DEFAULT_NAMESPACE"
  echo "   > help           - Display this help"
  echo -e "$NORMAL"
  echo "-----------------------------------------------------------------------"
}


log() {
  echo -e "$BLUE > $1 $NORMAL" | ts '[%d-%m-%Y %H:%M:%.S]'
}

error() {
  echo ""
  echo -e "$RED >>> ERROR - $1$NORMAL" | ts '[%d-%m-%Y %H:%M:%.S]'
}



$*
