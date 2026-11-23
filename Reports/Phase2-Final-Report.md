# Phase 2 Final Report — Team 1

Krishna (Mac 1) · Aaloke (Mac 2) · Arina (Mac 3) · Hemanth (Mac 4)
Run date: 2026-11-23. All evidence: [SUBMISSION.md](../SUBMISSION.md).

## 1. What changed from Phase 1

- **Edge (Mac 2):** nginx moved from 8443 to 443 with `http2 on`. The upstream now has passive health checks (`max_fails=1 fail_timeout=10s`) and retries a failed request on the other backend (`proxy_next_upstream error timeout http_502 http_503 http_504`, `proxy_connect_timeout 2s`). It sends a single `Cache-Control: max-age=60` and an `X-Edge` header that names the edge that served the request. Config: [nginx-phase2.conf](../Configuration/phase2/nginx-phase2.conf).
- **DNS:** a backup dnsmasq on Mac 4 serves the same records as the primary on Mac 1. Clients list both servers. TTL raised from 0 to 30 s so caching and cutover are visible. Configs: [dnsmasq-primary.conf](../Configuration/phase2/dnsmasq-primary.conf), [dnsmasq-backup.conf](../Configuration/phase2/dnsmasq-backup.conf).
- **Backends:** return an `ETag`, answer `If-None-Match` with `304 Not Modified`, and support `HEAD`.
- **Isolation:** pf rule files that let only the edge reach ports 3001/3002 ([pf-isolation-mac3.conf](../Configuration/phase2/pf-isolation-mac3.conf), [pf-isolation-mac4.conf](../Configuration/phase2/pf-isolation-mac4.conf)).
- **Edge redundancy:** Mac 3 can run a standby copy of the edge config for a DNS-based cutover.
- **Process:** every test is a script section (`scripts/macN.sh`) that saves the real output with machine, IP and time. A LAN message board on Mac 2 (`scripts/coord-server.py`) kept the four Macs in step during the run.
- **IPs:** all four changed through DHCP since Phase 1 (see [Architecture/phase2.md](../Architecture/phase2.md)).

## 2. Resilience tests and results

| Test | Result | Evidence |
|---|---|---|
| Phase 1 retakes (LAN, DNS, HTTPS by name, LB, caching) | Pass on all four Macs. Ping 0% loss; `dig` → 10.7.22.206 with TTL 30; TLS verified with the team CA (no `-k`), HTTP/2; `X-Backend` alternates A/B; `If-None-Match` → 304 | `Evidence/phase2/mac*/p1-*` |
| Packet capture (Task G) | DNS query/answer on UDP 53, TCP handshake to 10.7.22.206:443, TLS records then encrypted application data | [p1-09-full-request.pcap](../Evidence/phase2/mac1/p1-09-full-request.pcap) |
| Ext A — primary DNS down | Pass. `dig @10.7.5.108` timed out; the client still resolved `app.team1.test` → 10.7.22.206 from 10.7.2.47; HTTPS by name still returned `HTTP/2 200` | [mac1/extA-*](../Evidence/phase2/mac1/), [mac4/extA-*](../Evidence/phase2/mac4/) |
| Ext B — TTL and record change | Pass. Record moved to 10.7.17.193 on both servers; the client kept the cached 10.7.22.206 and switched about 43 s after caching it (TTL 30 s); `dscacheutil -flushcache` made the revert visible immediately | [mac1/extB-*](../Evidence/phase2/mac1/) |
| Ext C — service isolation | Partial. With Mac 4's rules on, a client got `curl: (7) Failed to connect to 10.7.2.47 port 3002` while the edge still reached Backend B (pf pass-rule counters and states from 10.7.22.206). Mac 3 was not isolated in that run, and the team section was skipped | [mac1/16-extC-mac4-isolated](../Evidence/phase2/mac1/16-extC-mac4-isolated.png), [mac4/extC-*](../Evidence/phase2/mac4/), [mac2/extC-1](../Evidence/phase2/mac2/extC-1-edge-allowed.png) |
| Ext D — backend failover | Pass. Backend A stopped at 19:23:05: 6/6 requests `HTTP/2 200 x-backend: B`. nginx logged `connect() failed (61: Connection refused)` to 10.7.17.193:3001 at 19:23:26 and the same request was answered `200`. After A restarted and the 10 s `fail_timeout` passed, A/B alternation resumed | [mac1/extD-*](../Evidence/phase2/mac1/), [mac2/extD-*](../Evidence/phase2/mac2/) |
| Ext E — edge migration | Pass. Standby nginx on Mac 3 passed `nginx -t` and served `x-edge: mac3`. After the DNS cutover a client with a cached answer still got `x-edge: mac2`, then `x-edge: mac3` after the TTL; a fresh client went straight to `mac3`. DNS was cut back to 10.7.22.206 and the standby stopped | [mac1/extE-*](../Evidence/phase2/mac1/), [mac3/extE-*](../Evidence/phase2/mac3/), [mac4/extE-1](../Evidence/phase2/mac4/extE-1-fresh-client.png) |

