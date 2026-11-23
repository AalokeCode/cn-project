#!/bin/bash
# Mac 2: edge nginx (TLS termination + load balancer).
# Usage: ./scripts/mac2.sh check          preflight only (run this first)
#        ./scripts/mac2.sh <section>      run one section when the run sheet says so (list: ./scripts/mac2.sh list)

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ME="Mac 2 (edge nginx)"
EVID_DIR="$REPO/Evidence/phase2/mac2"
SECTIONS=(phase1 extC extD)

# On Mac 2 the CA lives in mkcert's own folder
if command -v mkcert >/dev/null 2>&1 && [[ -f "$(mkcert -CAROOT)/rootCA.pem" ]]; then CA_FILE="$(mkcert -CAROOT)/rootCA.pem"; fi
CURL="curl --cacert '$CA_FILE' --resolve $DOMAIN:443:127.0.0.1"   # quoted: mkcert's folder is "Application Support"

# Mac 2 only: clear stray keystrokes (e.g. the Enter after the password) before every y/N question
ask() { local a; while read -r -t 1 -n 1000 _; do :; done; read -r -p "  ${Y}?${N} $* [y/N] " a; [[ $a == [yY]* ]]; }

listeners_443() { sudo lsof -t -nP -iTCP:443 -sTCP:LISTEN 2>/dev/null | sort -u; }

# Stop whatever is listening on TCP 443 so nginx can start cleanly with the Phase 2 config.
free_port_443() {
  # nginx kept alive by 'brew services' would be restarted by launchd after a kill: stop the service first
  if sudo launchctl list 2>/dev/null | grep -qE "homebrew.mxcl.nginx|sh.brew.nginx" || launchctl list 2>/dev/null | grep -qE "homebrew.mxcl.nginx|sh.brew.nginx"; then
    info "nginx is managed by 'brew services': stopping that service"
    sudo brew services stop nginx >/dev/null 2>&1; brew services stop nginx >/dev/null 2>&1; sleep 1
  fi
  [[ -z $(listeners_443) ]] && return 0
  info "port 443 is in use by:"
  sudo lsof -nP -iTCP:443 -sTCP:LISTEN | awk 'NR > 1 {print "      " $1 " (PID " $2 ", user " $3 ")"}' | sort -u
  sudo nginx -s stop 2>/dev/null; sleep 1                           # graceful stop if it is our nginx
  local pids; pids=$(listeners_443)
  if [[ -n $pids ]]; then info "killing PID(s): $(echo $pids)"; sudo kill $pids 2>/dev/null; sleep 2; fi
  pids=$(listeners_443)
  if [[ -n $pids ]]; then sudo kill -9 $pids 2>/dev/null; sleep 1; fi
  if [[ -z $(listeners_443) ]]; then ok "port 443 is free"
  else bad "could not free port 443 (still used by PID $(echo $(listeners_443)))"; return 1; fi
}

check_nginx() {
  if ! command -v nginx >/dev/null 2>&1; then bad "nginx not installed: brew install nginx"; return; fi
  local f
  for f in "$CERT_DIR/app.team${TEAM}.test.pem" "$CERT_DIR/app.team${TEAM}.test-key.pem"; do
    [[ -f $f ]] && ok "found $(basename "$f")" || bad "missing $f (see "Certificates" in the kit README.md)"
  done
  local tmp; tmp=$(mktemp); render "$PHASE2/nginx-phase2.conf" > "$tmp"
  if ! cmp -s "$tmp" "$NGINX_CONF"; then
    echo "  ${R}✘${N} installed nginx.conf is not the Phase 2 version"
    if ask "Install nginx-phase2.conf (with your team.env IPs), test it and reload nginx?"; then
      install_rendered "$tmp" "$NGINX_CONF"
    else bad "nginx.conf not installed (answered no)"; rm -f "$tmp"; return; fi
  fi
  rm -f "$tmp"
  if sudo nginx -t >/dev/null 2>&1; then ok "nginx -t: configuration is valid"
  else bad "nginx -t failed:"; sudo nginx -t; return; fi
  free_port_443 || return
  if sudo nginx; then ok "nginx started fresh with the Phase 2 config"
  else bad "nginx failed to start"; return; fi
  sleep 1
  local code; code=$(curl --cacert "$CA_FILE" --resolve "$DOMAIN:443:127.0.0.1" -s -o /dev/null -w '%{http_code}' --max-time 5 "https://$DOMAIN/api/status")
  [[ $code == 200 ]] && ok "edge answers https://$DOMAIN/ with 200" || bad "edge answers https://$DOMAIN/ with '$code'"
}

