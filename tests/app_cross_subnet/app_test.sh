#!/bin/bash
#
# mk-app.sh must emit cross subnet routes only when CROSS_SUBNET_ROUTING=true.
# Generates the app yaml both ways and diffs against the baselines here.
#
if [ ! -v NETOP_ROOT_DIR ];then
  echo "NETOP_ROOT_DIR variable not defined"
  exit 1
fi
TDIR="${NETOP_ROOT_DIR}/tests/app_cross_subnet"
export GLOBAL_OPS_USER="${TDIR}/app.cfg"
export CREATE_CONFIG_ONLY=1
WORK=$(mktemp -d)
res=0
for MODE in false true;do
  rm -rf "${WORK}/apps"
  ( cd "${WORK}" && CROSS_SUBNET_ROUTING=${MODE} "${NETOP_ROOT_DIR}/ops/mk-app.sh" app 1 default ) >/dev/null
  echo "Validating ${TDIR}/app-cross-subnet-${MODE}.yaml"
  diff -u "${TDIR}/app-cross-subnet-${MODE}.yaml" "${WORK}/apps/app.yaml"
  if [ $? -ne 0 ];then
    echo "Generated app yaml (CROSS_SUBNET_ROUTING=${MODE}) is different from baseline"
    res=$((res + 1))
  fi
done
rm -rf "${WORK}"
exit ${res}
