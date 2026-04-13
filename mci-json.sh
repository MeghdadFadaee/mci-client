#!/usr/bin/env bash

set -euo pipefail

ENV_FILE=".env"

AUTH_URL="https://my.mci.ir/api/idm/v1/auth"
PACKAGES_URL="https://my.mci.ir/api/unit/v1/packages/details"

NOW() { date +%s; }

env_get() {
  grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d '=' -f2- | sed 's/^"//;s/"$//'
}

env_set() {
  if grep -qE "^$1=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^$1=.*|$1=\"$2\"|" "$ENV_FILE"
  else
    echo "$1=\"$2\"" >> "$ENV_FILE"
  fi
}

require_env() {
  local v
  v=$(env_get "$1")
  [[ -z "$v" ]] && { echo "Missing $1" >&2; exit 1; }
  echo "$v"
}

expiry() { echo $(( $(NOW) + $1 - 30 )); }

token_valid() { [[ -n "$1" && "$1" -gt "$(NOW)" ]]; }

auth() {
  curl -sS -X POST "$AUTH_URL" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "User-Agent: Mozilla/5.0" \
    -H "Origin: https://my.mci.ir" \
    -H "Referer: https://my.mci.ir/" \
    -H "platform: WEB" \
    -H "version: 1.29.0" \
    ${2:+-H "Authorization: Bearer $2"} \
    -d "$1"
}

save_auth() {
  local p="$1"

  env_set MCI_ACCESS_TOKEN "$(echo "$p" | jq -r '.access_token // ""')"
  env_set MCI_REFRESH_TOKEN "$(echo "$p" | jq -r '.refresh_token // ""')"
  env_set MCI_ACCESS_TOKEN_EXPIRES_AT "$(expiry "$(echo "$p" | jq -r '.expires_in // 0')")"
  env_set MCI_REFRESH_TOKEN_EXPIRES_AT "$(expiry "$(echo "$p" | jq -r '.refresh_expires_in // 0')")"
}

login() {
  local u p
  u=$(require_env MCI_USERNAME)
  p=$(require_env MCI_PASSWORD)

  local body
  body=$(jq -n --arg u "$u" --arg p "$p" \
    '{username:$u,credential:$p,credential_type:"PASSWORD"}')

  local res
  res=$(auth "$body")
  save_auth "$res"
}

refresh() {
  local u rt at
  u=$(require_env MCI_USERNAME)
  rt=$(env_get MCI_REFRESH_TOKEN)
  at=$(env_get MCI_ACCESS_TOKEN)

  local body
  body=$(jq -n --arg u "$u" --arg r "$rt" \
    '{username:$u,credential:$r,credential_type:"REFRESH_TOKEN"}')

  local res
  res=$(auth "$body" "$at")
  save_auth "$res"
}

ensure_token() {
  local at rt aexp rexp
  at=$(env_get MCI_ACCESS_TOKEN)
  rt=$(env_get MCI_REFRESH_TOKEN)
  aexp=$(env_get MCI_ACCESS_TOKEN_EXPIRES_AT)
  rexp=$(env_get MCI_REFRESH_TOKEN_EXPIRES_AT)

  if token_valid "$aexp"; then
    echo "$at"; return
  fi

  if [[ -n "$rt" ]] && token_valid "$rexp"; then
    refresh >/dev/null
    echo "$(env_get MCI_ACCESS_TOKEN)"; return
  fi

  login >/dev/null
  echo "$(env_get MCI_ACCESS_TOKEN)"
}

get_packages() {
  local token
  token=$(ensure_token)

  curl -sS "$PACKAGES_URL" \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/json"
}

# Convert bytes to human label
to_label() {
  awk -v b="$1" 'BEGIN {
    if (b >= 1024^3) printf "%.2f GB", b/1024/1024/1024;
    else if (b >= 1024^2) printf "%.2f MB", b/1024/1024;
    else if (b >= 1024) printf "%.2f KB", b/1024;
    else printf "%d B", b;
  }'
}

# -----------------------------
# MAIN OUTPUT
# -----------------------------

main() {
  if ! raw=$(get_packages); then
    jq -n '{
      status:1,
      message:"request failed",
      data:null,
      errors:["request_error"]
    }'
    exit 1
  fi

  mapfile -t vals < <(
    echo "$raw" | jq '.. | objects | .unusedAmount? // empty' 2>/dev/null | awk '
      /^[0-9.]+$/ {
        if ($0 ~ /\./) printf "%d\n", $0
        else print $0
      }'
  )

  total=0
  packages_json="[]"

  if [[ ${#vals[@]} -gt 0 ]]; then
    for v in "${vals[@]}"; do
      total=$((total + v))
      label=$(to_label "$v")

      packages_json=$(jq -n \
        --argjson arr "$packages_json" \
        --argjson v "$v" \
        --arg l "$label" \
        '$arr + [{unused_bit:$v, unused_label:$l}]')
    done
  fi

  total_label=$(to_label "$total")

  jq -n \
    --argjson total "$total" \
    --arg total_label "$total_label" \
    --argjson packages "$packages_json" \
    '{
      status:0,
      message:"",
      data:{
        total_unused_bit:$total,
        total_unused_label:$total_label,
        packages:$packages
      },
      errors:[]
    }'
}

main
