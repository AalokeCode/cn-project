# CN Project — Team 1 — Submission Index

Private Network Service Platform, Phase 1 + Phase 2. Every deliverable and every piece of evidence is linked from this page.
Phase 2 evidence: each item is a `.txt` (real command output with machine, IP and time) plus a `.png` of it.

| Mac | Owner | Phase 2 role | IP |
|---|---|---|---|
| 1 | Krishna | Primary DNS (dnsmasq) + test client | 10.7.5.108 |
| 2 | Aaloke | Edge nginx: TLS :443, HTTP/2, load balancer, failover | 10.7.22.206 |
| 3 | Arina | Backend A :3001 + standby edge (Ext E) | 10.7.17.193 |
| 4 | Hemanth | Backend B :3002 + backup DNS (Ext A) + test client | 10.7.2.47 |

Domain: `app.team1.test` / `api.team1.test` → 10.7.22.206. Entry point: `https://app.team1.test/api/status`.

## 1. Deliverables (project doc Section 9)

| Deliverable | Where |
|---|---|
| Architecture document | Phase 1: [topology](Architecture/topology.md), [IP table](Architecture/ip-table.txt), [request flow](Architecture/request-flow.md). Phase 2 update: [Architecture/phase2.md](Architecture/phase2.md) |
| Configuration bundle | Phase 1: [Configuration/](Configuration/) (`dnsmasq.conf`, `nginx.conf`, `TLS-notes.txt`, `backend-launch-instructions.md`). Phase 2: [Configuration/phase2/](Configuration/phase2/) (`nginx-phase2.conf`, `dnsmasq-primary.conf`, `dnsmasq-backup.conf`, `pf-isolation-mac3.conf`, `pf-isolation-mac4.conf`) |
| Backend source code | [Backends/](Backends/) (Phase 2 code: ETag, 304, HEAD). Helper scripts: [scripts/](scripts/README.md) |
| Evidence folder | Phase 1: [Evidence/](Evidence/README.md). Phase 2: [Evidence/phase2/](Evidence/phase2/) — per Mac: [mac1](Evidence/phase2/mac1/README.md), [mac2](Evidence/phase2/mac2/README.md), [mac3](Evidence/phase2/mac3/README.md), [mac4](Evidence/phase2/mac4/README.md) |
| Phase 2 final report | [Reports/Phase2-Final-Report.md](Reports/Phase2-Final-Report.md) |
| Ext F practice | [scripts/troubleshooting-runbook.md](scripts/troubleshooting-runbook.md) |

## 2. Final demonstration sequence (Section 8) → evidence

| # | Step | Evidence |
|---|---|---|
| 1 | Topology and IP/service inventory | [Architecture/phase2.md](Architecture/phase2.md), [topology-diagram.png](Architecture/topology-diagram.png) |
| 2 | All machines on the private LAN | `p1-01-network-info` + `p1-02-ping` on every Mac: [mac1](Evidence/phase2/mac1/p1-02-ping.png), [mac2](Evidence/phase2/mac2/p1-02-ping.png), [mac3](Evidence/phase2/mac3/p1-02-ping.png), [mac4](Evidence/phase2/mac4/p1-02-ping.png) |
| 3 | Resolve the domain from a client | [mac1/p1-04-dig](Evidence/phase2/mac1/p1-04-dig.png), [mac3/p1-04-dig](Evidence/phase2/mac3/p1-04-dig.png), [mac4/p1-04-dig](Evidence/phase2/mac4/p1-04-dig.png) |
| 4 | HTTPS by name, no certificate warning, no `-k` | [mac1/p1-06-tls](Evidence/phase2/mac1/p1-06-tls.png), [mac4/p1-05-https-by-name](Evidence/phase2/mac4/p1-05-https-by-name.png), [mac2/p1-06-cert](Evidence/phase2/mac2/p1-06-cert.png), [mac2/p1-07-http2](Evidence/phase2/mac2/p1-07-http2.png) |
| 5 | Load balancing across both backends | [mac1/p1-05-load-balancing](Evidence/phase2/mac1/p1-05-load-balancing.png), [mac2/p1-08-load-balancing](Evidence/phase2/mac2/p1-08-load-balancing.png), [mac4/p1-08-load-balancing](Evidence/phase2/mac4/p1-08-load-balancing.png), nginx upstream: [mac2/p1-04-upstream](Evidence/phase2/mac2/p1-04-upstream.png) |
| 6 | Wireshark: DNS, TCP and TLS | [mac1/p1-09-full-request.pcap](Evidence/phase2/mac1/p1-09-full-request.pcap) (open in Wireshark) + [p1-09-full-request.png](Evidence/phase2/mac1/p1-09-full-request.png): DNS query/answer on UDP 53, SYN → SYN-ACK → ACK on TCP 443, TLS records, encrypted data |
| 7 | HTTP headers and caching (304) | [mac1/p1-07-curl-I](Evidence/phase2/mac1/p1-07-curl-I.png), [mac1/p1-08-conditional-1](Evidence/phase2/mac1/p1-08-conditional-1.png), [mac4/p1-07-backend-304](Evidence/phase2/mac4/p1-07-backend-304.png), [mac4/p1-09-edge-cache](Evidence/phase2/mac4/p1-09-edge-cache.png) |
| 8 | Fail one backend, service continues | Ext D: [mac1/extD-2-a-down](Evidence/phase2/mac1/extD-2-a-down.png), [mac2/extD-1-error-log](Evidence/phase2/mac2/extD-1-error-log.png), [mac2/extD-2-access-log](Evidence/phase2/mac2/extD-2-access-log.png) |
| 9 | Phase 2 DNS and resilience | Ext A, B, E below |
| 10 | Faculty-injected fault | Live (Ext F). Method: [troubleshooting-runbook.md](scripts/troubleshooting-runbook.md) |
| 11 | Individual viva | Live |

