# Output colors
NORMAL="\\033[0;39m"
RED="\\033[1;31m"
BLUE="\\033[1;34m"

PREFIX="adamcattermole"
SINK="server"

AMQ_BROKER="striot-artemis.eastus.cloudapp.azure.com"
SINK_HOST="striot-sink.eastus.cloudapp.azure.com"

RESULTS_DIR="output"

POD_COUNT="kubectl get pods --field-selector=status.phase=Running -o name | wc -l"

# TEST_TIME=1900

set -e

# declare -a dirs=("server" "client2" "gen-broker" "generator")
declare -a dirs=("client2")

build() {
    log "Creating docker containers..."
  if [ -n "$1" ]; then
    if  [ $1 = "base" ]; then
      log "Making striot/striot-base..."
      make -C ../../containers all
    fi
  fi

  name=haskell-link
  log $PREFIX/$name
  docker build -t $PREFIX/$name client2/
  docker push $PREFIX/$name:latest

  log "Creating Kubernetes services..."
  log $name
  helm install -n $name \
               --debug \
               --set image.repository.prefix=$PREFIX \
               --set image.repository.name=$name \
               --set image.tag=latest \
               --set amqBroker.host=$AMQ_BROKER \
               --set sink.host=$SINK_HOST ./test-chart
}


start() {
  log "Starting pipeline..."
  if [ -n "$1" ]; then
    replicas=$1
  else
    replicas=1
  fi

  pod_count=0
  log "haskell-link (replicas:$replicas)"
  kubectl scale deployment haskell-link --replicas=$replicas
  ((pod_count+=$replicas))
  pods_running $pod_count
}

pods_running() {
  while [[ $(eval $POD_COUNT) -ne $1 ]]; do
    log "Pods not running yet..."
    sleep 5
  done
}


# output() {
#   kubectl attach -it deploy haskell-server -c haskell-server
# }
#
#
# extract() {
#   log "Extracting logs from haskell-server..."
#   SINK_POD=$(kubectl get pods --selector=app=haskell-server -o jsonpath='{.items[*].metadata.name}')
#   kubectl cp "${SINK_POD}:/opt/server/sw-log.txt" "${RESULTS_DIR}/serial-log.txt"
# }
#
# benchmark() {
#   log "Starting benchmark..."
#   [[ -d "${RESULTS_DIR}" ]] || mkdir "${RESULTS_DIR}"
#   build $1
#   start $1
#   log "All pods running, waiting $(($TEST_TIME/60))m..."
#   sleep $TEST_TIME
#   extract
# }

# install() {
#   build $1
#   start
#   output
# }


stop() {
  log "Stopping pipeline..."
  # kubectl delete services,deployments -l name=haskell-server --now
  name="haskell-link"
  log $name
  kubectl scale deployment $name --replicas=0
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
    name=haskell-link
    if [[ -n $(helm list -q $name) ]]; then
      helm delete --purge $name
    fi
    # if [[ -n $(docker images -q $PREFIX/$n) ]]; then
    #   log $PREFIX/$n
    #   docker rmi -f $PREFIX/$n
    # fi
  done
}



help() {
  echo "-----------------------------------------------------------------------"
  echo "                      Available commands                              -"
  echo "-----------------------------------------------------------------------"
  echo "$BLUE"
  echo "   > install - Build, Start and Attach"
  echo "   > build - To build the Docker images"
  echo "   > start - To start the pipeline containers"
  echo "   > output - Follow log output from server"
  echo "   > stop - To stop the pipeline containers"
  echo "   > clean - Remove the pipeline containers and all assets"
  echo "   > help - Display this help"
  echo "$NORMAL"
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
