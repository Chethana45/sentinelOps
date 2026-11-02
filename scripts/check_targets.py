#!/usr/bin/env python3
"""Query Prometheus targets API and print a clean status table."""
import urllib.request, json, sys

def fetch(url):
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            return json.loads(r.read())
    except Exception as e:
        print(f"ERROR fetching {url}: {e}")
        sys.exit(1)

# --- Prometheus targets ---
print("\n=== PROMETHEUS SCRAPE TARGETS ===")
d = fetch("http://localhost:9090/api/v1/targets")
targets = d["data"]["activeTargets"]
fmt = "{:<20} {:<35} {:<8} {}"
print(fmt.format("JOB", "INSTANCE", "HEALTH", "LAST ERROR"))
print("-" * 80)
for t in targets:
    job      = t["labels"].get("job", "?")
    instance = t["labels"].get("instance", "?")
    health   = t["health"]
    error    = t.get("lastError", "") or "none"
    print(fmt.format(job, instance, health, error[:50]))

# --- Grafana datasources ---
print("\n=== GRAFANA DATASOURCES ===")
import urllib.request, base64
req = urllib.request.Request("http://localhost:3000/api/datasources")
creds = base64.b64encode(b"admin:sentinelops123").decode()
req.add_header("Authorization", f"Basic {creds}")
try:
    with urllib.request.urlopen(req, timeout=5) as r:
        ds_list = json.loads(r.read())
    for ds in ds_list:
        print(f"  Name: {ds['name']}  Type: {ds['type']}  URL: {ds['url']}  Default: {ds['isDefault']}")
    if not ds_list:
        print("  No datasources found!")
except Exception as e:
    print(f"  ERROR: {e}")

# --- Test a real PromQL query ---
print("\n=== SAMPLE METRICS (live data) ===")
queries = [
    ("Node up?",         "up{job='node-exporter'}"),
    ("CPU idle %",       "avg(rate(node_cpu_seconds_total{mode='idle'}[1m]))*100"),
    ("RAM available MB", "node_memory_MemAvailable_bytes/1024/1024"),
    ("Disk used %",      "(1-(node_filesystem_free_bytes{mountpoint='/'}  /node_filesystem_size_bytes{mountpoint='/'}  ))*100"),
    ("Uptime seconds",   "node_time_seconds - node_boot_time_seconds"),
]
for label, q in queries:
    r = fetch(f"http://localhost:9090/api/v1/query?query={urllib.request.quote(q)}")
    results = r["data"]["result"]
    if results:
        val = results[0]["value"][1]
        try:    print(f"  {label:<22} = {float(val):.2f}")
        except: print(f"  {label:<22} = {val}")
    else:
        print(f"  {label:<22} = NO DATA")

print()
