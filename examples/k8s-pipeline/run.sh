# Output colors
NORMAL="\\033[0;39m"
RED="\\033[1;31m"
BLUE="\\033[1;34m"

PREFIX="adamcattermole"
SINK="server"

AMQ_BROKER="artemis-broker.eastus.cloudapp.azure.com"

RESULTS_DIR="output"

POD_COUNT="kubectl get pods --field-selector=status.phase=Running -o name | wc -l"

TEST_TIME=1900

set -e

# declare -a dirs=("server" "client2" "gen-broker" "generator")
declare -a dirs=("server" "client2")

build() {
    log "Creating docker containers..."
  if [ -n "$1" ]; then
    if  [ $1 = "base" ]; then
      log "Making striot/striot-base..."
      make -C ../../containers all
    fi
  fi
  declare -a names=()
  for dir in "${dirs[@]}"
  do
    n=haskell-$dir
    names+=($n)
    log $PREFIX/$n
    docker build -t $PREFIX/$n $dir/
    docker push $PREFIX/$n:latest
  done

  log "Creating Kubernetes services..."
  for name in "${names[@]}"
  do
    log $name
    # kubectl run $name --image=$PREFIX/$name:latest --port=9001 --replicas=0 --image-pull-policy='IfNotPresent' --expose -l name=$name,all-flag=striot
    helm install -n $name --debug --set image.repository.prefix=$PREFIX --set image.repository.name=$name --set image.tag=latest --set amqBroker.host=$AMQ_BROKER ./test-chart
    # kubectl create service clusterip $name --tcp=9001 -l name=$name,all-flag=striot
    # kubectl run $name --image=$PREFIX/$name:latest --port=9001 --replicas=0 --image-pull-policy='Always' --expose -l name=$name,all-flag=striot
  done

  # log "Creating ActiveMQ Broker"
  # kubectl run amq-broker --image=webcenter/activemq:latest --replicas=0 --image-pull-policy='IfNotPresent' -l name=amq-broker,all=striot\
  #   --env="ACTIVEMQ_ADMIN_LOGIN=admin" --env="ACTIVEMQ_ADMIN_PASSWORD=yy^U#Fca!52Y"\
  #   --env="ACTIVEMQ_FRAME_SIZE=104857600&amp;jms.prefetchPolicy.all=25000"\
  #   --env='ACTIVEMQ_CONFIG_MINMEMORY=1024' --env='ACTIVEMQ_CONFIG_MAXMEMORY=6044'
  # kubectl expose deployment amq-broker --port=8161 --target-port=8161 --name=amq-web --type='LoadBalancer' -l name=amq-broker,all=striot
  # kubectl expose deployment amq-broker --port=61616 --target-port=61616 --name=amq-default -l name=amq-broker,all=striot
  # kubectl expose deployment amq-broker --port=61613 --target-port=61613 --name=amq-stomp -l name=amq-broker,all=striot

  # log "Creating ActiveMQ Artemis Broker"
  # kubectl run amq-broker --image=vromero/activemq-artemis:latest --replicas=0 --image-pull-policy='IfNotPresent' -l name=amq-broker,all=striot\
  #   --env="ARTEMIS_USERNAME=admin" --env="ARTEMIS_PASSWORD=yy^U#Fca!52Y"\
  #   --env='ARTEMIS_MIN_MEMORY=1024M' --env='ARTEMIS_MAX_MEMORY=4096M'
  # kubectl expose deployment amq-broker --port=8161 --target-port=8161 --name=amq-web --type='LoadBalancer' -l name=amq-broker,all=striot
  # kubectl expose deployment amq-broker --port=61616 --target-port=61616 --name=amq-default -l name=amq-broker,all=striot
  # kubectl expose deployment amq-broker --port=61613 --target-port=61613 --name=amq-stomp -l name=amq-broker,all=striot
}


