# Phase 2 Architecture (Team 1)

Same LAN as Phase 1 (10.7.0.0/19, mask 255.255.224.0, gateway 10.7.0.1). IPs changed through DHCP; the single source of truth is [`scripts/team.env`](../scripts/team.env).

## IP / service table

| Mac | Owner | Services | IP | Ports | Cloud equivalent |
|---|---|---|---|---|---|
| 1 | Krishna | Primary DNS (dnsmasq), test client | 10.7.5.108 | UDP/TCP 53 | Route 53 (primary) |
| 2 | Aaloke | Edge nginx: TLS termination, HTTP/2, round-robin LB, passive health checks | 10.7.22.206 | TCP 443 | ALB / CDN edge |
| 3 | Arina | Backend A (Python), standby edge for Ext E | 10.7.17.193 | TCP 3001 (+443 during Ext E) | App instance A / standby LB |
| 4 | Hemanth | Backend B (Python), backup DNS, test client | 10.7.2.47 | TCP 3002, UDP/TCP 53 | App instance B / secondary DNS |

DNS records (both servers, TTL 30 s): `app.team1.test` and `api.team1.test` → 10.7.22.206.
Clients list the DNS servers in order: 10.7.5.108 (primary), 10.7.2.47 (backup).

## Topology

```
                      SAME PRIVATE LAN 10.7.0.0/19 (gw 10.7.0.1)

  Mac 1 Krishna              Mac 4 Hemanth
  primary DNS :53            backup DNS :53 + Backend B :3002
  10.7.5.108                 10.7.2.47
       \   DNS (UDP 53)        /
        \                     /
         Client (Mac 1 / Mac 4)
                  |
                  | HTTPS TCP 443 (TLS 1.3, HTTP/2)
                  v
        Mac 2 Aaloke — edge nginx 10.7.22.206
        upstream backend_cluster (round-robin, max_fails=1 fail_timeout=10s)
              |                               |
              | HTTP :3001                    | HTTP :3002
              v                               v
   Mac 3 Arina — Backend A           Mac 4 Hemanth — Backend B
   10.7.17.193                       10.7.2.47
   (+ standby edge :443 in Ext E)
```

## Request flow (one client request)

1. **DNS (Application over UDP 53):** client asks 10.7.5.108 for `app.team1.test` → A 10.7.22.206, TTL 30. If the primary does not answer, the client retries the backup 10.7.2.47 (Ext A).
2. **TCP (Transport):** client ephemeral port → 10.7.22.206:443, SYN → SYN-ACK → ACK.
3. **TLS (Session):** ClientHello (SNI `app.team1.test`, ALPN h2) → ServerHello + certificate signed by the team mkcert CA → key exchange → Finished. Clients verify with `--cacert tls/rootCA.pem`, never `-k`.
4. **HTTP/2 (Application):** `GET /api/status` inside the encrypted stream.
5. **Load balancing:** nginx picks the next upstream (A, B, A, …) and proxies plain HTTP to :3001 or :3002. If the connect fails, nginx marks that backend down for 10 s and retries the same request on the other one (`proxy_next_upstream error timeout http_502 http_503 http_504`, `proxy_connect_timeout 2s`).
6. **Response:** backend returns JSON with `X-Backend: A|B` and an `ETag`; nginx adds `Cache-Control: max-age=60` and `X-Edge: mac2`. A repeat request with `If-None-Match` gets `304 Not Modified` from the backend that issued the ETag.

## What changed from Phase 1

| Area | Phase 1 | Phase 2 |
|---|---|---|
| Edge port | 8443 | 443, HTTP/2 on |
| Upstream | plain round-robin | + `max_fails=1 fail_timeout=10s`, `proxy_next_upstream`, `proxy_connect_timeout 2s` |
| DNS | one dnsmasq, TTL 0 | primary + backup dnsmasq, TTL 30 s |
| Backends | JSON + `X-Backend` | + `ETag`, `304`, `HEAD` |
| Headers | — | `X-Edge` (which edge served), single `Cache-Control` |
| Isolation | none | pf rules allowing only the edge to reach :3001/:3002 (Ext C) |
| Edge redundancy | none | standby nginx on Mac 3, DNS cutover (Ext E) |

## Single point of failure

The edge nginx on Mac 2 is still a single point of failure for clients that already cached its IP: if Mac 2 dies, requests fail until DNS is moved (Ext E) and the TTL runs out. Removing it needs two edges active at the same time behind a floating virtual IP (VRRP/keepalived) or an anycast/managed load balancer, plus health-checked DNS that withdraws a dead edge automatically.
