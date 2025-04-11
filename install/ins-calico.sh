#!/bin/bash
#
# https://docs.tigera.io/calico/3.25/getting-started/kubernetes/helm
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
CALICO_DIR="${NETOP_ROOT_DIR}/release/calico-${CALICO_VERSION}"
if [ ! -d ${CALICO_DIR} ];then
  mkdir -p ${CALICO_DIR}
fi

cd ${CALICO_DIR}
if [ ! -f ./tigera-operator.yaml ];then
  curl -o ./tigera-operator.yaml https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml
fi
if [ ! -f ./custom-resources.yaml ];then
  curl -o ./custom-resources.yaml https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml
fi
#
# delete existing tigera-operator namespace.
#
${NETOP_ROOT_DIR}/uninstall/delhelmchart.sh calico tigera-operator
#
# Create the tigera-operator namespace.
#
X=`kubectl get namespace tigera-operator | grep -c tigera-operator`
if [ "${X}" != "0" ];then
  kubectl delete namespace tigera-operator
fi
kubectl create namespace tigera-operator

#
# add the calico repo
#
helm repo add projectcalico https://docs.tigera.io/calico/charts

# Install the Tigera Calico operator and custom resource definitions using the Helm chart:
helm install calico projectcalico/tigera-operator --version ${CALICO_VERSION} --namespace tigera-operator

#
# apply the custom resources
#
helm repo update
kubectl apply -f ./custom-resources.yaml

${NETOP_ROOT_DIR}/install/fixes/fix_calico_bird.sh
#helm install calico projectcalico/tigera-operator --version ${CALICO_VERSION} -f values.yaml --namespace tigera-operator
### #kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml
### #kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml
### # Create the tigera-operator namespace.
### # get the error message that this already exists
### kubectl create namespace tigera-operator
### 
### helm repo add projectcalico https://docs.tigera.io/calico/charts
### # Install the Tigera Calico operator and custom resource definitions using the Helm chart:
### 
### #helm install calico projectcalico/tigera-operator --version ${CALICO_VERSION} --namespace tigera-operator
### helm install calico projectcalico/tigera-operator --namespace tigera-operator
### 
### kubectl apply -f ./calico/calico-custom-resources.yaml
### #helm upgrade tigera-operator -f calico/calico-custom-resources.yaml tigera-operator
### # or if you created a values.yaml above:
### 
### #helm install calico projectcalico/tigera-operator --version ${CALICO_VERSION} -f values.yaml --namespace tigera-operator
