kubectl delete serviceaccount prometheus
kubectl delete clusterrole prometheus
kubectl delete clusterrolebinding prometheus

kubectl delete --all prometheus,servicemonitor,alertmanager
kubectl delete --ignore-not-found service prometheus-operated alertmanager-operated

kubectl delete service example-app
kubectl delete deployment.apps example-app
