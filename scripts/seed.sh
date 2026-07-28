#!/usr/bin/env bash
# seed.sh
# -----------------------------------------------------------------------------
# Seed the local (docker-compose) CloudKitchen stack with demo data via the
# public HTTP APIs:
#   1. register one user per role (customer, restaurant owner, delivery rider)
#   2. log in as the owner and create a restaurant
#   3. add a couple of menu items to that restaurant
#   4. place an order as the customer
#
# This talks to the services on their host ports (see docker/README.md).
# It is intentionally tolerant: it prints what it does and uses jq to pull IDs
# / tokens out of responses. Endpoints follow a conventional REST shape; adjust
# paths if your handlers differ.
#
# Usage:
#   ./scripts/seed.sh
#
# Requires: curl, jq
# -----------------------------------------------------------------------------
set -euo pipefail

AUTH=${AUTH:-http://localhost:8081}
USERS=${USERS:-http://localhost:8082}
RESTAURANT=${RESTAURANT:-http://localhost:8083}
MENU=${MENU:-http://localhost:8084}
ORDER=${ORDER:-http://localhost:8085}

command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 1; }

# POST helper: json [bearer-token] -> response body
post() {
  local url="$1" body="$2" token="${3:-}"
  if [[ -n "${token}" ]]; then
    curl -sS -X POST "${url}" \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer ${token}" \
      -d "${body}"
  else
    curl -sS -X POST "${url}" \
      -H 'Content-Type: application/json' \
      -d "${body}"
  fi
}

register() {  # email password role -> token
  local email="$1" pass="$2" role="$3"
  echo ">> register ${role}: ${email}" >&2
  local resp
  resp=$(post "${AUTH}/auth/register" \
    "{\"email\":\"${email}\",\"password\":\"${pass}\",\"role\":\"${role}\"}") || true
  # Fall back to login if the user already exists.
  local token
  token=$(echo "${resp}" | jq -r '.token // .access_token // empty')
  if [[ -z "${token}" ]]; then
    resp=$(post "${AUTH}/auth/login" "{\"email\":\"${email}\",\"password\":\"${pass}\"}")
    token=$(echo "${resp}" | jq -r '.token // .access_token // empty')
  fi
  echo "${token}"
}

echo "=== 1. Register users (one per role) ==="
CUSTOMER_TOKEN=$(register "customer@demo.io"  "Passw0rd!" "customer")
OWNER_TOKEN=$(register   "owner@demo.io"     "Passw0rd!" "restaurant_owner")
RIDER_TOKEN=$(register   "rider@demo.io"     "Passw0rd!" "delivery")
echo "   customer token: ${CUSTOMER_TOKEN:0:12}..."
echo "   owner token:    ${OWNER_TOKEN:0:12}..."
echo "   rider token:    ${RIDER_TOKEN:0:12}..."

echo "=== 2. Create a restaurant (as owner) ==="
REST_RESP=$(post "${RESTAURANT}/restaurants" \
  '{"name":"Demo Diner","cuisine":"American","address":"1 Test St"}' \
  "${OWNER_TOKEN}")
RESTAURANT_ID=$(echo "${REST_RESP}" | jq -r '.id // .restaurant_id // empty')
echo "   restaurant id: ${RESTAURANT_ID}"

echo "=== 3. Add menu items ==="
post "${MENU}/restaurants/${RESTAURANT_ID}/menu-items" \
  '{"name":"Cheeseburger","price":9.99,"description":"Classic"}' \
  "${OWNER_TOKEN}" >/dev/null
ITEM_RESP=$(post "${MENU}/restaurants/${RESTAURANT_ID}/menu-items" \
  '{"name":"Fries","price":3.49,"description":"Crispy"}' \
  "${OWNER_TOKEN}")
ITEM_ID=$(echo "${ITEM_RESP}" | jq -r '.id // .item_id // empty')
echo "   added 2 menu items (sample item id: ${ITEM_ID})"

echo "=== 4. Place an order (as customer) ==="
ORDER_RESP=$(post "${ORDER}/orders" \
  "{\"restaurant_id\":\"${RESTAURANT_ID}\",\"items\":[{\"item_id\":\"${ITEM_ID}\",\"quantity\":2}]}" \
  "${CUSTOMER_TOKEN}")
ORDER_ID=$(echo "${ORDER_RESP}" | jq -r '.id // .order_id // empty')
echo "   order id: ${ORDER_ID}"

echo "=== Done. Seeded users, restaurant, menu, and one order. ==="
