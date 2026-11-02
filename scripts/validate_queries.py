#!/usr/bin/env python3
"""
Validate all PromQL queries that will be used in the SentinelOps dashboard.
Prints each query, its result value, and PASS/FAIL status.
"""
import urllib.request, json, sys

PROM = "http://localhost:9090"

def query(q):
    url = f"{PROM}/api/v1/query?query={urllib.request.quote(q)}"
    with urllib.request.urlopen(url, timeout=8) as r:
        d = json.loads(r.read())
    results = d["data"]["result"]
    if not results:
        return None, []
    # Return first result value + all label sets
    val = results[0]["value"][1]
    labels = [r["metric"] for r in results]
    return val, labels

queries = [
    # (panel_title, promql, expected_unit, min_expected, max_expected)
    ("Service UP - node-exporter",
     "up{job='node-exporter'}",                                                            "1=up",  1,  1),
    ("Service UP - prometheus",
     "up{job='prometheus'}",                                                               "1=up",  1,  1),
    ("Service UP - alertmanager",
     "up{job='alertmanager'}",                                                             "1=up",  1,  1),
    ("Service UP - grafana",
     "up{job='grafana'}",                                                                  "1=up",  1,  1),
    ("CPU Usage %",
     "100-(avg(rate(node_cpu_seconds_total{mode='idle'}[5m]))*100)",                       "%",     0, 100),
    ("CPU User %",
     "avg(rate(node_cpu_seconds_total{mode='user'}[5m]))*100",                            "%",     0, 100),
    ("CPU System %",
     "avg(rate(node_cpu_seconds_total{mode='system'}[5m]))*100",                          "%",     0, 100),
    ("CPU IOWait %",
     "avg(rate(node_cpu_seconds_total{mode='iowait'}[5m]))*100",                          "%",     0, 100),
    ("Load Average 1m",
     "node_load1",                                                                         "load",  0,  None),
    ("Load Average 5m",
     "node_load5",                                                                         "load",  0,  None),
    ("Load Average 15m",
     "node_load15",                                                                        "load",  0,  None),
    ("CPU Core Count",
     "count(count(node_cpu_seconds_total)by(cpu))",                                        "cores", 1,  None),
    ("RAM Total bytes",
     "node_memory_MemTotal_bytes",                                                         "bytes", 1,  None),
    ("RAM Used bytes",
     "node_memory_MemTotal_bytes-node_memory_MemAvailable_bytes",                          "bytes", 0,  None),
    ("RAM Available bytes",
     "node_memory_MemAvailable_bytes",                                                     "bytes", 0,  None),
    ("RAM Usage %",
     "(1-(node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes))*100",               "%",     0,  100),
    ("Swap Usage %",
     "(1-(node_memory_SwapFree_bytes/node_memory_SwapTotal_bytes))*100",                  "%",     0,  100),
    ("Disk Usage % /",
     "(1-(node_filesystem_free_bytes{mountpoint='/'}/ node_filesystem_size_bytes{mountpoint='/'}))*100", "%", 0, 100),
    ("Disk Available bytes",
     "node_filesystem_free_bytes{mountpoint='/'}",                                         "bytes", 0,  None),
    ("Disk Total bytes",
     "node_filesystem_size_bytes{mountpoint='/'}",                                         "bytes", 1,  None),
    ("Disk Read bytes/s",
     "sum(rate(node_disk_read_bytes_total[5m]))",                                          "Bps",   0,  None),
    ("Disk Write bytes/s",
     "sum(rate(node_disk_written_bytes_total[5m]))",                                       "Bps",   0,  None),
    ("Net Receive bytes/s",
     "sum(rate(node_network_receive_bytes_total{device!~'lo|docker.*|br-.*|veth.*'}[5m]))", "Bps", 0, None),
    ("Net Transmit bytes/s",
     "sum(rate(node_network_transmit_bytes_total{device!~'lo|docker.*|br-.*|veth.*'}[5m]))", "Bps",0, None),
    ("System Uptime seconds",
     "node_time_seconds-node_boot_time_seconds",                                           "s",    60, None),
    ("Running Processes",
     "node_procs_running",                                                                  "procs", 1, None),
    ("Open File Descriptors",
     "node_filefd_allocated",                                                               "fds",   1, None),
]

print(f"\n{'='*80}")
print(f"  SentinelOps Dashboard PromQL Validation")
print(f"{'='*80}")
fmt = "{:<35} {:<12} {:<8}"
print(fmt.format("PANEL", "VALUE", "STATUS"))
print("-"*60)

all_pass = True
for title, q, unit, mn, mx in queries:
    try:
        val, labels = query(q)
        if val is None:
            print(fmt.format(title[:34], "NO DATA", "FAIL"))
            all_pass = False
            continue
        fval = float(val)
        ok = True
        if mn is not None and fval < mn: ok = False
        if mx is not None and fval > mx: ok = False
        disp = f"{fval:.2f} {unit}"
        print(fmt.format(title[:34], disp[:11], "PASS" if ok else "WARN"))
        if not ok:
            all_pass = False
    except Exception as e:
        print(fmt.format(title[:34], "ERROR", "FAIL"))
        print(f"  -> {e}")
        all_pass = False

print("-"*60)
print(f"\n  Result: {'ALL QUERIES PASS' if all_pass else 'SOME QUERIES NEED ATTENTION'}\n")
