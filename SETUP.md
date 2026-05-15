```bash
helm uninstall banking -n banking; 
helm uninstall kube-prometheus-stack -n monitoring; 
helm uninstall tempo -n monitoring; 
helm uninstall opentelemetry-collector -n monitoring; 
kubectl delete namespace banking --ignore-not-found=true; 
kubectl delete namespace monitoring --ignore-not-found=true

helm uninstall keda -n keda; 
kubectl delete namespace keda --ignore-not-found=true

```