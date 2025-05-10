#!/bin/bash

if [ ! -v NETOP_ROOT_DIR ];then
  echo "NETOP_ROOT_DIR variable not defined"
  exit 1
fi

if [[ $# -eq 0 ]];then
  echo "Running all tests"
  CONFIGS=$(ls ${NETOP_ROOT_DIR}/tests/*/*/config)
else
  #TODO: how to identify single test?"
  #IDEA: contantenate base usecase with a test number
  echo "Running $1"
  CONFIGS=$1
fi

export CREATE_CONFIG_ONLY=1


res=0

for CONF in ${CONFIGS};do
  export GLOBAL_OPS_USER=${CONF}
  source ${GLOBAL_OPS_USER}
  if [ ! -r ${GLOBAL_OPS_USER} ];then
    echo "Configration file ${GLOBAL_OPS_USER} not found"
    res=$((res + 1))
    continue
  fi
  echo "Using configuration from ${GLOBAL_OPS_USER}"
  TDIR=${GLOBAL_OPS_USER%/*}
  $NETOP_ROOT_DIR/install/ins-network-operator.sh
  for FILE in $(find ${TDIR} -type f -name '*.yaml'  | xargs -I % -r basename %);do
    echo "Validating ${TDIR}/${FILE}"
    diff -ruN $NETOP_ROOT_DIR/usecase/${USECASE}/${FILE} ${TDIR}/${FILE}
    if [ $? -ne 0 ];then
      echo "Generated file ${USECASE}/${FILE} is different from baseline ${TDIR}/${FILE}"
      res=$((res + 1))
    fi
  done
done

exit ${res}

