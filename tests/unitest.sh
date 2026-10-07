#!/bin/bash

if [ ! -v NETOP_ROOT_DIR ];then
  echo "NETOP_ROOT_DIR variable not defined"
  exit 1
fi

if [[ $# -eq 0 ]];then
  echo "Running all tests"
  CONFIGS=$(find ${NETOP_ROOT_DIR}/tests -type f -name 'config' | sort)
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
  if [ ! -r "${GLOBAL_OPS_USER}" ];then
    echo "Configuration file ${GLOBAL_OPS_USER} not found"
    res=$((res + 1))
    continue
  fi
  source "${GLOBAL_OPS_USER}"
  echo "Using configuration from ${GLOBAL_OPS_USER}"
  TDIR=${GLOBAL_OPS_USER%/*}
  find "${NETOP_ROOT_DIR}/usecase" -name "*.yaml" -type f -delete 2>/dev/null || true
  find "${NETOP_ROOT_DIR}/usecase" -name "netop_*_files" -type f -delete 2>/dev/null || true
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

# mk-app.sh generates pod yaml outside of ins-network-operator.sh, so the
# app tests have their own runner (tests/*/app_test.sh)
if [[ $# -eq 0 ]];then
  for APPTEST in $(find ${NETOP_ROOT_DIR}/tests -type f -name 'app_test.sh' | sort);do
    echo "Running ${APPTEST}"
    ${APPTEST}
    res=$((res + $?))
  done
fi

exit ${res}
