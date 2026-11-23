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

## Still pending (run with the team, per `scripts/README.md`)
- `extC`: apply the pf rules, wait for Mac 1 and Mac 2 to test, roll back.
- `extE`: standby edge on this Mac. Needs `brew install nginx` and both certificate files from Mac 2's `/opt/homebrew/etc/nginx/certs/`.

The scripts write to `Evidences/phase2/mac3/`; move the new `.txt` files here and rerun `evidence-to-png.sh`.
