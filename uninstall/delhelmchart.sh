#!/bin/bash
#
#
${HELMCL} list --all-namespaces
#${HELMCL} delete network-operator -n network-operator
${HELMCL} delete ${1} -n ${2}
${HELMCL} list --all-namespaces
