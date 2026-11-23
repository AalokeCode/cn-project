# Phase 2 evidence — Mac 4 (Backend B :3002 + backup DNS + client, Hemanth, 10.7.2.47)

Each item has a `.png` screenshot and a `.txt` with the raw output (machine, IP, timestamp, command).
The `.txt` files are written by `scripts/mac4-solo.sh` / `scripts/mac4-extC-solo.sh`; the PNGs are drawn from them by
`scripts/render-evidence.py`.

| File | Requirement | Shows |
|---|---|---|
| p1-01-network-info | Task A | Mac 4 IP 10.7.2.47/19, gateway 10.7.0.1, en0, MAC |
| p1-02-ping | Task A | Mac 4 → Mac 1/2/3, 0% loss |
| p1-03-resolver | Task B, Ext A | client DNS = `10.7.5.108` (primary, Mac 1) then `10.7.2.47` (backup, Mac 4) |
| p1-04-dig | Task B | `dig app.team1.test` → 10.7.22.206 (edge) via team DNS |
| p1-05-https-by-name | Task E | `https://app.team1.test` by name, cert verified with the team CA (`--cacert`, no `-k`), TLS verify result 0, HTTP/2 |
| p1-06-backend | Task C | Backend B listening on `*:3002` (all interfaces), `/` and `/api/status`, `X-Backend: B` |
| p1-07-backend-304 | Task F | Backend B ETag → `If-None-Match` → `304 Not Modified` |
| p1-08-load-balancing | Task D | 8 requests by name alternate `X-Backend: B` / `A` (round-robin) |
| p1-09-edge-cache | Task F | `Cache-Control: max-age=60` + ETag through the edge; conditional request to the same backend → `HTTP/2 304` |
| extA-1-backup-config | Ext A | backup dnsmasq: `listen-address=10.7.2.47`, same records as primary, `local-ttl=30` |
| extA-2-backup-running | Ext A | dnsmasq running (as `nobody`), bound to `10.7.2.47:53`, answers app/api |
| extA-3-both-servers | Ext A | primary (10.7.5.108) and backup (10.7.2.47) return the same answer, TTL 30 |
| extA-4-backup-forwards | Ext A | backup still forwards non-project names (clients keep internet when primary is down) |
| extB-1-ttl | Ext B | project record served with a 30 s TTL |
| extC-0-rollback-copy-of-etc-pf.conf | Ext C | rollback copy of the macOS default pf rules |
| extC-1-before | Ext C | pf status before (Disabled) |
| extC-2-rules-on | Ext C | rules loaded: `pass in` only from edge 10.7.22.206 to :3002, `block return` for everyone else |
| extC-3-edge-allowed | Ext C | with rules ON the edge still reaches Backend B: pass-rule counters and live pf states from 10.7.22.206 |

Team IPs: Mac 1 DNS 10.7.5.108 · Mac 2 edge 10.7.22.206 · Mac 3 Backend A 10.7.17.193 · **Mac 4 Backend B + backup DNS 10.7.2.47**.

## Mac 4 status
- Backup DNS (Ext A): **running** on 10.7.2.47:53 with the Phase 2 config.
- Backend B: **running the new code** (ETag / 304 / HEAD) on `*:3002`.
- Client DNS on Mac 4: primary 10.7.5.108, backup 10.7.2.47.
- Team CA (Aaloke's mkcert root, exported from this Mac's keychain) at `~/cn-project/tls/rootCA.pem`: HTTPS by name verifies.

## Still pending (needs the other Macs at the same time)
- Ext A failover: Mac 1 stops dnsmasq, clients keep resolving through 10.7.2.47. Mac 1's evidence `07-resolvers` lists the backup as 10.7.17.193 — that is Backend A; the backup DNS is **10.7.2.47**.
- Ext B: `./scripts/mac4.sh dns-point <ip>` when Mac 1 changes the record, so both DNS servers agree.
- Ext C: Mac 1 / Mac 3 show `curl -m 3 http://10.7.2.47:3002/api/status` is refused while the rules are on.
- Ext D: Mac 3 stops Backend A → every request through the edge shows `X-Backend: B`.
- Ext E: `./scripts/mac4.sh extE` when Mac 1 cuts DNS over to the standby edge (Mac 3), then `dns-point 10.7.22.206`.
