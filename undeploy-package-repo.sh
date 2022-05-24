yes | kapp delete -a kc 
yes | kapp delete -a sg 
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.0/cert-manager.yaml
