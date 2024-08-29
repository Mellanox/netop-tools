#!/bin/bash -x
#
# fix the sym links based on version
#
function opslinks()
{
  for DIR in $*;do
    cd ${DIR}
    LIST=( netop.cfg netop-chart values.yaml calico uc )
    for FILE in ${LIST[@]};do
      rm -f ${FILE}
      ln -s ../${FILE} ./${FILE}
    done
    cd ..
  done
}
if [ "$#" -lt 1 ];then
  echo "usage:$0 {USECASE}"
  ls ./usecase
  exit 1
fi
LINKS=( csi-driver-lvm release multus-cni nerdctl )
for LINK in ${LINKS[@]};do
# rm -f ${LINK}
# ln -s ../${LINK} ${LINK}
  mkdir -p ${LINK}
done
rm -f ./uc
ln -s ./usecase/${1} uc
source ./uc/netop.cfg
mkdir -p ./release/${NETOP_VERSION}/netop-chart
rm -f ./netop-chart
ln -s ./release/${NETOP_VERSION}/netop-chart ./netop-chart
mkdir -p ./release/calico-${CALICO_VERSION}
rm -f ./calico
ln -s ./release/calico-${CALICO_VERSION} ./calico
rm -f ./values.yaml
ln -s ./uc/values.yaml ./values.yaml
rm -f ./netop.cfg
ln -s ./uc/netop.cfg ./netop.cfg
opslinks ops install uninstall upgrade
cd ./install
LINKS=( ins-k8repo.sh ins-k8base.sh ins-docker.sh ins-go.sh )
for LINK in ${LINKS[@]};do
  rm -f ${LINK}
  ln -s ./${HOSTOS}/${LINK} ${LINK}
done
