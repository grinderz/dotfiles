#!/usr/bin/env bash

set -o errtrace -o pipefail -o noclobber -o errexit -o nounset

OKD_TOKEN_GREP=${OKD_TOKEN_GREP:-grep}
OKD_TOKEN_URL=${OKD_TOKEN_URL:-}
OKD_TOKEN_USER_ID=${OKD_TOKEN_USER_ID:-}
OKD_TOKEN_API_URL=${OKD_TOKEN_API_URL:-}
OKD_TOKEN_PASS_PATH=${OKD_TOKEN_PASS_PATH:-}

token=$(curl -u "$OKD_TOKEN_USER_ID:$(pass "$OKD_TOKEN_PASS_PATH" | head -1)" "$OKD_TOKEN_URL/oauth/authorize?client_id=openshift-challenging-client&response_type=token" -skv -H "X-CSRF-Token: xxx" --stderr - | $OKD_TOKEN_GREP -oP "access_token=\K[^&]*")

oc login --token="$token" --server="$OKD_TOKEN_API_URL" --insecure-skip-tls-verify=true
