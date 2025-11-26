#!/bin/bash
#
#
git clone https://github.com/Mellanox/nic-configuration-operator.git
cd ./nic-configuration-operator
git checkout ${1}
apply -f ./config/crd/bases/nicconfigurationtemplate.nvidia.com_nicconfigurationtemplates.yaml .
