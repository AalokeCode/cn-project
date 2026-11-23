# Phase 1 — Basic Network (Team 1)

## Roles

| Mac | Owner   | Role                     | IP            |
|-----|---------|--------------------------|---------------|
| A   | Krishna | DNS (dnsmasq)            | 10.7.5.108    |
| B   | Aaloke  | Edge / nginx / TLS / LB  | 10.7.20.225   |
| C   | Arina   | Backend A — :3001        | 10.7.13.142   |
| D   | Hemanth | Backend B — :3002        | 10.7.20.219   |

Domain: `app.team1.test` / `api.team1.test` → resolves to Mac B (10.7.20.225)
Public entry point: `https://app.team1.test:8443/api/status`

Full IP table: [`Architecture/ip-table.txt`](Architecture/ip-table.txt)
Topology: [`Architecture/topology.md`](Architecture/topology.md), rendered at [`Architecture/topology-diagram.png`](Architecture/topology-diagram.png)
Request flow: [`Architecture/request-flow.md`](Architecture/request-flow.md), rendered at [`Architecture/request-flow-diagram.png`](Architecture/request-flow-diagram.png)
Backend launch steps: [`Configuration/backend-launch-instructions.md`](Configuration/backend-launch-instructions.md)

## Build order

1. **LAN** — confirm all four Macs on 10.7.0.0/19, `ping` each other.
2. **Mac A: DNS** — deploy `Configuration/dnsmasq.conf`, start dnsmasq, `dig` test.
3. **Mac C: Backend A** — run `Backends/backend-a/server.py`.
4. **Mac D: Backend B** — run `Backends/backend-b/server.py`.
5. **Mac B: nginx** — deploy `Configuration/nginx.conf` (HTTP first), verify round-robin.
6. **Mac B: TLS** — generate cert with mkcert, switch nginx to `listen 8443 ssl`, distribute `rootCA.pem` to Mac C/D, trust it (`security add-trusted-cert`).
7. **Mac C/D: DNS client** — `sudo networksetup -setdnsservers Wi-Fi 10.7.5.108`.
8. **Caching** — verify `Cache-Control: max-age=60` header via `curl -I`.
9. **Wireshark** — capture one full request from a client Mac; identify DNS, TCP handshake, TLS handshake, encrypted HTTP.
10. **Failure demos** — wrong DNS server, wrong DNS record, one backend down, both backends down.

See [`Configuration/TLS-notes.txt`](Configuration/TLS-notes.txt) for cert generation/trust steps in detail.

## Verification commands (run from Mac C or Mac D)

```bash
# DNS
dig app.team1.test
# expect: app.team1.test. A 10.7.20.225

# HTTPS + backend identity
curl -v https://app.team1.test:8443/api/status

# Load balancing (round robin across A/B)
for i in {1..10}; do
    curl -s -D - https://app.team1.test:8443/api/status -o /dev/null | grep X-Backend
done

# Cache header
curl -I https://app.team1.test:8443/api/status
```

`curl -k` must never be used in the final demo — Mac C/D must trust the mkcert root CA.

## Evidence checklist

Screenshots/captures go in `Evidence/`, numbered to match the Final
Demonstration Sequence steps in the project doc (01-ping, 02-dns,
03-backend-a-and-b, 04-https, 05-load-balancing, 06-dns-wireshark,
07-wireshark-tcp-tls-NOT-CAPTURED, 08-http-cache, 09-failure-tests/).

Full status of what's captured and what's not: [`Evidence/README.md`](Evidence/README.md).

## Submission deliverables status

| Deliverable | Status |
|---|---|
| Architecture document (topology, IP table, request flow) | Done, all three now have rendered diagram images |
| Configuration bundle (dnsmasq, nginx, TLS, launch instructions) | Done for Phase 1. Phase 2 configs in [`Configuration/phase2/`](Configuration/phase2/) |
| Backend source code | Done. Zipped at [`_submission/Backend-Source-Code.zip`](_submission/Backend-Source-Code.zip) |
| Evidence folder | Done except TCP and TLS Wireshark handshake captures, confirmed unrecoverable, see `Evidence/README.md` |
| Phase 1 checkpoint (live system) | Not yet, the topology needs to be rebuilt before the actual review |
| Phase 2 final report | Not started, not due until Phase 2 |
| Final presentation | Not started, not due until final evaluation |

## Phase 2 (Team 1)

IPs changed after Phase 1 (DHCP). Current values live in [`scripts/team.env`](scripts/team.env):

| Mac | Owner   | Role                                   | IP           |
|-----|---------|----------------------------------------|--------------|
| 1   | Krishna | Primary DNS (dnsmasq) + test client    | 10.7.5.108   |
| 2   | Aaloke  | Edge nginx: TLS :443, HTTP/2, LB       | 10.7.22.206  |
| 3   | Arina   | Backend A :3001 + standby edge (Ext E) | 10.7.17.193  |
| 4   | Hemanth | Backend B :3002 + backup DNS (Ext A)   | 10.7.2.47    |

Entry point: `https://app.team1.test/api/status` (port 443, HTTP/2).

- Configs: [`Configuration/phase2/`](Configuration/phase2/) (nginx with failover, primary/backup dnsmasq, pf isolation rules)
- Backends: [`Backends/`](Backends/) now send `ETag`, answer `304` and `HEAD`
- Scripts + run sheet: [`scripts/README.md`](scripts/README.md); Ext F practice: [`scripts/troubleshooting-runbook.md`](scripts/troubleshooting-runbook.md)
- Team CA (public cert only): [`tls/rootCA.pem`](tls/rootCA.pem). Never commit `*-key.pem`.
- Evidence: [`Evidence/phase2/mac1/`](Evidence/phase2/mac1/README.md) (DNS), [`Evidence/phase2/mac2/`](Evidence/phase2/mac2/README.md) (edge)
