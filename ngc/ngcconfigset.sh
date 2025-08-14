#!/bin/bash
#
#
#
if [ $# -lt 1 ];then
  echo "usage:0 {PERSONALKEY_FILE}"
  exit 1
fi
API_KEY=$(cat ${1})
source ./ngc_exec.sh
source ./ngc.cfg
#Enter API key [no-apikey]. Choices: [<VALID_APIKEY>, 'no-apikey']: {SAVED PERSONAL KEY} 
#Enter CLI output format type [ascii]. Choices: ['ascii', 'csv', 'json']: ascii
#Enter org [no-org]. Choices: ['0517391077169504']: 0517391077169504
#Enter team [no-team]. Choices: ['no-team']: no-team
#Enter ace [no-ace]. Choices: ['no-ace']: no-ace
cat << NGCCONFIG > ./ngcconfig.dat
${API_KEY}
ascii
${REGISTRY_ORG}
${REGISTRY_TEAM}
no-ace
NGCCONFIG
cat ./ngcconfig.dat | ngc config set