check_backend_from_edge() {  # <name> <ip> <port>
  local h; h=$(curl -sI --max-time 3 "http://$2:$3/api/status" 2>/dev/null)
  if [[ -z $h ]]; then bad "$1 ($2:$3) is not reachable from the edge"
  elif grep -qi '^etag' <<<"$h"; then ok "$1 ($2:$3) reachable, running Phase 2 code"
  else bad "$1 ($2:$3) is running OLD code: restart it with the pulled server.py"; fi
}

preflight() {
  title "Preflight: $ME"
  check_sudo
  check_repo
  check_ip "$MAC2_IP"
  check_ping "Mac 1" "$MAC1_IP" "Mac 3" "$MAC3_IP" "Mac 4" "$MAC4_IP"
  check_ca
  check_backend_from_edge "Backend A" "$MAC3_IP" 3001
  check_backend_from_edge "Backend B" "$MAC4_IP" 3002
  check_nginx
  preflight_result
}

sec_phase1() {
  title "Phase 1 re-takes (Task A, D, E)"
  evidence p1-01-network-info "Task A: Mac 2 IP, mask, gateway, interface, MAC" \
    "networksetup -getinfo '$WIFI_SERVICE'; echo; echo 'en0 MAC (on the wire):'; ifconfig en0 | grep ether"
  evidence p1-02-ping "Task A: Mac 2 pings Mac 1, 3, 4" \
    "for ip in $MAC1_IP $MAC3_IP $MAC4_IP; do ping -c 3 \$ip | tail -2; done"
  evidence p1-03-nginx-t "Task D/E: nginx configuration is valid" "sudo nginx -t"
  evidence p1-04-upstream "Task D + Ext D: upstream with failover settings, TLS and HTTP/2" \
    "grep -n -E 'upstream|server [0-9]|listen|http2|ssl_certificate|proxy_next_upstream|proxy_connect_timeout' '$NGINX_CONF'"
  evidence p1-05-listening "Task D: nginx listens on TCP 443" "sudo lsof -nP -iTCP:443 -sTCP:LISTEN"
  evidence p1-06-cert "Task E: the certificate nginx serves" \
    "openssl x509 -in '$CERT_DIR/app.team${TEAM}.test.pem' -noout -subject -issuer -dates -ext subjectAltName"
  evidence p1-07-http2 "HTTP/2 negotiated through ALPN" "$CURL -sI --http2 https://$DOMAIN/ | head -1"
}

sec_extC() {
  title "Extension C: the edge can still reach the backends"
  pause "Wait until Mac 3 and Mac 4 say the firewall rules are ON"
  evidence extC-1-edge-allowed "With pf on, the edge (Mac 2) can still reach both backends directly" \
    "curl -s -i --max-time 5 http://$MAC3_IP:3001/api/status | grep -i -E '^(HTTP|x-backend)'; curl -s -i --max-time 5 http://$MAC4_IP:3002/api/status | grep -i -E '^(HTTP|x-backend)'"
  info "Tell Mac 3 and Mac 4 they can press Enter to roll back."
}

sec_extD() {
  title "Extension D: what nginx logged during the failover"
  info "Run this right after Mac 1's extD section."
  # Only today's requests from Mac 1 (the test client), so older Phase 1 / setup errors don't show up
  local day_err day_acc errs times
  day_err=$(date +%Y/%m/%d); day_acc=$(date +%d/%b/%Y)
  errs="grep -E 'connect\\(\\) failed|upstream|no live' /opt/homebrew/var/log/nginx/error.log | grep '^$day_err' | grep 'client: $MAC1_IP,' | tail -8"
  evidence extD-1-error-log "nginx detected Backend A down and moved to the next upstream (requests from Mac 1, today)" "$errs"
  # The seconds those failures happened, so the access log shows exactly those requests
  times=$(bash -c "$errs" | awk '{print $2}' | sort -u | paste -sd'|' -)
  [[ -z $times ]] && { bad "no failover errors from Mac 1 today: run this right after Mac 1's extD"; return; }
  evidence extD-2-access-log "The same requests still got HTTP 200 for Mac 1 (nginx retried them on Backend B)" \
    "grep -E '^$MAC1_IP .*\\[$day_acc:($times) ' /opt/homebrew/var/log/nginx/access.log"
}

run_sections "${1:-check}"
