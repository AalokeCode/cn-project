# Phase 2 evidence — Mac 3 (Backend A :3001 + standby edge, Arina, 10.7.17.193)

Each item has a `.txt` with the real command output (machine, IP, timestamp, command) saved by
`./scripts/mac3.sh phase1`, and a `.png` rendered from it with `./scripts/evidence-to-png.sh Evidence/phase2/mac3`.

| File | Requirement | Shows |
|---|---|---|
| p1-01-network-info | Task A | Mac 3 IP 10.7.17.193, mask 255.255.224.0, gateway 10.7.0.1, en0 MAC |
| p1-02-ping | Task A | Mac 3 → Mac 1/2/4, 0% loss |
| p1-03-resolver | Task B, Ext A | Mac 3 uses the team DNS: 10.7.5.108 (primary), then 10.7.2.47 (backup) |
| p1-04-dig | Task B | `dig app.team1.test` → 10.7.22.206 (Mac 2), TTL 30, answered by 10.7.5.108 |
| p1-05-backend | Task C, F | Backend A listening on `*:3001`, `/` and `/api/status` both answer with `X-Backend: A`, `Cache-Control: max-age=60` and `ETag` |
| extD-0-failover-mac3-view | Ext D | Seen from Mac 3 through the edge: A/B round robin → Backend A stopped, all 6 requests served by B with no errors → A restarted, balancing resumes after nginx's `fail_timeout`. Captured before the kit was pulled, so it uses a small start/stop helper instead of Ctrl+C, and `--resolve` instead of the team DNS. Mac 1's `extD` is the official capture. |
| extE-1-nginx-t | Ext E | Standby edge on Mac 3: the same `nginx-phase2.conf` as Mac 2 (only `X-Edge` differs) passes `nginx -t` |
| extE-2-standby-works | Ext E | Standby edge serves the app before any DNS change: `HTTP/2 200`, `x-edge: mac3`, verified with `--cacert` against the team CA |


## Skipped
- `extC` (pf isolation): not evaluated this round, so it was not run.

## Notes
- Ext E run: standby started 19:27, kept up while Mac 1 and Mac 4 did the DNS cutover, stopped on mac2's go at about 19:33. The script then restored the original `nginx.conf`, and port 443 on Mac 3 was confirmed closed.
- Ext D run: Backend A stopped with Ctrl+C on mac2's cue at 19:23:05 and restarted at about 19:23:50 (Mac 1's `extD` files are the capture).
