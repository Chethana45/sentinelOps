#!/usr/bin/env python3
"""
Push the SentinelOps dashboard JSON to Grafana via the API.
This is idempotent — safe to run multiple times.
"""
import urllib.request, json, base64, sys, pathlib

GRAFANA = "http://localhost:3000"
CREDS   = base64.b64encode(b"admin:sentinelops123").decode()
DASH_FILE = pathlib.Path("/mnt/c/Users/cheth/OneDrive/Desktop/sentinelOps/grafana/dashboards/system_overview.json")

def api(method, path, data=None):
    url = f"{GRAFANA}{path}"
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Authorization", f"Basic {CREDS}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read()), r.status
    except urllib.error.HTTPError as e:
        body_text = e.read().decode()
        print(f"  HTTP {e.code} on {method} {path}: {body_text[:200]}")
        return None, e.code

print("\n=== Pushing Dashboard to Grafana ===")

# 1. Load dashboard JSON
dash = json.loads(DASH_FILE.read_text())
dash["id"] = None   # let Grafana assign ID on create/update

# 2. Get or create the SentinelOps folder
folders, _ = api("GET", "/api/folders")
folder_uid  = None
for f in (folders or []):
    if f["uid"] == "sentinelops":
        folder_uid = f["uid"]
        print(f"  Folder already exists: {f['title']} (uid={folder_uid})")
        break

if not folder_uid:
    result, code = api("POST", "/api/folders", {"uid": "sentinelops", "title": "SentinelOps"})
    if result:
        folder_uid = result["uid"]
        print(f"  Created folder: SentinelOps (uid={folder_uid})")
    else:
        print("  ERROR: Could not create folder")
        sys.exit(1)

# 3. Push (upsert) the dashboard
payload = {
    "dashboard":  dash,
    "folderUid":  folder_uid,
    "overwrite":  True,
    "message":    "Pushed by deploy_dashboard.py — validated queries v2"
}
result, code = api("POST", "/api/dashboards/db", payload)
if result and code == 200:
    uid  = result.get("uid", "?")
    slug = result.get("slug", "?")
    url  = result.get("url", f"/d/{uid}")
    print(f"\n  SUCCESS!")
    print(f"  Dashboard UID : {uid}")
    print(f"  Dashboard URL : http://localhost:3000{url}")
    print(f"  Status        : {result.get('status','?')}")
else:
    print(f"\n  FAILED (HTTP {code})")
    sys.exit(1)

# 4. Verify it's retrievable
check, _ = api("GET", f"/api/dashboards/uid/sentinelops-system-overview")
if check:
    meta  = check.get("meta", {})
    ddata = check.get("dashboard", {})
    print(f"\n  Verification:")
    print(f"    Title      : {ddata.get('title')}")
    print(f"    Panels     : {len(ddata.get('panels', []))}")
    print(f"    Folder     : {meta.get('folderTitle')}")
    print(f"    Updated    : {meta.get('updated')}")
else:
    print("  WARNING: Dashboard pushed but verification GET failed")

print()
