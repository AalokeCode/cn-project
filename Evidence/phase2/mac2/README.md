# Phase 2 evidence — Mac 2 (edge nginx: TLS + load balancer, Aaloke, 10.7.22.206)

Each item has a `.txt` with the real command output (machine, IP, timestamp, command) saved by
`./scripts/mac2.sh phase1`, and a `.png` rendered from it with `./scripts/evidence-to-png.sh Evidence/phase2/mac2`.

| File | Requirement | Shows |
|---|---|---|
| p1-01-network-info | Task A | Mac 2 IP 10.7.22.206, mask 255.255.224.0, gateway 10.7.0.1, en0 MAC |
| p1-02-ping | Task A | Mac 2 → Mac 1/3/4, 0% loss |
| p1-03-nginx-t | Task D/E | `nginx -t`: Phase 2 config is valid |
| p1-04-upstream | Task D, Ext D | `upstream backend_cluster` (10.7.17.193:3001, 10.7.2.47:3002, `max_fails=1 fail_timeout=10s`), `listen 443 ssl`, `http2 on`, `proxy_next_upstream` |
| p1-05-listening | Task D | nginx listening on TCP 443 |
| p1-06-cert | Task E | mkcert certificate: SAN `app.team1.test`, `api.team1.test`, issued by the team CA |
| p1-07-http2 | HTTP/2 | `HTTP/2 200` through the edge, verified with `--cacert` (no `-k`) |
| p1-08-load-balancing | Task D | 6 requests alternate `X-Backend: A` / `B`, all `X-Edge: mac2` |
| extC-1-edge-allowed | Ext C | With pf on at Mac 3 and Mac 4, the edge still gets `200` from Backend A :3001 and Backend B :3002 |

Team CA (public cert only) for the other Macs: [`tls/rootCA.pem`](../../../tls/rootCA.pem) → copy to `~/cn-project/tls/rootCA.pem`.

## Still pending (run with the team, per `scripts/README.md`)
- `extD` — right after Mac 1's `extD`: nginx error/access log lines for the Backend A failover.

The scripts now write straight here; after each section rerun `./scripts/evidence-to-png.sh Evidence/phase2/mac2`.
