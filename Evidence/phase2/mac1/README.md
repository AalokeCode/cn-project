# Phase 2 evidence — Mac 1 (primary DNS, Krishna, 10.7.5.108)

Each item has a `.png` screenshot and a `.txt` with the raw output (host, IP, timestamp, command).

| File | Requirement | Shows |
|---|---|---|
| 01-network-info | Task A | IP, mask, gateway, en0, MAC |
| 02-ping | Task A | Mac 1 → Mac 2/3/4, 0% loss |
| 03-dnsmasq-config | Task B, Ext B | Phase 2 dnsmasq config: app/api.team1.test → 10.7.22.206, `local-ttl=30` |
| 04-dnsmasq-running | Task B | dnsmasq process running, answering |
| 05-dig-app | Task B | `dig app.team1.test` → 10.7.22.206 (authoritative, from 10.7.5.108) |
| 06-dig-api | Task B | `api.team1.test` → 10.7.22.206 |
| 07-resolvers | Ext A | client lists primary 10.7.5.108 + backup 10.7.17.193 |
| 08-ttl | Ext B | record TTL 30 s (Phase 1 was 0) |
| 09-forwarding | Task B | non-project names forwarded upstream |

Team IPs: Mac 2 edge 10.7.22.206 · Mac 3 Backend A 10.7.2.47 · Mac 4 Backend B + backup DNS 10.7.17.193.

## Still pending (needs other Macs)
- Mac 4 backup dnsmasq not answering yet → Ext A failover test.
- Mac 2 nginx/TLS not answering, `rootCA.pem` not received → HTTPS, load balancing, caching, `.pcap`.
- Mac 3/4 backends must run the new code (ETag).
Once those are up, run `./scripts/mac1.sh phase1`, `extA`, `extB`, `extE`; output goes to `Evidences/phase2/mac1/`.
