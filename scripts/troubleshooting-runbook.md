# Troubleshooting Runbook (Extension F)

> Replace `<MAC1_IP>` … `<MAC4_IP>` with the IPs from `scripts/team.env`, and `teamX` with `team<TEAM>` if you changed the team letter.

When the faculty injects a fault, go **layer by layer, bottom-up along the request path**, and say each step out loud: what you're checking, what you expected, what you saw. Stop at the first layer that fails. That's where the fault is.

Run everything from a **client Mac** unless stated.

---

## Step 0: Reproduce

```bash
curl -v https://app.teamX.test/api/status
```

The **last line `curl` reaches** already points to a layer:

| curl says | Layer that failed | Go to |
|---|---|---|
| `Could not resolve host` | DNS | Step 1 |
| `Failed to connect ... Connection refused` / `timed out` | TCP (IP/port/firewall/service down) | Step 2 |
| `SSL certificate problem` / `handshake failure` / `no alternative certificate subject name` | TLS | Step 3 |
| `HTTP/2 502` / `503` / `504` / `404` | Application, behind the edge | Step 4 |

---

## Step 1: DNS (Application layer, UDP 53)

```bash
scutil --dns | grep nameserver          # which DNS servers is this Mac using?
dig app.teamX.test                      # through the configured server
dig @<MAC1_IP> app.teamX.test          # ask primary directly
dig @<MAC4_IP> app.teamX.test         # ask backup directly
dscacheutil -q host -a name app.teamX.test   # what the OS cache holds
```

| Symptom | Likely fault | Fix |
|---|---|---|
| `SERVER: 8.8.8.8` / `NXDOMAIN` | Client points at the wrong DNS server | `sudo networksetup -setdnsservers Wi-Fi <MAC1_IP> <MAC4_IP>` |
| Answer is not `<MAC2_IP>` | Wrong `address=` record | Fix the record on **both** DNS Macs, restart dnsmasq, flush the client cache |
| `connection timed out; no servers could be reached` | dnsmasq stopped, or wrong `listen-address` | Mac 1: `pgrep -fl dnsmasq`; `sudo dnsmasq --test`; restart |
| `dig` correct but `dscacheutil` old | Stale client cache | `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder` |

**Proves:** DNS is only a directory. If DNS is broken, `ping <MAC2_IP>` still works.

---

## Step 2: IP and TCP (Network + Transport, TCP 443)

```bash
ping -c 3 <MAC2_IP>                    # IP reachability to the edge
nc -vz <MAC2_IP> 443                   # can a TCP handshake complete on 443?
```

| Symptom | Likely fault | Fix |
|---|---|---|
| ping fails | Wrong Wi-Fi / IP changed / Mac asleep | `ipconfig getifaddr en0` on each Mac; compare with `ip_table.md` |
| ping OK, `nc` refused | nginx stopped or listening on another port | Mac 2: `sudo nginx -t`, `sudo nginx`, `sudo lsof -nP -iTCP:443 -sTCP:LISTEN` |
| ping OK, `nc` times out | Firewall (pf / macOS firewall) dropping | `sudo pfctl -sr`; roll back with `sudo pfctl -f /etc/pf.conf` |
| Client uses wrong port (e.g. 3999) | Wrong destination port | Use 443. **Host reachable but port closed** means IP and port are separate identifiers |

---

## Step 3: TLS (between Transport and Application)

```bash
openssl s_client -connect <MAC2_IP>:443 -servername app.teamX.test </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

| Symptom | Likely fault | Fix |
|---|---|---|
| Name not in SAN | Wrong cert / wrong `server_name` | Mac 2: check `ssl_certificate` paths in `nginx.conf` |
| `unable to get local issuer certificate` | Client doesn't trust our CA | Add `rootCA.pem` to the trust store, or `--cacert rootCA.pem` |
| Dates expired / not yet valid | Clock or certificate dates | Check `date` on both Macs |
| `nginx -t` fails on `ssl_certificate_key` | Key path/permissions wrong | `chmod 600` the key, fix the path |

---

## Step 4: Application (HTTP, edge → backends)

```bash
curl -i https://app.teamX.test/api/status          # status code + X-Backend
# From Mac 2 only (the client may be blocked by pf):
curl -i http://<MAC3_IP>:3001/api/status
curl -i http://<MAC4_IP>:3002/api/status
# Mac 2 logs:
tail -n 20 /opt/homebrew/var/log/nginx/error.log
```

| Symptom | Likely fault | Fix |
|---|---|---|
| `502 Bad Gateway` | Both backends down / wrong IP or port in `upstream` | Start backends; check the `upstream` block; `nginx -t && nginx -s reload` |
| Only one `X-Backend` ever appears | One backend down (failover working) or removed from `upstream` | Start it; check `upstream` |
| `504 Gateway Timeout` | Backend reachable but hanging / pf dropping edge traffic | Check pf on Mac 3/4 allows `<MAC2_IP>` |
| `404` | Wrong path or `location` / `proxy_pass` | Compare with `nginx-phase2.conf` |

---

## Say this when you've found it

> "The fault is at the **___ layer**. We know because ___ worked but ___ failed. We fixed it by ___, and confirmed with ___."
