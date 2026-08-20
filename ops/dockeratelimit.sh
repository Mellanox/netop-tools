#!/bin/bash
#
#
#
if [ -z "${DOCKER_PASSWORD:-}" ];then
  if [ -t 0 ];then
    echo "usage: DOCKER_USER=<username> DOCKER_PASSWORD=<token> $0"
    echo "   or: printf '%s\n' <token> | DOCKER_USER=<username> $0"
    exit 1
  fi
  IFS= read -r DOCKER_PASSWORD
fi
export -n DOCKER_PASSWORD 2>/dev/null || true
DOCKER_USER="${DOCKER_USER:-${USER}}"
if [ -z "${DOCKER_USER:-}" ];then
  echo "ERROR: DOCKER_USER is required"
  exit 1
fi
if [ -z "${DOCKER_PASSWORD:-}" ];then
  echo "ERROR: Docker Hub password/token is required"
  exit 1
fi

CURL_CONFIG=$(mktemp "${TMPDIR:-/tmp}/netop-dockerhub-curl.XXXXXX") || exit 1
trap 'rm -f "${CURL_CONFIG}"' EXIT
chmod 0600 "${CURL_CONFIG}"
CURL_USERPASS="${DOCKER_USER}:${DOCKER_PASSWORD}"
CURL_USERPASS="${CURL_USERPASS//\\/\\\\}"
CURL_USERPASS="${CURL_USERPASS//\"/\\\"}"
{
  printf 'user = "%s"\n' "${CURL_USERPASS}"
} > "${CURL_CONFIG}"

#TOKEN=$(curl "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq -r .token)
TOKEN=$(curl --config "${CURL_CONFIG}" "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq -r .token)
curl --head -H "Authorization: Bearer ${TOKEN}" https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest
