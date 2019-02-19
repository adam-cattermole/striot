set -e

kubectl create -f striot-sm.yaml

kubectl create -f prom-sa.yaml
kubectl create -f prom-cr.yaml
kubectl create -f prom-crb.yaml

kubectl create -f striot-prom.yaml
