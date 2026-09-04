# Learn TPC - Terminal Port Crawler

A practical guide to understanding how TPC works under the hood - for contributors, security students, and curious developers.

---

## What is TPC?

TPC is a Python-based network reconnaissance tool that performs TCP/UDP port scanning with threat analysis, banner grabbing, OS fingerprinting, and CVE references. It runs as either a full-screen terminal UI (TUI) or a command-line tool (CLI).

---

## Project Structure

```
tpc/
  __init__.py      # Package init
  __main__.py      # Entry point for `python -m tpc`
  scanner.py       # Core scanning logic + CLI entry point
  data.py          # Port definitions, service categories, threat data, CVEs
  screens.py       # Textual TUI screens, widgets, and layout
  utils.py         # Export, history, OS fingerprinting, threat analysis
```

**External dependencies:**
- [`textual`](https://github.com/Textualize/textual) - powers the TUI (widgets, layout, keybindings)
- Standard library only for scanning: `socket`, `threading`, `concurrent.futures`, `ipaddress`

---

## How Scanning Works

### TCP Scanning

The core of TCP scanning is a simple socket connect attempt:

```python
s = socket.socket()
s.settimeout(timeout)
s.connect((host, port))  # success = open, exception = closed/filtered
```

In `fast` and `random` modes, a `ThreadPoolExecutor` runs up to 100 workers in parallel. In `slow` mode, ports are checked one at a time with a configurable `time.sleep()` delay between each.

### UDP Scanning

UDP is connectionless - you cannot do a TCP-style connect. TPC sends 8 null bytes and interprets the response:

- Response received → **open**
- Timeout → **open/filtered** (follows nmap convention - UDP timeouts are ambiguous)
- `ConnectionRefusedError` (ICMP port unreachable) → **closed**

Only known UDP ports within the selected range are checked (not every port 1–65535).

### Target Parsing

TPC resolves targets before scanning:

| Input | How it's parsed |
|-------|----------------|
| Single IP | Used directly |
| Hostname | `socket.gethostbyname()` |
| CIDR (`/24`) | `ipaddress.ip_network()` expanded to host list |
| Dash range (`1.1.1.1-50`) | Split on `-`, last octet iterated |

---

## Port & Service Data (`data.py`)

All port knowledge lives in `data.py`. This is where you add new ports, categories, or threat data.

**TCP_PORTS** - maps port numbers to `(service_name, category)`:

```python
TCP_PORTS = {
    22:  ("SSH/SCP/SFTP", "File"),
    80:  ("HTTP",         "Web"),
    443: ("HTTPS",        "Web"),
    ...
}
```

**UDP_PORTS** - same structure, for known UDP services.

**THREAT_PORTS** - maps port numbers to risk level strings:

```python
THREAT_PORTS = {
    21:   "HIGH",   # FTP - plaintext credentials
    445:  "MEDIUM", # SMB - EternalBlue vector
    ...
}
```

**CVE_MAP** - maps port numbers to a list of `(CVE-ID, description)` tuples.

---

## OS Fingerprinting (`utils.py`)

TPC guesses the OS from which ports are open - no packet crafting, just pattern matching:

| Open ports | OS guess |
|-----------|----------|
| 135 + 445 | Windows |
| 135 + 445 + 902/912 | Windows + VMware |
| 902 or 912 (no 445) | VMware Host / Linux |
| 548 (no 445) | macOS (AFP) |
| 22 (no 135/445/139) | Linux / Unix |
| Anything else | Unknown |

This is intentionally simple - it's pattern matching, not active fingerprinting like `nmap -O`.

---

## Threat Analysis (`utils.py`)

After scanning, every open port is checked against `THREAT_PORTS`. The overall risk level is:

- **HIGH** if any port is rated HIGH
- **MEDIUM** if any port is rated MEDIUM (and none are HIGH)
- **LOW** otherwise

CVEs from `CVE_MAP` are pulled for any open port that has known vulnerabilities, and displayed in the Analysis tab / CLI output.

---

## Banner Grabbing (`scanner.py`)

For each open TCP port, TPC:

1. Checks if it's a known SSL port (443, 465, 993, etc.) → returns `SSL/TLS encrypted`
2. Opens a raw socket with a 2-second timeout and calls `recv(1024)`
3. If no data comes back, sends an HTTP HEAD request and retries
4. Returns the first 80 characters of the first response line
5. Falls back to `no banner`

---

## Exporting (`utils.py`)

Exports land in `exports/` (auto-created). Filename: `scan_<IP>_<YYYYMMDD_HHMMSS>.<ext>`.

| Format | What it contains |
|--------|-----------------|
| `txt` | Human-readable header + one line per open port |
| `csv` | IP, Hostname, Port, Service, Protocols, Banner |
| `json` | Full structured object with metadata |
| `html` | Styled HTML report (GitHub Dark theme) |

---

## The TUI (`screens.py`)

The TUI is built with [Textual](https://textual.textualize.io/). Key concepts:

- **App** - the root Textual app class, handles keybindings and screen management
- **Screens** - the disclaimer modal, the about modal, the main scan screen
- **Widgets** - sidebar inputs (target, port range, mode, options), the results DataTable, Analysis log, History tab
- **Workers** - scanning runs in a background thread via Textual's `run_in_thread` / `call_from_thread` pattern so the UI stays responsive
- **Messages** - workers post messages back to the UI to update the results table and stats live

---

## Scan History

Every completed scan is appended to `~/.tpc/scan_history.log`. The format is plain text - one block per scan. The History tab in the TUI reads this file on load.

---

## Adding a New Port

1. Open `tpc/data.py`
2. Add the port to `TCP_PORTS` or `UDP_PORTS`:
   ```python
   9200: ("Elasticsearch", "Database"),
   ```
3. Optionally add a threat rating to `THREAT_PORTS`:
   ```python
   9200: "MEDIUM",
   ```
4. Optionally add CVEs to `CVE_MAP`:
   ```python
   9200: [("CVE-2021-22145", "Elasticsearch info disclosure")],
   ```

---

## Key Concepts for Contributors

- **No external scan libraries** - all scanning is raw `socket` calls. TPC does not use nmap, scapy, or similar.
- **Threading model** - `concurrent.futures.ThreadPoolExecutor` for fast/random modes; sequential loop for slow mode.
- **TUI/CLI split** - `scanner.py:main()` checks for `-t` flag to decide CLI vs TUI. CLI prints results to stdout; TUI uses Textual widgets.
- **Data separation** - all port/threat/CVE knowledge is in `data.py`, keeping scanner logic clean.
- **No root required** - TCP connect scanning works without elevated privileges. UDP scanning may require root/admin on some systems.

---

## Building the Windows Executable

TPC ships as a single-file PyInstaller build (`tpc.spec`), producing `dist\tpc.exe`.

```
pyinstaller tpc.spec --noconfirm
```

The `.exe` icon comes from `assets\tpc.ico` (generated by `assets\make_icon.py`, which
draws a radar/scan glyph with Pillow) and is wired in via `icon=['assets\\tpc.ico']`
in the `EXE(...)` block of `tpc.spec`. Regenerate it with:

```
python assets/make_icon.py
```

### Code Signing (removing the SmartScreen warning)

An unsigned `.exe` downloaded from the internet always shows Windows SmartScreen's
"Windows protected your PC" prompt for other users - there is no manifest setting,
icon, or local trick that removes this for people who aren't you. The only real
fixes:

| Option | Effect | Cost |
|--------|--------|------|
| EV code-signing certificate | Instant SmartScreen reputation | ~$250-500/yr, business validation + hardware token |
| Standard (OV) code-signing certificate | Signed, but SmartScreen still needs downloads/time to build reputation | ~$70-300/yr |
| Microsoft Trusted Signing (Azure) | Fast reputation, subscription-based, no hardware token | ~$10/mo + Azure/identity setup |
| Self-signed cert + local Trusted Root install | Removes the warning only on machines where you installed the cert | Free, not viable for distribution |

Once you hold a `.pfx` cert (or one installed in your certificate store), sign the
build with:

```
./scripts/sign.ps1 -PfxPath C:\certs\tpc-codesign.pfx
# or, for a cert already in your Windows cert store:
./scripts/sign.ps1 -Thumbprint <thumbprint>
```

This runs `signtool sign` with a SHA-256 signature and RFC3161 timestamp (so the
signature stays valid after the cert expires), then verifies it.

**Heads up:** because TPC is a port scanner, SmartScreen/AV engines commonly flag
this class of tool as "HackTool" or "PUA" heuristically, even when properly signed.
If that happens after signing, submit the exe at
[Microsoft's file submission portal](https://www.microsoft.com/wdsi/filesubmission)
for reputation review.

---

## Legal

Only use TPC on systems you own or have explicit written permission to test. Unauthorized port scanning may be illegal under the CFAA, Computer Misuse Act, or equivalent laws in your jurisdiction.
