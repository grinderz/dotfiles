#!/usr/bin/env bash

set -o errtrace -o pipefail -o noclobber -o errexit -o nounset

# all four come from the environment (private shell config); fail up front
# with the variable's name rather than deep inside curl
OKD_TOKEN_GREP=${OKD_TOKEN_GREP:-grep}
: "${OKD_TOKEN_URL:?set OKD_TOKEN_URL to the OKD console url}"
: "${OKD_TOKEN_USER_ID:?set OKD_TOKEN_USER_ID to the login name}"
: "${OKD_TOKEN_API_URL:?set OKD_TOKEN_API_URL to the API server url}"
: "${OKD_TOKEN_PASS_PATH:?set OKD_TOKEN_PASS_PATH to the pass entry with the password}"

token=$(curl -u "$OKD_TOKEN_USER_ID:$(passw "$OKD_TOKEN_PASS_PATH" | head -1)" "$OKD_TOKEN_URL/oauth/authorize?client_id=openshift-challenging-client&response_type=token" -skv -H "X-CSRF-Token: xxx" --stderr - | $OKD_TOKEN_GREP -oP "access_token=\K[^&]*")

oc login --token="$token" --server="$OKD_TOKEN_API_URL" --insecure-skip-tls-verify=true
