#!/bin/bash
#
#
cd ..
git clone https://github.com/Mellanox/nic-configuration-operator.git
cd ./nic-configuration-operator
git checkout ${1}
cd deployment/nic-configuration-operator-chart/crds
FILES=$(ls *.yaml)
for FILE=${FILES[@]};do
  apply -f ${FILE}
done
