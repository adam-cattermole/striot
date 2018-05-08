# Output colors
NORMAL="\\033[0;39m"
RED="\\033[1;31m"
BLUE="\\033[1;34m"

PREFIX="striot"
SINK="server"

declare -a dirs=("server" "client2" "client")

build() {
  eval $(minikube docker-env)
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
  done
  log "Creating Kubernetes images..."
  for name in "${names[@]:1}"
  do
    log $name
    kubectl run $name --image=$PREFIX/$name:latest --port=9001 --replicas=0 --image-pull-policy='IfNotPresent' --expose -l name=$name,all-flag=striot
  done
}

start() {
  log "Starting pipeline..."
  kubectl run haskell-server -it --image=$PREFIX/haskell-server:latest --port=9001 --image-pull-policy='IfNotPresent' --attach=False --expose -l name=haskell-server,all-flag=striot
  declare -a names=()
  for dir in "${dirs[@]:1}"
  do
    n=haskell-$dir
    names+=($n)
    log $n
    kubectl scale deployment $n --replicas=1
  done
}

attach() {
  kubectl attach -it deploy haskell-server -c haskell-server
}

install() {
  build $1
  start
  attach
}

stop() {
  log "Stopping pipeline..."
  kubectl delete services,deployments -l name=haskell-server --now
  declare -a names=()
  for dir in "${dirs[@]:1}"
  do
    n=haskell-$dir
    names+=($n)
    log $n
    kubectl scale deployment $n --replicas=0
  done
}


clean() {
  eval $(minikube docker-env)
  log "Removing Kubernetes assets..."
  kubectl delete deployments,pods,services -l all-flag=striot --now
  log "Removing docker containers..."
  if [ -n "$1" ]; then
    if  [ $1 = "base" ]; then
      log "Removing striot/striot-base..."
      make -C ../../containers clean
    fi
  fi
  declare -a names=()
  for dir in "${dirs[@]}"
  do
    n=haskell-$dir
    names+=($n)
    if [[ -n $(docker images -q $PREFIX/$n) ]]; then
      log $PREFIX/$n
      docker rmi -f $PREFIX/$n
    fi
  done
}






help() {
  echo "-----------------------------------------------------------------------"
  echo "                      Available commands                              -"
  echo "-----------------------------------------------------------------------"
  # echo -e -n "$BLUE"
  echo "   > install - Build, Start and Attach"
  echo "   > build - To build the Docker images"
  echo "   > start - To start the pipeline containers"
  echo "   > attach - Connect to server to see output"
  echo "   > stop - To stop the pipeline containers"
  echo "   > clean - Remove the pipeline containers and all assets"
  echo "   > help - Display this help"
  # echo -e -n "$NORMAL"
  echo "-----------------------------------------------------------------------"
}


log() {
  echo "$BLUE > $1 $NORMAL"
}

error() {
  echo ""
  echo "$RED >>> ERROR - $1$NORMAL"
}



$*
