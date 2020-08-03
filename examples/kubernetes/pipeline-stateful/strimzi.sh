#operator='https://strimzi.io/install/latest?namespace=kafka'
#kafka='https://strimzi.io/examples/latest/kafka/kafka-ephemeral-single.yaml'
operator='operator.yaml'
kafka='kafka.yaml'

kubectl create namespace kafka

kubectl apply -f $operator -n kafka

kubectl apply -f $kafka -n kafka

kubectl wait kafka/my-cluster --for=condition=Ready --timeout=300s -n kafka

#kubectl apply -f striot-topic.yaml -n kafka

kubectl apply -f striot-redis/deploy.yaml -n kafka