## 3. Phase 2 extensions → evidence

| Ext | What it proves | Evidence |
|---|---|---|
| A — Backup DNS | Primary dnsmasq stopped, clients resolve through the backup on Mac 4, app still works | Backup config/running: [mac4/extA-1](Evidence/phase2/mac4/extA-1-backup-config.png), [mac4/extA-2](Evidence/phase2/mac4/extA-2-backup-running.png), [mac4/extA-3](Evidence/phase2/mac4/extA-3-both-servers.png). Failover from the client: [mac1/extA-1 … extA-7](Evidence/phase2/mac1/extA-4-still-resolves.png) (`extA-3-primary-down`, `extA-4-still-resolves`, `extA-5-app-still-works`, `extA-6-dns-vs-app`) |
| B — TTL and controlled record change | 30 s TTL; client keeps the cached answer, switches after the TTL; manual flush is immediate | [mac1/extB-1 … extB-7](Evidence/phase2/mac1/extB-5-client-new-after-ttl.png), [mac4/extB-1-ttl](Evidence/phase2/mac4/extB-1-ttl.png) |
| C — Service isolation (pf) | Only the edge may reach :3001/:3002 | Partial, not run as a full team section: Mac 4 rules + edge allowed [mac4/extC-2](Evidence/phase2/mac4/extC-2-rules-on.png), [mac4/extC-3](Evidence/phase2/mac4/extC-3-edge-allowed.png), rollback copy `mac4/extC-0-rollback-copy-of-etc-pf.conf`; client refused [mac1/16-extC-mac4-isolated](Evidence/phase2/mac1/16-extC-mac4-isolated.png); edge side [mac2/extC-1](Evidence/phase2/mac2/extC-1-edge-allowed.png). Rules: [Configuration/phase2/pf-isolation-*.conf](Configuration/phase2/) |
| D — HA failover | nginx passive health check; A down → all traffic on B; A back → balancing resumes | [mac1/extD-1](Evidence/phase2/mac1/extD-1-both-up.png), [extD-2](Evidence/phase2/mac1/extD-2-a-down.png), [extD-3](Evidence/phase2/mac1/extD-3-a-back.png); nginx logs [mac2/extD-1](Evidence/phase2/mac2/extD-1-error-log.png), [mac2/extD-2](Evidence/phase2/mac2/extD-2-access-log.png); Mac 3 view [mac3/extD-0](Evidence/phase2/mac3/extD-0-failover-mac3-view.png) |
| E — DNS-based edge migration | Standby nginx on Mac 3; DNS cut over; cached client stays on the old edge until the TTL; fresh client goes to the standby | Standby: [mac3/extE-1](Evidence/phase2/mac3/extE-1-nginx-t.png), [mac3/extE-2](Evidence/phase2/mac3/extE-2-standby-works.png). Client: [mac1/extE-1 … extE-4](Evidence/phase2/mac1/extE-3-after-ttl.png), fresh client [mac4/extE-1](Evidence/phase2/mac4/extE-1-fresh-client.png) |
| F — Troubleshooting challenge | Diagnose a faculty-injected fault layer by layer | Live on demo day; [runbook](scripts/troubleshooting-runbook.md) |

## 4. Phase 1 failure demonstrations (Section 6.3)

[Evidence/09-failure-tests/](Evidence/09-failure-tests/): wrong DNS server, wrong DNS record, one backend down, both backends down (502), wrong destination port. Phase 2 retake of the wrong-DNS case: [mac1/extA-6-dns-vs-app](Evidence/phase2/mac1/extA-6-dns-vs-app.png).
