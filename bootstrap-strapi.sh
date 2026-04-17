#!/bin/bash
set -e

# Register or login admin
RESP=$(curl -s http://localhost:1337/admin/register-admin \
  -H 'Content-Type: application/json' \
  -d '{"firstname":"Admin","lastname":"User","email":"admin@stoside.org","password":"Admin1234!"}')

# If registration fails (already registered), login instead
if echo "$RESP" | python3 -c 'import sys,json; d=json.load(sys.stdin); exit(0 if d.get("data") else 1)' 2>/dev/null; then
  ADMIN_JWT=$(echo "$RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["token"])')
else
  echo "Admin already registered, logging in..."
  RESP=$(curl -s http://localhost:1337/admin/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"admin@stoside.org","password":"Admin1234!"}')
  ADMIN_JWT=$(echo "$RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["token"])')
fi
echo "JWT: ${ADMIN_JWT:0:20}..."

# Get public role ID
echo "=== Getting public role ==="
ROLES=$(curl -s http://localhost:1337/users-permissions/roles \
  -H "Authorization: Bearer $ADMIN_JWT")
echo "Roles response: $(echo $ROLES | head -c 200)"

PUBLIC_ROLE_ID=$(echo "$ROLES" | python3 -c 'import sys,json; roles=json.load(sys.stdin)["roles"]; print(next(r["id"] for r in roles if r["type"]=="public"))')
echo "Public role ID: $PUBLIC_ROLE_ID"

# Get current public role details  
echo "=== Public role details ==="
ROLE_DETAIL=$(curl -s "http://localhost:1337/users-permissions/roles/$PUBLIC_ROLE_ID" \
  -H "Authorization: Bearer $ADMIN_JWT")
echo "$ROLE_DETAIL" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(json.dumps(d, indent=2))' 2>&1 | head -60

# Build update payload enabling article find/findOne
echo "=== Updating permissions ==="
echo "$ROLE_DETAIL" | python3 -c '
import sys, json
data = json.load(sys.stdin)
perms = data["role"]["permissions"]
# Enable article find and findOne
if "api::article" not in perms:
    perms["api::article"] = {"controllers": {"article": {}}}
c = perms["api::article"]["controllers"]["article"]
c["find"] = {"enabled": True, "policy": ""}
c["findOne"] = {"enabled": True, "policy": ""}
# Enable author find and findOne
if "api::author" not in perms:
    perms["api::author"] = {"controllers": {"author": {}}}
a = perms["api::author"]["controllers"]["author"]
a["find"] = {"enabled": True, "policy": ""}
a["findOne"] = {"enabled": True, "policy": ""}
payload = {"permissions": perms}
print(json.dumps(payload))
' > /tmp/perms.json

echo "Payload:"
cat /tmp/perms.json | python3 -m json.tool | head -30

RESULT=$(curl -s -X PUT "http://localhost:1337/users-permissions/roles/$PUBLIC_ROLE_ID" \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -H 'Content-Type: application/json' \
  -d @/tmp/perms.json)
echo "Update result: $RESULT"

# Test GraphQL
echo "=== Testing GraphQL ==="
curl -s http://localhost:1337/graphql \
  -X POST \
  -H 'Content-Type: application/json' \
  -H 'apollo-require-preflight: true' \
  -d '{"query":"{ articles { documentId title } }"}'
echo ""
