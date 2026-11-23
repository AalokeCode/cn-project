# Phase 2 helper scripts

The scripts in `scripts/` do the setup checks, install the configs, run every command below, and save the **real output** (with machine, IP and time) to `Evidence/phase2/mac1` … `mac4`. Mac 1 also saves a `.pcap` you can open in Wireshark.

**Before the session (everyone, once):**

1. Tell the team your current IP (`ipconfig getifaddr en0`). If any IP differs from `scripts/team.env`, one person updates that file, commits and pushes.
2. Get the latest copy: `git pull`.
3. Mac 3 / Mac 4: start your backend in its own Terminal and leave it open:
   `python3 backends/backend-a/server.py` (Mac 3) · `python3 backends/backend-b/server.py` (Mac 4)
4. Copy the team CA: Mac 2 runs `mkcert -CAROOT` and sends **only `rootCA.pem`** to the others, who save it as `~/cn-project/tls/rootCA.pem`.
   Mac 3 also needs both certificate files from Mac 2's `/opt/homebrew/etc/nginx/certs/` for Extension E.
5. Run `./scripts/macN.sh check` (your Mac's number) until it says **All checks passed**. It offers to fix anything on your own Mac (configs, DNS settings, dnsmasq, nginx) and names who must fix anything else.
   Order: **Mac 2 first** (the edge), then Mac 1 and Mac 4 (DNS), then Mac 3.

**Run sheet (everyone in the same call/room; one row at a time):**

| Step | Mac 1 (DNS + client) | Mac 2 (edge) | Mac 3 (Backend A) | Mac 4 (Backend B + backup DNS) |
|---|---|---|---|---|
| 1 | `phase1` | `phase1` | `phase1` | `phase1` |
| 2 Ext A | `extA` | | | `extA` |
| 3 Ext B | `extB` (it tells Mac 4 when to act) | | | `dns-point …` when told (2nd Terminal tab) |
| 4 Ext C | `extC` | `extC` | `extC` (applies the firewall, waits, rolls back) | `extC` (same) |
| 5 Ext D | `extD` (tells Mac 3 when to stop/start A) | `extD` **after** Mac 1 finishes | Ctrl+C / restart Backend A when told | |
| 6 Ext E | `extE` | | `extE` (starts the standby edge, waits) | `extE` + `dns-point …` when told |

Each cell means `./scripts/macN.sh <cell>`. When a script shows **⏸**, it is waiting for someone else; it says who and what.
**Afterwards:** each Mac commits its own `Evidence/phase2/macN` folder.

For Extension F practice, see `scripts/troubleshooting-runbook.md`.
