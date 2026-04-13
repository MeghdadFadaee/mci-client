#!/usr/bin/env bash

set -euo pipefail

ENV_FILE=".env"

AUTH_URL="https://my.mci.ir/api/idm/v1/auth"
PACKAGES_URL="https://my.mci.ir/api/unit/v1/packages/details"

NOW() {
  date +%s
}

# -----------------------------
# .env helpers
# -----------------------------
env_get() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d '=' -f2- | sed 's/^"//;s/"$//'
}

env_set() {
  local key="$1"
  local value="$2"

  if grep -qE "^${key}=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$ENV_FILE"
  else
    echo "${key}=\"${value}\"" >> "$ENV_FILE"
  fi
}

require_env() {
  local key="$1"
  local val
  val=$(env_get "$key")
  if [[ -z "${val}" ]]; then
    echo "Missing env: $key" >&2
    exit 1
  fi
  echo "$val"
}

# -----------------------------
# Auth helpers
# -----------------------------
expiry_from_seconds() {
  local expires_in="$1"
  local buffer=30
  echo $(( $(NOW) + expires_in - buffer ))
}

token_valid() {
  local expires_at="$1"
  [[ -n "$expires_at" && "$expires_at" -gt "$(NOW)" ]]
}

auth_request() {
  local body="$1"
  local bearer="${2:-}"

  if [[ -n "$bearer" ]]; then
    curl -sS -X POST "$AUTH_URL" \
      -H "Authorization: Bearer $bearer" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -H "User-Agent: Mozilla/5.0" \
      -H "Origin: https://my.mci.ir" \
      -H "Referer: https://my.mci.ir/" \
      -H "platform: WEB" \
      -H "version: 1.29.0" \
      -d "$body"
  else
    curl -sS -X POST "$AUTH_URL" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -H "User-Agent: Mozilla/5.0" \
      -H "Origin: https://my.mci.ir" \
      -H "Referer: https://my.mci.ir/" \
      -H "platform: WEB" \
      -H "version: 1.29.0" \
      -d "$body"
  fi
}

save_auth() {
  local payload="$1"

  local access_token refresh_token session_state
  access_token=$(echo "$payload" | jq -r '.access_token // empty')
  refresh_token=$(echo "$payload" | jq -r '.refresh_token // empty')
  session_state=$(echo "$payload" | jq -r '.session_state // empty')

  local access_exp refresh_exp
  access_exp=$(echo "$payload" | jq -r '.expires_in // empty')
  refresh_exp=$(echo "$payload" | jq -r '.refresh_expires_in // empty')

  [[ -n "$access_exp" ]] && access_exp=$(expiry_from_seconds "$access_exp")
  [[ -n "$refresh_exp" ]] && refresh_exp=$(expiry_from_seconds "$refresh_exp")

  env_set "MCI_ACCESS_TOKEN" "$access_token"
  env_set "MCI_REFRESH_TOKEN" "$refresh_token"
  env_set "MCI_SESSION_STATE" "$session_state"
  env_set "MCI_ACCESS_TOKEN_EXPIRES_AT" "$access_exp"
  env_set "MCI_REFRESH_TOKEN_EXPIRES_AT" "$refresh_exp"
}

login() {
  local username password
  username=$(require_env "MCI_USERNAME")
  password=$(require_env "MCI_PASSWORD")

  local body
  body=$(jq -n \
    --arg u "$username" \
    --arg p "$password" \
    '{username:$u, credential:$p, credential_type:"PASSWORD"}')

  local res
  res=$(auth_request "$body")

  save_auth "$res"
  echo "$res"
}

refresh() {
  local username refresh_token access_token
  username=$(require_env "MCI_USERNAME")
  refresh_token=$(env_get "MCI_REFRESH_TOKEN")
  access_token=$(env_get "MCI_ACCESS_TOKEN")

  if [[ -z "$refresh_token" ]]; then
    login
    return
  fi

  local body
  body=$(jq -n \
    --arg u "$username" \
    --arg r "$refresh_token" \
    '{username:$u, credential:$r, credential_type:"REFRESH_TOKEN"}')

  local res
  res=$(auth_request "$body" "$access_token")

  save_auth "$res"
  echo "$res"
}

ensure_token() {
  local access_token refresh_token access_exp refresh_exp

  access_token=$(env_get "MCI_ACCESS_TOKEN")
  refresh_token=$(env_get "MCI_REFRESH_TOKEN")
  access_exp=$(env_get "MCI_ACCESS_TOKEN_EXPIRES_AT")
  refresh_exp=$(env_get "MCI_REFRESH_TOKEN_EXPIRES_AT")

  if token_valid "$access_exp"; then
    echo "$access_token"
    return
  fi

  if [[ -n "$refresh_token" ]] && token_valid "$refresh_exp"; then
    refresh >/dev/null
    echo "$(env_get MCI_ACCESS_TOKEN)"
    return
  fi

  login >/dev/null
  echo "$(env_get MCI_ACCESS_TOKEN)"
}

# -----------------------------
# API
# -----------------------------
get_packages() {
  local token
  token=$(ensure_token)

  local res
  res=$(curl -sS "$PACKAGES_URL" \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/json")

  echo "$res"
}

get_unused_amounts() {
  get_packages | jq '.. | objects | .unusedAmount? // empty' 2>/dev/null | awk '
  {
    if ($0 ~ /^[0-9.]+$/) {
      if ($0 ~ /\./) printf "%d\n", $0
      else print $0
    }
  }'
}

# -----------------------------
# MAIN
# -----------------------------
echo "=== MCI Internet Client Test ==="

echo "[1] Checking tokens..."
echo "Access token: $(env_get MCI_ACCESS_TOKEN | wc -c) chars"
echo "Refresh token: $(env_get MCI_REFRESH_TOKEN | wc -c) chars"

echo "[2] Ensuring token..."
token=$(ensure_token)
echo "Token: ${token:0:20}..."

echo "[3] Fetching packages..."
packages=$(get_packages)
echo "Fetched."

echo "--- Raw (truncated) ---"
echo "$packages" | head -c 300
echo

echo "[4] Extracting unusedAmount..."
mapfile -t values < <(get_unused_amounts)

if [[ ${#values[@]} -eq 0 ]]; then
  echo "No unusedAmount found!"
else
  total=0
  i=1
  for v in "${values[@]}"; do
    gb=$(awk "BEGIN {printf \"%.2f\", $v/1024/1024/1024}")
    echo "$i. $v bytes (~${gb} GB)"
    total=$((total + v))
    ((i++))
  done

  total_gb=$(awk "BEGIN {printf \"%.2f\", $total/1024/1024/1024}")
  echo "Total: $total bytes (~${total_gb} GB)"
fi

echo "=== DONE ==="
