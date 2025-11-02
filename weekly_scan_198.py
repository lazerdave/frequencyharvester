#!/usr/bin/env python3
import subprocess, sys, re, statistics, time, random, json, os
from datetime import datetime, timezone
import requests
import sys, time
open("/home/pi/weekly_scan_198.log", "a").write(
    f"[start] {time.strftime('%Y-%m-%d %H:%M:%S %Z')}  argv={sys.argv}\n"
)

# ---- Adjust for your Pi ----
KIWIREC_PATH = "/home/pi/kiwiclient/kiwirecorder.py"
FREQ_KHZ     = "198"
PROBE_SEC    = 8
DEEP_SEC     = 20
RSSI_FLOOR   = -65.0
TARGET_COUNT = 100
CONNECT_TIMEOUT = 7
DISCOVERY_TIMEOUT = 8
OUT_DIR      = "/home/pi/kiwi_scans"   # results folder

PUBLIC_LIST_URLS = [
    "https://kiwisdr.com/public/",
    "https://kiwisdr.com/.public/",
]

COUNTRY_KEYS = [
    "United Kingdom","England","Scotland","Wales","Northern Ireland",
    "Isle of Man","Jersey","Guernsey","Channel Islands",
    "Ireland","Belgium","Netherlands","France","Luxembourg","GB","UK"
]
HOST_HINTS = (".uk", ".ie", ".je", ".gg", ".im", ".nl", ".be", ".fr")

SEED_HOSTS = [
    "norfolk.george-smart.co.uk:8073",
    "fordham.george-smart.co.uk:8073",
    "ixworthsdr.hopto.org:8073",
    "21785.proxy.kiwisdr.com:8073",
    "kernow.hopto.org:8073",
    "21246.proxy.kiwisdr.com:8073",
    "21247.proxy.kiwisdr.com:8073",
    "g4wim.proxy.kiwisdr.com:8073",
    "193.237.203.108:8074",
    "kiwisdr.g0dub.uk:8073",
    "g8gporx.proxy.kiwisdr.com:8073",
    "websdr.uk:8073",
    "21182.proxy.kiwisdr.com:8073",
    "21181.proxy.kiwisdr.com:8073",
    "antskiwisdr.zapto.org:8077",
    "antskiwisdr.zapto.org:8078",
    "185.128.57.240:8073",
    "21826.proxy.kiwisdr.com:8073",
    "uk-kiwisdr2.proxy.kiwisdr.com:8073",
]

HTTP_URL_RE = re.compile(r"https?://([A-Za-z0-9\-\.\:]+)", re.I)
RSSI_NUM_RE  = re.compile(r"(-?\d+(?:\.\d+)?)\s*dB(?:FS)?", re.I)
RSSI_RSSI_RE = re.compile(r"RSSI[=:]\s*(-?\d+(?:\.\d+)?)", re.I)

def fetch_candidates():
    found = []
    for url in PUBLIC_LIST_URLS:
        try:
            r = requests.get(url, timeout=DISCOVERY_TIMEOUT)
            r.raise_for_status()
            text = r.text
        except Exception:
            continue
        for line in text.splitlines():
            if not line.strip():
                continue
            country_hit = any(k in line for k in COUNTRY_KEYS)
            for m in HTTP_URL_RE.finditer(line):
                hp = m.group(1)
                if ":" not in hp: continue
                host, port = hp.rsplit(":", 1)
                if port not in ("8073","8074"): continue
                hint_hit = any(h in host.lower() for h in HOST_HINTS)
                if country_hit or hint_hit:
                    found.append(f"{host}:{port}")
    # merge with seeds, dedupe, shuffle
    cand = list(dict.fromkeys(found + SEED_HOSTS))
    random.shuffle(cand)
    return cand

def host_port(hp):
    h,p = hp.rsplit(":",1)
    return h,int(p)

def probe_smeter(host, port, seconds):
    cmd = [
        "python3", KIWIREC_PATH,
        "-s", host, "-p", str(port),
        "-f", FREQ_KHZ,
        "--S-meter=1",
        "--time-limit", str(seconds),
        "--quiet"
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True,
                              timeout=seconds+CONNECT_TIMEOUT)
    except subprocess.TimeoutExpired:
        return None, "timeout"
    out = (proc.stdout or "") + (proc.stderr or "")
    vals = [float(x) for x in RSSI_NUM_RE.findall(out)]
    if not vals:
        vals = [float(x) for x in RSSI_RSSI_RE.findall(out)]
    if not vals:
        return None, "no-RSSI"
    return vals, None

