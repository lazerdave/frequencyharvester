#!/usr/bin/env python3
"""
Record 198 kHz from the best recent KiwiSDR and save with a tidy, podcast-friendly name.

Filename format example:
  ShippingFCST-251019_AM_032829UTC--g8gporx.proxy.kiwisdr--avg-36.wav

Features:
- Adds AM/PM in filename and sidecar file
- Passes --filename WITHOUT extension (kiwirecorder appends .wav)
- Writes sidecar text file with attribution
- Updates latest.wav symlink
- Rebuilds RSS feed
"""

from datetime import datetime, timezone
from zoneinfo import ZoneInfo
import json, os, sys, time, subprocess, re, statistics, pathlib

# ---------- CONFIG ----------
KIWI_REC   = "/home/pi/kiwiclient/kiwirecorder.py"
SCAN_PTR   = "/home/pi/kiwi_scans/latest_scan_198.json"   # produced by weekly_scan_198.py
OUT_DIR    = "/home/pi/share/198k"                        # served by nginx
FREQ_KHZ   = "198"
MODE       = "am"
DUR_SEC    = 13 * 60
RSSI_REFRESH_SEC = 6
MAKE_FEED  = "/home/pi/make_feed.py"
FALLBACK_HOST = "norfolk.george-smart.co.uk"
FALLBACK_PORT = 8073

RSSI_NUM_RE  = re.compile(r"(-?\d+(?:\.\d+)?)\s*dB(?:FS)?", re.I)
RSSI_RSSI_RE = re.compile(r"RSSI[=:]\s*(-?\d+(?:\.\d+)?)", re.I)


def now_parts_with_ampm():
    """Return tuple (utc_date, ampm, utc_time)"""
    now_utc = datetime.now(timezone.utc)
    ampm = now_utc.strftime("%p")  # AM or PM
    utc_date = now_utc.strftime("%y%m%d")
    utc_time = now_utc.strftime("%H%M%S")
    return utc_date, ampm, utc_time


def pick_site_from_scan(ptr_path: str):
    if not os.path.exists(ptr_path):
        return (FALLBACK_HOST, FALLBACK_PORT, None, "no-scan-file")
    try:
        with open(ptr_path) as f:
            data = json.load(f)
    except Exception as e:
        return (FALLBACK_HOST, FALLBACK_PORT, None, f"scan-read-error: {e}")
    top = data.get("top20") or []
    kept = data.get("kept_initial") or []
    if top:
        r = top[0]; return (r["host"], int(r["port"]), r.get("avg"), None)
    if kept:
        kept.sort(key=lambda r: r["avg"], reverse=True)
        r = kept[0]; return (r["host"], int(r["port"]), r.get("avg"), "fallback-kept-initial")
    return (FALLBACK_HOST, FALLBACK_PORT, None, "empty-scan")


def smeter_avg(host: str, port: int, seconds: int):
    cmd = [
        "python3", KIWI_REC, "-s", host, "-p", str(port),
        "-f", FREQ_KHZ, "--S-meter=1", "--time-limit", str(seconds), "--quiet"
    ]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=seconds + 8)
    except subprocess.TimeoutExpired:
        return None
    out = (p.stdout or "") + (p.stderr or "")
    vals = [float(x) for x in RSSI_NUM_RE.findall(out)] or \
           [float(x) for x in RSSI_RSSI_RE.findall(out)]
    return round(statistics.mean(vals), 1) if vals else None


def hostname_short(host: str) -> str:
    """Shorten hostname like g8gporx.proxy.kiwisdr.com -> g8gporx.proxy.kiwisdr"""
    h = host.split(":")[0]
    parts = h.split(".")
    if len(parts) >= 3:
        return ".".join(parts[:3])
    elif len(parts) == 2:
        return parts[0]
    return h


def make_base_name(utc_date: str, ampm: str, utc_time: str, host_short: str, rssi: float) -> str:
    rssi_int = int(round(abs(rssi))) if isinstance(rssi, (int, float)) else 999
    return f"ShippingFCST-{utc_date}_{ampm}_{utc_time}UTC--{host_short}--avg-{rssi_int}"


def write_sidecar(path_wav: str, host: str, port: int, rssi_label: float, ampm: str):
    txt = path_wav.replace(".wav", ".txt")
    now_utc = datetime.now(timezone.utc)
    now_lon = now_utc.astimezone(ZoneInfo("Europe/London"))
    body = (
        "Station recording summary\n"
        f"File : {os.path.basename(path_wav)}\n"
        f"Host : {host}:{port}\n"
        f"Freq : {FREQ_KHZ} kHz, Mode: {MODE}\n"
        f"RSSI : {rssi_label} dBFS (fresh at start)\n"
        f"UTC  : {now_utc.strftime('%Y-%m-%d %H:%M:%S')}Z ({ampm})\n"
        f"LON  : {now_lon.strftime('%Y-%m-%d %H:%M:%S %Z')}\n"
        "\n"
        "CREDIT / ORIGIN:\n"
        "  Received via KiwiSDR network (https://kiwisdr.com)\n"
        f"  Receiver host: {host}:{port}\n"
        "Use non-commercially and credit the receiver operator where possible.\n"
    )
    with open(txt, "w", encoding="utf-8") as f:
        f.write(body)
    return txt


def record(host: str, port: int, out_base_no_ext: str):
    """Pass filename base (no extension) to kiwirecorder; it will write .wav"""
    pathlib.Path(OUT_DIR).mkdir(parents=True, exist_ok=True)
    cmd = [
        "python3", KIWI_REC,
        "-s", host, "-p", str(port),
        "-f", FREQ_KHZ, "-m", MODE,
        "--time-limit", str(DUR_SEC),
        "--filename", out_base_no_ext
    ]
    print("Recording:", " ".join(cmd))
    subprocess.run(cmd, check=True)
    return out_base_no_ext + ".wav"


def maybe_build_feed():
    if os.path.exists(MAKE_FEED):
        try:
            subprocess.run(["/usr/bin/python3", MAKE_FEED], check=False)
        except Exception as e:
            print("Feed build skipped/error:", e)


def main():
    utc_d, ampm, utc_t = now_parts_with_ampm()
    host, port, scan_avg, why = pick_site_from_scan(SCAN_PTR)
    if why: print("Scan note:", why)
    print(f"Chosen site: {host}:{port} (scan avg: {scan_avg})")

    fresh = smeter_avg(host, port, RSSI_REFRESH_SEC)
    rssi_for_label = fresh if fresh is not None else (scan_avg if scan_avg is not None else -999.0)
    print(f"Fresh RSSI: {fresh} dBFS  |  Using in label: {rssi_for_label} dBFS")

    host_short = hostname_short(host)
    base_name = make_base_name(utc_d, ampm, utc_t, host_short, rssi_for_label)
    out_base = os.path.join(OUT_DIR, base_name)

    wav_path = record(host, port, out_base)
    write_sidecar(wav_path, host, port, rssi_for_label, ampm)

    latest = os.path.join(OUT_DIR, "latest.wav")
    try:
        if os.path.islink(latest) or os.path.exists(latest):
            os.remove(latest)
        os.symlink(wav_path, latest)
    except Exception as e:
        print("latest.wav symlink not updated:", e)

    maybe_build_feed()
    print("Saved:", wav_path)

    # Log timestamps for easy debugging
    now = datetime.now(timezone.utc)
    print(
        "Health:",
        now.isoformat(timespec="seconds") + "Z",
        "| London:",
        now.astimezone(ZoneInfo("Europe/London")).strftime("%Y-%m-%d %H:%M:%S %Z"),
    )


if __name__ == "__main__":
    main()