## 3. Troubleshooting findings (from the run)

| Symptom | Layer | Cause → fix |
|---|---|---|
| Edge could not reach Backend B (`Connection refused` on :3002) although `ping 10.7.2.47` worked | Transport / application | Backend process not running. IP fine, port closed → start `server.py`. Ping proves IP reachability only, not the service. |
| `ping` to Mac 1 and Mac 3 failed once, worked seconds later | Network (Wi-Fi) | Lost ICMP on Wi-Fi; retry with `-c 3` before calling a host down. |
| Mac 3/Mac 4 IPs swapped in a teammate's `team.env` | Configuration | Checked live with `curl -i http://<ip>:<port>/api/status` and the `X-Backend` header; fixed `team.env` once for everyone. |
| All IPs different from Phase 1 | Network (DHCP) | Re-read `ipconfig getifaddr en0` on every Mac before each session; one shared `team.env`. |
| Old nginx kept port 443/8443 busy and `brew services` restarted it | Application | Stop the brew service before starting nginx with the new config; verify with `lsof -iTCP:443 -sTCP:LISTEN`. |
| Client still on the old IP after the record change | DNS cache | Expected TTL behaviour (macOS held it ~43 s for a 30 s TTL). Flush with `dscacheutil -flushcache; killall -HUP mDNSResponder` when an immediate change is needed. |
| First Ext D attempt left no failover in the nginx logs | Process | Backend A was never actually stopped during Mac 1's run. Re-ran with an explicit STOP/START cue and checked `:3001` was refused before continuing. |

Method for the live fault (Ext F): DNS (`dig`) → TCP (`nc -z host port`) → TLS (`curl -v --cacert`) → HTTP (`curl -i`, nginx `error.log`). See [troubleshooting-runbook.md](../scripts/troubleshooting-runbook.md).

## 4. Learning summary

**Ext A — Backup DNS.** A DNS failure and an application failure look different from the client. With the primary DNS down, the name still resolved from the backup and the app kept working. With a wrong DNS server, the name did not resolve even though the edge answered ping by IP. DNS only maps names to addresses, so a second resolver with the same records removes it as a single point of failure for new lookups. This is what secondary name servers and multi-provider DNS do in production.

**Ext B — TTL.** The TTL is a promise about how long an answer may be reused, and clients keep it. After we changed the record, the client still used the old IP until its cached copy expired (about 43 s on macOS for a 30 s TTL), then moved over. A flush made the change visible at once. In production this is why teams lower the TTL well before a migration and wait at least one old TTL before switching traffic.

**Ext C — Service isolation.** The firewall turns "clients never talk to backends" from a convention into a rule. With pf on Mac 4, a client's direct connection to :3002 was refused while the edge, the only allowed source, still got through. This is the security-group / private-subnet pattern behind a cloud load balancer. We kept a rollback copy of `/etc/pf.conf` and restored it after the test. The team-wide run was skipped this round, so only Mac 4's side is captured.

**Ext D — HA failover.** nginx's passive health check needs no extra service. When Backend A refused a connection, nginx marked it down for 10 s and retried the same request on B, so the client saw only 200s. When A came back, nginx tried it again after `fail_timeout` and round-robin resumed. The edge itself is still the single point of failure: two edges behind a floating IP (keepalived/VRRP) or a managed load balancer would remove it.

**Ext E — DNS-based edge migration.** DNS can move traffic between edges without touching clients, but not instantly. After the record moved to the standby edge on Mac 3, a fresh client went straight there, while a client with a cached answer stayed on Mac 2 until the TTL ran out. The `X-Edge` header made it visible which edge served each request. This is how blue/green and region failover work with DNS, and why TTL planning matters.

**Ext F — Troubleshooting.** Going layer by layer is faster than guessing. In our own run, a backend that was down looked like a network problem until `nc -z` showed the host was up but the port was closed. We use the same order for the faculty fault: name resolution, TCP connect, TLS, then the application and the nginx logs.

## 5. Known limitations

- Ext C was not run as a full team section (Mac 3's rules were never captured), so isolation is shown for Backend B only.
- In Ext B, `extB-6` shows the reverted answer already in the client cache, so "cached again" is not visible there. The TTL behaviour is shown by `extB-4` → `extB-5`.
- The Phase 1 TCP/TLS Wireshark capture is still missing ([Evidence/README.md](../Evidence/README.md)). Phase 2's `p1-09-full-request.pcap` now covers DNS, TCP and TLS for one request.
