#!/bin/bash
# Extension C on Mac 4 alone: load the isolation rules, prove the edge (Mac 2) still gets in,
# show the per-rule counters, then roll back to the macOS default rules.
# The "client is refused" half is shown from Mac 1 / Mac 3 with:  curl -m 3 http://<MAC4_IP>:3002/api/status
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ME="Mac 4 (Backend B + backup DNS + client)"
EVID_DIR="$REPO/Evidence/phase2/mac4"
PORT=3002
check_sudo
tmp=$(mktemp); render "$PHASE2/pf-isolation-mac4.conf" > "$tmp"
mkdir -p "$EVID_DIR"; cp /etc/pf.conf "$EVID_DIR/extC-0-rollback-copy-of-etc-pf.conf"
evidence extC-1-before "Before: pf status (rollback copy of /etc/pf.conf saved as extC-0-rollback-copy-of-etc-pf.conf)" "sudo pfctl -s info 2>/dev/null | head -1"
sudo pfctl -nf "$tmp" || { echo "syntax check failed"; exit 1; }
out=$(sudo pfctl -f "$tmp" -E 2>&1); token=$(sed -n 's/^Token : //p' <<<"$out")
evidence extC-2-rules-on "Rules loaded: only the edge $MAC2_IP may connect to port $PORT, all others get a TCP reset" \
  "sudo pfctl -s info 2>/dev/null | head -1; sudo pfctl -sr 2>/dev/null | grep -E 'port = $PORT'"
info "sending 6 requests through the edge so nginx opens connections to Backend B…"
for i in 1 2 3 4 5 6; do curl -sk -o /dev/null --max-time 5 --resolve "$DOMAIN:443:$MAC2_IP" "https://$DOMAIN/api/status"; done
evidence extC-3-edge-allowed "Edge still reaches Backend B: pf rule counters and live states from $MAC2_IP to :$PORT" \
  "sudo pfctl -vsr 2>/dev/null | grep -A2 -E 'port = $PORT' | grep -E 'port|Packets'; echo; echo 'pf states for port $PORT:'; sudo pfctl -ss 2>/dev/null | grep ':$PORT' | head -6"
pause "Rules are ON. If Mac 1/Mac 3 are testing direct access to $MAC4_IP:$PORT, let them finish, then press Enter to ROLL BACK"
evidence extC-4-blocked-counter "Blocked attempts from non-edge hosts (block rule counter)" \
  "sudo pfctl -vsr 2>/dev/null | grep -A2 -E 'block return.*port = $PORT' | grep -E 'block|Packets'"
sudo pfctl -f /etc/pf.conf 2>/dev/null
[[ -n $token ]] && sudo pfctl -X "$token" >/dev/null 2>&1
evidence extC-5-rolled-back "Rollback: macOS default rules restored, no project rules left" \
  "sudo pfctl -s info 2>/dev/null | head -1; echo -n 'project rules left: '; sudo pfctl -sr 2>/dev/null | grep -c 'port = $PORT'"
rm -f "$tmp"
