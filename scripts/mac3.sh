#!/bin/bash
# Mac 3: Backend A (:3001) + pf isolation + standby edge (Ext E).
# Keep Backend A running in its own Terminal:  python3 backends/backend-a/server.py
# Usage: ./scripts/mac3.sh check          preflight only (run this first)
#        ./scripts/mac3.sh <section>      run one section when the run sheet says so (list: ./scripts/mac3.sh list)

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ME="Mac 3 (Backend A + standby edge)"
EVID_DIR="$REPO/Evidence/phase2/mac3"
SECTIONS=(phase1 extC extE)
PORT=3001
PF_RULES="$PHASE2/pf-isolation-mac3.conf"

preflight() {
  title "Preflight: $ME"
  check_sudo
  check_repo
  check_ip "$MAC3_IP"
  check_ping "Mac 1" "$MAC1_IP" "Mac 2" "$MAC2_IP" "Mac 4" "$MAC4_IP"
  check_local_backend "$PORT" A "backends/backend-a/server.py"
  check_resolvers
  check_ca
  preflight_result
}

sec_phase1() {
  title "Phase 1 re-takes (Task A, B, C)"
  evidence p1-01-network-info "Task A: Mac 3 IP, mask, gateway, interface, MAC" \
    "networksetup -getinfo '$WIFI_SERVICE'; echo; echo 'en0 MAC (on the wire):'; ifconfig en0 | grep ether"
  evidence p1-02-ping "Task A: Mac 3 pings Mac 1, 2, 4" \
    "for ip in $MAC1_IP $MAC2_IP $MAC4_IP; do ping -c 3 \$ip | tail -2; done"
  evidence p1-03-resolver "Task B: Mac 3 is configured to use the team DNS" \
    "networksetup -getdnsservers '$WIFI_SERVICE'; scutil --dns | grep nameserver | sort -u"
  evidence p1-04-dig "Task B: Mac 3 (a client) resolves $DOMAIN through the team DNS" "dig $DOMAIN"
  evidence p1-05-backend "Task C: Backend A listens on all interfaces and answers both endpoints" \
    "lsof -nP -iTCP:$PORT -sTCP:LISTEN; curl -s -i http://$MAC3_IP:$PORT/; echo; curl -s -i http://$MAC3_IP:$PORT/api/status"
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
  title "Extension E: standby edge on this Mac"
  if ! command -v nginx >/dev/null 2>&1; then
    ask "nginx is not installed. Install it with Homebrew now?" && brew install nginx || { bad "nginx needed for Ext E"; return; }
  fi
  local f
  for f in app.team${TEAM}.test.pem app.team${TEAM}.test-key.pem; do
    if [[ ! -f $CERT_DIR/$f ]]; then
      bad "missing $CERT_DIR/$f: copy BOTH certificate files from Mac 2's $CERT_DIR (e.g. AirDrop), then:"
      echo "      sudo mkdir -p $CERT_DIR && sudo cp ~/Downloads/app.team${TEAM}.test*.pem $CERT_DIR/ && sudo chmod 600 $CERT_DIR/app.team${TEAM}.test-key.pem"
      return
    fi
  done
  local tmp; tmp=$(mktemp)
  render "$PHASE2/nginx-phase2.conf" | sed 's/X-Edge "mac2"/X-Edge "mac3"/' > "$tmp"
  install_rendered "$tmp" "$NGINX_CONF"; rm -f "$tmp"
  evidence extE-1-nginx-t "Standby edge: same config as Mac 2 (only X-Edge differs)" "sudo nginx -t"
  if nginx_running; then sudo nginx -s reload; else sudo nginx; fi
  sleep 1
  evidence extE-2-standby-works "Standby edge serves the app (tested before any DNS change)" \
    "curl --cacert '$CA_FILE' -sI --resolve $DOMAIN:443:$MAC3_IP https://$DOMAIN/api/status | grep -i -E '^(HTTP|x-edge|x-backend)'"
  echo; echo "  ${G}${B}Standby edge is UP.${N} Tell Mac 1 to continue."
  pause "Press Enter when Mac 1 says to stop the standby edge"
  sudo nginx -s stop && ok "standby edge stopped"
  if [[ -f $NGINX_CONF.phase1.bak ]]; then sudo cp "$NGINX_CONF.phase1.bak" "$NGINX_CONF" && ok "restored the original nginx.conf"; fi
}

run_sections "${1:-check}"
