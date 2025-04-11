#!/bin/bash
#
# https://technekey.com/check-whats-inside-the-etcd-database-in-kubernetes/
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
MASTER="cloud-dev-20"
ETCDCTL=`which etcdctl`
if [ "${ETCDCTL}" = "" ];then
  apt-get install -y etcd-client
fi
IPADDR=`${K8CL} get pods -A -o wide | grep etcd | tr -s [:space:]|cut -d' ' -f7`
CONFIG="./tmp.$$"
${K8CL} get pod -n kube-system kube-apiserver-${MASTER} -o yaml |grep -i etcd > ${CONFIG}
CACERT=`grep "cafile=" ${CONFIG} | cut -d'=' -f2`
CLIENTCERT=`grep "certfile=" ${CONFIG} | cut -d'=' -f2`
CLIENTKEY=`grep "keyfile=" ${CONFIG} | cut -d'=' -f2`
SERVER=`grep "servers=" ${CONFIG} | cut -d'=' -f2`
case ${1} in
	namespaces)
		ARGS='get --keys-only --prefix=true "/registry/namespaces/"'
		;;
	keys)
		ARGS="get /registry/ --prefix --keys-only"
		;;
	registry)
		ARGS="get /registry/ --prefix=true"
		;;
	pods)
		ARGS="get /registry/ --prefix --keys-only \|grep pods/default"
		;;
	services)
		ARGS="get /registry/ --prefix --keys-only \|grep services/specs/kube-system"
		;;
	get)
		ARGS="get"
		;;
	*)
		ARGS=${*}
		;;
esac
ETCDCTL_API=3 etcdctl --endpoints ${SERVER} --cert=${CLIENTCERT} --key=${CLIENTKEY} --cacert=${CACERT} ${ARGS}
rm -f ./${CONFIG}
