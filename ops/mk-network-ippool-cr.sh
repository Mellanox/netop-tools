#!/bin/bash
#
# make sure the ip pool is created
#
function mkIPPoolCRDs()
{
if [ "${IPAM_TYPE}" = "nv-ipam" ];then
  for NETOP_SU in ${NETOP_SULIST[@]};do
    echo "NETOP_SU:${NETOP_SU}"
    IPPOOLS_KEY=NETOP_IPPOOLS[${NETOP_SU}]
    for IPPOOL_KEY in ${IPPOOLS_KEY[@]};do
      echo "IPPOOL_KEY:${IPPOOL_KEY}"
      IPPOOL=${!IPPOOL_KEY}
      echo "IPPOOL:${IPPOOL}"
      for NIDXDEF in ${IPPOOL[@]};do
        NIDX=$(echo ${NIDXDEF}|cut -d',' -f1)
        RANGE=$(echo ${NIDXDEF}|cut -d',' -f2)
        GW=$(echo ${NIDXDEF}|cut -d',' -f3)
        BLOCKSIZE=$(echo ${NIDXDEF}|cut -d',' -f4)
        case "${NVIPAM_POOL_TYPE}" in
        IPPool)
          FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/ippool-${NIDX}-${NETOP_SU}.yaml"
          ${NETOP_ROOT_DIR}/ops/mk-nvipam-pool.sh ${FILE} ${NIDX} ${NETOP_SU} ${RANGE} ${GW} ${BLOCKSIZE}
          ;;
        CIDRPool)
          FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/cidrpool-${NIDX}-${NETOP_SU}.yaml"
          ${NETOP_ROOT_DIR}/ops/mk-nvipam-cidr.sh ${FILE} ${NIDX} ${NETOP_SU} ${RANGE} ${GW} ${BLOCKSIZE}
          ;;
        esac
        echo ${FILE}
      done
    done
  done
fi
}