start() {
  log "Starting pipeline..."
  if [ -n "$1" ]; then
    replicas=$1
  else
    replicas=1
  fi

  # kubectl scale deployment amq-broker --replicas=1
  pod_count=0
  # pods_running $pod_count
  # minikube service amq-web --url
  # kubectl run haskell-server -it --image=$PREFIX/haskell-server:latest --port=9001 --image-pull-policy='Always' --attach=False --expose -l name=haskell-server,all-flag=striot
  log "haskell-server"
  kubectl scale deployment haskell-server --replicas=1
  ((pod_count++))
  pods_running $pod_count

  # log "haskell-gen-broker"
  # kubectl scale deployment haskell-gen-broker --replicas=1
  # ((pod_count++))
  # pods_running $pod_count

  log "haskell-client2 (replicas:$replicas)"
  kubectl scale deployment haskell-client2 --replicas=$replicas
  ((pod_count+=$replicas))
  pods_running $pod_count

  # log "haskell-client"
  # kubectl scale deployment haskell-generator --replicas=1
  # ((pod_count++))
  # pods_running $pod_count

  # declare -a names=()
  # for dir in "${dirs[@]:2}"
  # do
  #   n=haskell-$dir
  #   names+=($n)
  #   log $n
  #   kubectl scale deployment $n --replicas=1
  #   ((pod_count++))
  #   pods_running $pod_count
  # done
}

pods_running() {
  while [[ $(eval $POD_COUNT) -ne $1 ]]; do
    log "Pods not running yet..."
    sleep 5
  done
}


output() {
  # kubectl logs -f --pod-running-timeout=1h --timestamps=true deploy/haskell-server
  kubectl attach -it deploy haskell-server -c haskell-server
}


extract() {
  log "Extracting logs from haskell-server..."
  SINK_POD=$(kubectl get pods --selector=app=haskell-server -o jsonpath='{.items[*].metadata.name}')
  kubectl cp "${SINK_POD}:/opt/server/sw-log.txt" "${RESULTS_DIR}/serial-log.txt"
}

benchmark() {
  log "Starting benchmark..."
  [[ -d "${RESULTS_DIR}" ]] || mkdir "${RESULTS_DIR}"
  build $1
  start $1
  log "All pods running, waiting $(($TEST_TIME/60))m..."
  sleep $TEST_TIME
  extract
}

install() {
  build $1
  start
  output
}


stop() {
  log "Stopping pipeline..."
  # kubectl delete services,deployments -l name=haskell-server --now
  declare -a names=()
  for dir in "${dirs[@]}"
  do
    n=haskell-$dir
    names+=($n)
    log $n
    kubectl scale deployment $n --replicas=0
  done
}


clean() {
  # eval $(minikube docker-env)
  log "Removing Kubernetes assets..."

  # log "Removing docker containers..."
  # if [ -n "$1" ]; then
  #   if  [ $1 = "base" ]; then
  #     log "Removing striot/striot-base..."
  #     make -C ../../containers clean
  #   fi
  # fi
  # declare -a names=()
  for dir in "${dirs[@]}"
  do
    n=haskell-$dir
    names+=($n)
    if [[ -n $(helm list -q $n) ]]; then
      helm delete --purge $n
    fi
    # if [[ -n $(docker images -q $PREFIX/$n) ]]; then
    #   log $PREFIX/$n
    #   docker rmi -f $PREFIX/$n
    # fi
  done
  # kubectl delete deployments,pods,services -l all=striot --now
}



help() {
  echo "-----------------------------------------------------------------------"
  echo "                      Available commands                              -"
  echo "-----------------------------------------------------------------------"
  # echo -e -n "$BLUE"
  echo "   > install - Build, Start and Attach"
  echo "   > build - To build the Docker images"
  echo "   > start - To start the pipeline containers"
  echo "   > output - Follow log output from server"
  echo "   > stop - To stop the pipeline containers"
  echo "   > clean - Remove the pipeline containers and all assets"
  echo "   > help - Display this help"
  # echo -e -n "$NORMAL"
  echo "-----------------------------------------------------------------------"
}


log() {
  echo "$BLUE > $1 $NORMAL" | ts '[%d-%m-%Y %H:%M:%.S]'
}

error() {
  echo ""
  echo "$RED >>> ERROR - $1$NORMAL" | ts '[%d-%m-%Y %H:%M:%.S]'
}



$*
