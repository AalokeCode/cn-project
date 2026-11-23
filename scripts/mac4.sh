#!/bin/bash
# Mac 4: Backend B (:3002) + backup DNS (Ext A) + second test client.
# Keep Backend B running in its own Terminal:  python3 backends/backend-b/server.py
# Usage: ./scripts/mac4.sh check          preflight only (run this first)
#        ./scripts/mac4.sh <section>      run one section when the run sheet says so (list: ./scripts/mac4.sh list)
#        ./scripts/mac4.sh dns-point <ip> point app/api.team${TEAM}.test at <ip> on this Mac's (backup) dnsmasq

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ME="Mac 4 (Backend B + backup DNS + client)"
EVID_DIR="$REPO/Evidence/phase2/mac4"
SECTIONS=(phase1 extA extC extE)
PORT=3002
PF_RULES="$PHASE2/pf-isolation-mac4.conf"
CURL="curl --cacert '$CA_FILE'"   # quoted: the CA path may contain spaces

preflight() {
  title "Preflight: $ME"
  check_sudo
  check_repo
  check_ip "$MAC4_IP"
  check_ping "Mac 1" "$MAC1_IP" "Mac 2" "$MAC2_IP" "Mac 3" "$MAC3_IP"
  check_local_backend "$PORT" B "backends/backend-b/server.py"
  check_dnsmasq "$PHASE2/dnsmasq-backup.conf" "$MAC4_IP"
  check_remote_dns "Primary (Mac 1)" "$MAC1_IP"
  check_resolvers
  check_ca
  preflight_result
}

sec_phase1() {
  title "Phase 1 re-takes (Task A, B, C), Mac 4 as the second client"
  evidence p1-01-network-info "Task A: Mac 4 IP, mask, gateway, interface, MAC" \
    "networksetup -getinfo '$WIFI_SERVICE'; echo; echo 'en0 MAC (on the wire):'; ifconfig en0 | grep ether"
  evidence p1-02-ping "Task A: Mac 4 pings Mac 1, 2, 3" \
    "for ip in $MAC1_IP $MAC2_IP $MAC3_IP; do ping -c 3 \$ip | tail -2; done"
  evidence p1-03-resolver "Task B: Mac 4 (second client) uses the team DNS" \
    "networksetup -getdnsservers '$WIFI_SERVICE'; scutil --dns | grep nameserver | sort -u"
  evidence p1-04-dig "Task B: Mac 4 resolves $DOMAIN through the team DNS" "dig $DOMAIN"
  evidence p1-05-https-by-name "Task E: second client opens the app by name over HTTPS, no -k" \
    "$CURL -s -i https://$DOMAIN/api/status | grep -i -E '^(HTTP|x-backend|cache-control|etag)'"
  evidence p1-06-backend "Task C: Backend B listens on all interfaces and answers both endpoints" \
    "lsof -nP -iTCP:$PORT -sTCP:LISTEN; curl -s -i http://$MAC4_IP:$PORT/; echo; curl -s -i http://$MAC4_IP:$PORT/api/status"
}

sec_extA() {
  title "Extension A: this Mac is the backup DNS"
  evidence extA-1-backup-config "Backup DNS has the same project records and TTL as the primary" \
    "grep -E '^(listen-address|address|local-ttl)' '$DNSMASQ_CONF'"
  evidence extA-2-backup-running "Backup dnsmasq is running and answering" \
    "pgrep -fl dnsmasq; dig @$MAC4_IP $DOMAIN +noall +answer"
}

sec_extC() {
  title "Extension C: only the edge may reach port $PORT"
  local tmp out token was
  tmp=$(mktemp); render "$PF_RULES" > "$tmp"
  was=$(sudo pfctl -s info 2>/dev/null | head -1)
  evidence extC-1-before "Before: pf status" "sudo pfctl -s info | head -1"
  sudo pfctl -nf "$tmp" || { bad "pf rules failed the syntax check"; rm -f "$tmp"; return; }
  out=$(sudo pfctl -f "$tmp" -E 2>&1); token=$(sed -n 's/^Token : //p' <<<"$out")
  rm -f "$tmp"
  evidence extC-2-rules-on "Rules loaded: only $MAC2_IP may connect to port $PORT" "sudo pfctl -sr | grep -E 'port = $PORT'"
  echo; echo "  ${G}${B}Rules are ON.${N} Tell Mac 1 and Mac 2 to run their extC tests."
  pause "Press Enter ONLY after Mac 1 and Mac 2 have finished, to ROLL BACK"
  sudo pfctl -f /etc/pf.conf 2>/dev/null
  [[ -n $token ]] && sudo pfctl -X "$token" >/dev/null 2>&1
  evidence extC-3-rolled-back "Rollback: macOS default rules restored (pf was: $was)" \
    "sudo pfctl -s info | head -1; echo 'project rules left:'; sudo pfctl -sr 2>/dev/null | grep -c 'port = $PORT'"
  echo "  ${G}${B}Rolled back.${N} Tell Mac 1 to press Enter."
}

sec_extE() {
  title "Extension E: this Mac = a FRESH client during the cutover"
  info "Run this when Mac 1's script asks for it (after the DNS cutover)."
  info "Updating the backup DNS too, so both DNS servers agree…"
  dns_point "$MAC3_IP"
  flush_dns_cache
  evidence extE-1-fresh-client "Fresh client (no cached answer) goes straight to the standby edge" \
    "dscacheutil -q host -a name $DOMAIN | grep ip_address; $CURL -sI https://$DOMAIN/api/status | grep -i -E '^(HTTP|x-edge)'"
  echo; echo "  ${G}${B}Done.${N} Tell Mac 1 to continue. When Mac 1 asks, run:  ./scripts/mac4.sh dns-point $MAC2_IP"
}

if [[ ${1:-} == dns-point ]]; then
  [[ -n ${2:-} ]] || { echo "Usage: $0 dns-point <ip>"; exit 1; }
  sudo -v && dns_point "$2"; exit
fi
run_sections "${1:-check}"
