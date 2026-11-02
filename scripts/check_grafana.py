#!/usr/bin/env python3
"""Check Grafana dashboards via API and verify provisioning loaded them."""
import urllib.request, json, base64, sys

BASE = "http://localhost:3000"
CREDS = base64.b64encode(b"admin:sentinelops123").decode()

def gf_get(path):
    req = urllib.request.Request(f"{BASE}{path}")
    req.add_header("Authorization", f"Basic {CREDS}")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=8) as r:
        return json.loads(r.read())

def gf_post(path, data):
    payload = json.dumps(data).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=payload, method="POST")
    req.add_header("Authorization", f"Basic {CREDS}")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=8) as r:
        return json.loads(r.read())

print("\n=== GRAFANA DATASOURCES ===")
for ds in gf_get("/api/datasources"):
    print(f"  [{ds['id']}] {ds['name']} ({ds['type']}) -> {ds['url']}  default={ds['isDefault']}")

print("\n=== GRAFANA DASHBOARDS ===")
results = gf_get("/api/search?type=dash-db")
if results:
    for d in results:
        print(f"  [{d['id']}] {d['title']}  folder={d.get('folderTitle','General')}  uid={d['uid']}")
else:
    print("  NO DASHBOARDS FOUND - provisioning may not have loaded them yet")

print("\n=== GRAFANA FOLDERS ===")
for f in gf_get("/api/folders"):
    print(f"  [{f['id']}] {f['title']}  uid={f['uid']}")

print("\n=== DATASOURCE TEST ===")
ds_list = gf_get("/api/datasources")
if ds_list:
    ds_id = ds_list[0]["id"]
    try:
        result = gf_get(f"/api/datasources/{ds_id}/health")
        print(f"  Datasource health: {result}")
    except Exception as e:
        print(f"  Health check error: {e}")

print()