def ensure_dir(d):
    os.makedirs(d, exist_ok=True)

def save_json(payload):
    ensure_dir(OUT_DIR)
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%SZ")
    path = os.path.join(OUT_DIR, f"scan_198_{ts}.json")
    with open(path, "w") as f:
        json.dump(payload, f, indent=2)
    latest = os.path.join(OUT_DIR, "latest_scan_198.json")
    # update pointer
    tmp = latest + ".tmp"
    with open(tmp, "w") as f:
        json.dump(payload, f, indent=2)
    os.replace(tmp, latest)
    return path, latest

def main():
    print("Discovering KiwiSDRs in/near UK...")
    discovered = fetch_candidates()
    if not discovered:
        print("No candidates from public list(s). Using seeds only.")
        discovered = SEED_HOSTS[:]

    print(f"Found {len(discovered)} candidates, screening up to {TARGET_COUNT}...\n")
    t0 = time.perf_counter()
    tested=kept=0
    kept_rows=[]
    skipped_rows=[]

    for hp in discovered:
        if tested >= TARGET_COUNT: break
        host,port = host_port(hp)
        tested += 1
        tag = f"{host}:{port}"
        print(f"[{tested:3d}/{TARGET_COUNT}] {tag:40s}  ", end="", flush=True)
        vals, err = probe_smeter(host, port, PROBE_SEC)
        if err:
            print(f"SKIP ({err})")
            skipped_rows.append({"host":host,"port":port,"reason":err})
            continue
        avg = statistics.mean(vals)
        if avg < RSSI_FLOOR:
            print(f"SKIP (avg {avg:.1f} < {RSSI_FLOOR:.1f})")
            skipped_rows.append({"host":host,"port":port,"reason":f"weak {avg:.1f}"})
            continue
        mn,mx = min(vals), max(vals)
        kept += 1
        print(f"KEEP avg={avg:.1f} min={mn:.1f} max={mx:.1f} n={len(vals)}")
        kept_rows.append({
            "host":host,"port":port,
            "avg":round(avg,1),"min":round(mn,1),"max":round(mx,1),
            "n":len(vals)
        })

    screen_s = time.perf_counter()-t0
    kept_rows.sort(key=lambda r: r["avg"], reverse=True)
    top20 = kept_rows[:20]

    # Deep probe the top 20
    deep = []
    print("\nDeep 20-second probe on Top 20...\n")
    t1 = time.perf_counter()
    for i,row in enumerate(top20,1):
        tag=f'{row["host"]}:{row["port"]}'
        print(f"[deep {i:2d}/20] {tag:40s}  ", end="", flush=True)
        vals, err = probe_smeter(row["host"], row["port"], DEEP_SEC)
        if err:
            print(f"FAIL ({err})")
            continue
        avg  = statistics.mean(vals)
        med  = statistics.median(vals)
        mn,mx= min(vals), max(vals)
        stdev= statistics.pstdev(vals) if len(vals)>1 else 0.0
        deep.append({
            "host":row["host"], "port":row["port"],
            "avg":round(avg,1), "median":round(med,1),
            "stdev":round(stdev,2), "min":round(mn,1), "max":round(mx,1),
            "n":len(vals)
        })
        print(f'ok  avg={avg:.1f}  med={med:.1f}  σ={stdev:.2f}  range[{mn:.1f},{mx:.1f}]')

    deep.sort(key=lambda r: r["avg"], reverse=True)
    total_s = time.perf_counter()-t0

    payload = {
        "stamp_utc": datetime.utcnow().isoformat(timespec="seconds")+"Z",
        "freq_khz": int(FREQ_KHZ),
        "probe_sec": PROBE_SEC,
        "deep_sec": DEEP_SEC,
        "rssi_floor": RSSI_FLOOR,
        "tested": tested,
        "kept": kept,
        "screen_seconds": round(screen_s,1),
        "total_seconds": round(total_s,1),
        "top20": deep,              # deep results in rank order
        "kept_initial": kept_rows,  # shallow results, strongest first
        "skipped": skipped_rows
    }

    path, latest = save_json(payload)
    print(f"\nSaved scan JSON:\n  {path}\n  (pointer) {latest}")
    print(f"Total run time: {total_s:.1f}s ({total_s/60:.1f} min).  Ran at {payload['stamp_utc']}")

if __name__ == "__main__":
    main()
