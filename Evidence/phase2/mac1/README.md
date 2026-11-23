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
| 07-resolvers | Ext A | client lists primary 10.7.5.108 + backup 10.7.2.47 |
| 08-ttl | Ext B | record TTL 30 s (Phase 1 was 0) |
| 09-forwarding | Task B | non-project names forwarded upstream |
| 10-https-tls | Task E | HTTPS by name, TLS 1.3, HTTP/2 (ALPN h2), cert verified by team mkcert CA, no `-k` |
| 11-load-balancing | Task D | X-Backend alternates A/B via edge (x-edge: mac2) |
| 12-curl-I | Task F | `Cache-Control: max-age=60`, `ETag` |
| 13-conditional-304 | Task F | `If-None-Match` → 304 from issuing backend, 200 from the other |
| 14-api-host | Task B/D | api.team1.test served by edge |
| 15-wrong-dns | Failure demo / Ext A | wrong DNS (8.8.8.8) → no answer, but IP ping to edge works |
| 16-extC-mac4-isolated | Ext C | direct curl to Backend B :3002 refused (Mac 4 pf ON) |
| 17-extC-mac3-not-yet-isolated | Ext C | Backend A :3001 still reachable at that moment (Mac 3 pf not on) |
| 18-extC-edge-still-works | Ext C | A/B still served via edge while isolated |
| 19-backup-dns | Ext A | backup DNS 10.7.2.47 answers app.team1.test → 10.7.22.206 |

Team IPs: Mac 2 edge 10.7.22.206 · Mac 3 Backend A 10.7.17.193 · Mac 4 Backend B + backup DNS 10.7.2.47.

## Still pending
- Mac 3 pf rules ON → retake Ext C for Backend A.
- `.pcap` (Task G), Ext A failover, Ext B, Ext E: run `./scripts/mac1.sh phase1 / extA / extB / extE` with the team.
