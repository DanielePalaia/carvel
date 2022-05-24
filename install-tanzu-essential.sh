yes | kapp deploy -a kc -f https://raw.githubusercontent.com/DanielePalaia/carvel/main/kapp-release-openshift.yml
yes | kapp deploy -a sg -f https://raw.githubusercontent.com/DanielePalaia/carvel/main/secretgen-controller-release.yml
# kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.0/cert-manager.yaml
