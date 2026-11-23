#!/bin/bash
# Mac 1: primary DNS + test client.
# Usage: ./scripts/mac1.sh check          preflight only (run this first)
#        ./scripts/mac1.sh <section>      run one section when the run sheet says so (list: ./scripts/mac1.sh list)
#        ./scripts/mac1.sh dns-point <ip> point app/api.team${TEAM}.test at <ip> on this Mac's dnsmasq

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ME="Mac 1 (primary DNS + client)"
EVID_DIR="$REPO/Evidence/phase2/mac1"
SECTIONS=(phase1 extA extB extC extD extE)
CURL="curl --cacert '$CA_FILE'"   # quoted: the CA path may contain spaces
LOOP6="for i in 1 2 3 4 5 6; do $CURL -s -o /dev/null -D - https://$DOMAIN/api/status | grep -i -E '^(HTTP|x-backend)' | tr -d '\r' | paste -sd' ' -; done"

preflight() {
  title "Preflight: $ME"
  check_sudo
  check_repo
  check_ip "$MAC1_IP"
  check_ping "Mac 2" "$MAC2_IP" "Mac 3" "$MAC3_IP" "Mac 4" "$MAC4_IP"
  check_dnsmasq "$PHASE2/dnsmasq-primary.conf" "$MAC1_IP"
  check_remote_dns "Backup (Mac 4)" "$MAC4_IP"
  check_resolvers
  check_ca
  check_edge
  preflight_result
}

sec_phase1() {
  title "Phase 1 re-takes (Task A, B, C, E, F, G)"
  evidence p1-01-network-info "Task A: Mac 1 IP, mask, gateway, interface, MAC" \
    "networksetup -getinfo '$WIFI_SERVICE'; echo; echo 'en0 MAC (on the wire):'; ifconfig en0 | grep ether"
  evidence p1-02-ping "Task A: Mac 1 pings Mac 2, 3, 4" \
    "for ip in $MAC2_IP $MAC3_IP $MAC4_IP; do ping -c 3 \$ip | tail -2; done"
  evidence p1-03-resolver "Task B: Mac 1 uses the team DNS servers" \
    "networksetup -getdnsservers '$WIFI_SERVICE'; scutil --dns | grep nameserver | sort -u"
  evidence p1-04-dig "Task B: client resolves $DOMAIN through the team DNS" "dig $DOMAIN"
  evidence p1-05-load-balancing "Task C/D: X-Backend alternates A/B (by name, no IP, no -k)" "$LOOP6"
  evidence p1-06-tls "Task E: certificate verified by our CA, TLS version, no -k" \
    "$CURL -v -o /dev/null https://$DOMAIN/ 2>&1 | grep -E 'Connected to|SSL connection|ALPN|subject:|issuer:|subjectAltName|verify|HTTP/'"
  evidence p1-07-curl-I "Task F: response headers (Cache-Control, ETag)" "$CURL -I https://$DOMAIN/api/status"
  local i
  # Round-robin alternates A/B, so the conditional request is sent TWICE: one copy reaches the
  # backend that issued the ETag (304 Not Modified), the other reaches the other backend (200, its own ETag).
  for i in 1 2; do
    evidence "p1-08-conditional-$i" "Task F: conditional requests #$i: 304 from the backend that issued the ETag, 200 from the other one" \
      "H=\$($CURL -sI https://$DOMAIN/api/status | tr -d '\r'); ET=\$(echo \"\$H\" | awk 'tolower(\$1)==\"etag:\"{print \$2}'); echo \"First request: \$(echo \"\$H\" | grep -i '^x-backend') -> ETag \$ET\"; for n in 1 2; do echo; echo \"Conditional request \$n (If-None-Match: \$ET):\"; $CURL -si -H \"If-None-Match: \$ET\" https://$DOMAIN/api/status | grep -i -E '^(HTTP|x-backend|etag|cache-control)' | tr -d '\r'; done"
  done

  title "Task G: packet capture of one full request (DNS + TCP + TLS)"
  local pcap="$EVID_DIR/p1-09-full-request.pcap"
  mkdir -p "$EVID_DIR"
  # Mac 1 is its own primary DNS, so its lookups go over loopback, not Wi-Fi. To get the DNS
  # query/response on the wire, the lookup is sent to the team's backup DNS (Mac 4) over Wi-Fi.
  # Only team traffic is captured (no background iCloud/8.8.8.8 lookups).
  sudo tcpdump -i en0 -U -w "$pcap" "(host $MAC4_IP and udp port 53) or (host $MAC2_IP and tcp port 443)" 2>/dev/null &
  local tpid=$!
  sleep 2; flush_dns_cache
  dig @"$MAC4_IP" "$DOMAIN" +short >/dev/null
  curl --cacert "$CA_FILE" -s -o /dev/null "https://$DOMAIN/api/status"
  sleep 2; sudo kill -INT "$tpid" 2>/dev/null; wait "$tpid" 2>/dev/null
  sudo chown "$USER" "$pcap"
  evidence p1-09-full-request "Task G: DNS query/response (UDP 53, to the team DNS on Mac 4), TCP 3-way handshake + TLS + encrypted data (TCP 443, to the edge). Open the .pcap in Wireshark for the TLS ClientHello/ServerHello." \
    "tcpdump -nn -r '$pcap' 2>/dev/null | head -40"
}

sec_extA() {
  title "Extension A: backup DNS"
  evidence extA-1-resolvers "Client lists primary and backup DNS" "scutil --dns | grep nameserver | sort -u"
  evidence extA-2-backup-alone "Backup DNS (Mac 4) answers on its own" "dig @$MAC4_IP $DOMAIN +noall +answer +stats | grep -E 'IN|SERVER'"
  info "Stopping the PRIMARY DNS (dnsmasq on this Mac)…"
  dnsmasq_stop; flush_dns_cache
  evidence extA-3-primary-down "Primary is down: dig to Mac 1 fails" "dig @$MAC1_IP $DOMAIN +time=2 +tries=1 | tail -3"
  evidence extA-4-still-resolves "Primary down, name still resolves via the backup" "dig $DOMAIN +noall +answer +stats | grep -E 'IN|SERVER'"
  evidence extA-5-app-still-works "Primary down, the app still works by name" "$CURL -s -i https://$DOMAIN/api/status | grep -i -E '^(HTTP|x-backend)'"
  evidence extA-6-dns-vs-app "Contrast: wrong DNS server = name lookup fails although IP connectivity works" \
    "dig @8.8.8.8 $DOMAIN +short +time=2 | head -1; echo '(empty = NXDOMAIN)'; ping -c 2 $MAC2_IP | tail -1"
  info "Starting the primary DNS again…"
  dnsmasq_start
  evidence extA-7-primary-back "Primary is back" "dig @$MAC1_IP $DOMAIN +short"
}

sec_extB() {
  title "Extension B: TTL and a controlled record change"
  # What each DNS server answers, and what THIS client (macOS resolver cache) currently uses
  local SERVERS="echo \"primary DNS (Mac 1): \$(dig @$MAC1_IP $DOMAIN +short)\"; echo \"backup  DNS (Mac 4): \$(dig @$MAC4_IP $DOMAIN +short)\""
  local CLIENT="echo \"client (dscacheutil): \$(dscacheutil -q host -a name $DOMAIN | awk '/ip_address/{print \$2}')\"; echo \"client (ping):       \$(ping -c 1 -t 1 $DOMAIN 2>/dev/null | head -1 | sed 's/.*(\\(.*\\)).*/\\1/')\""
  client_ip() { ping -c 1 -t 1 "$DOMAIN" 2>/dev/null | head -1 | sed 's/.*(\(.*\)).*/\1/'; }
  # wait_for_client <ip> <max-seconds>: poll the client every 5 s; prints seconds waited, returns 1 on timeout
  wait_for_client() {
    local t=0
    while [[ $(client_ip) != "$1" ]]; do
      ((t >= $2)) && { echo "$t"; return 1; }
      printf "\r  ${Y}⏳${N} client still on %s after %3ds (TTL is 30 s)… " "$(client_ip)" "$t" >&2; sleep 5; t=$((t + 5))
    done; printf "\r%60s\r" "" >&2; echo "$t"
  }
  backup_to() {  # make sure Mac 4's backup answers <ip> before continuing
    until [[ $(dig_a "$MAC4_IP") == "$1" ]]; do
      pause "Mac 4: run  ./scripts/mac4.sh dns-point $1   (backup now answers '$(dig_a "$MAC4_IP")')"
    done; ok "backup DNS (Mac 4) answers $1"
  }

  evidence extB-1-ttl "Record TTL is now 30 s (was 0 in Phase 1)" "dig $DOMAIN +noall +answer"

  # --- Part 1: the client keeps its cached answer until it expires ---
  backup_to "$MAC3_IP"
  flush_dns_cache
  evidence extB-2-client-caches "Client resolves and caches the CURRENT answer" "$SERVERS; $CLIENT"
  local t0=$SECONDS
  info "Changing the record on this Mac (primary) to ${MAC3_IP}…"
  dns_point "$MAC3_IP"
  evidence extB-3-server-new "Both DNS servers now give the NEW answer" "$SERVERS"
  evidence extB-4-client-still-old "…but the client still uses its CACHED old answer" "$CLIENT"
  local waited
  if waited=$(wait_for_client "$MAC3_IP" 90); then
    evidence extB-5-client-new-after-ttl "Client switched to the new answer about $((SECONDS - t0)) s after caching it (record TTL 30 s)" "$SERVERS; $CLIENT"
  else
    evidence extB-5-client-new-after-ttl "Client was STILL on its cached answer $((SECONDS - t0)) s after caching it: macOS kept the entry longer than the 30 s TTL" "$SERVERS; $CLIENT"
    flush_dns_cache
    evidence extB-5b-flush "Manual cache flush: the client picks up the new answer immediately" \
      "echo '(ran: sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder)'; $CLIENT"
  fi

  # --- Part 2: put the record back, then show that a flush makes the change visible at once ---
  backup_to "$MAC2_IP"
  info "Reverting the record on this Mac to the edge ($MAC2_IP)…"
  dns_point "$MAC2_IP"
  evidence extB-6-client-cached-again "Both servers reverted; the client still has the now-outdated cached answer" "$SERVERS; $CLIENT"
  flush_dns_cache
  evidence extB-7-after-flush "Manual cache flush: the change is visible immediately" \
    "echo '(ran: sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder)'; $CLIENT"
}

sec_extC() {
  title "Extension C: service isolation (client side)"
  pause "Mac 3 and Mac 4: run your extC section and wait until it says the rules are ON"
  evidence extC-1-client-blocked "Client can NOT reach the backends directly" \
    "curl -s -i --max-time 5 http://$MAC3_IP:3001/api/status || echo '-> blocked'; curl -s -i --max-time 5 http://$MAC4_IP:3002/api/status || echo '-> blocked'"
  evidence extC-2-edge-path-works "…but the service still works through the edge" "$LOOP6"
  pause "Mac 2: run ./scripts/mac2.sh extC now. Then Mac 3 and Mac 4 press Enter to roll back"
  pause "Wait until Mac 3 and Mac 4 say the rules are rolled back"
  evidence extC-3-after-rollback "After rollback, direct access works again" \
    "curl -s -i --max-time 5 http://$MAC3_IP:3001/api/status | head -1; curl -s -i --max-time 5 http://$MAC4_IP:3002/api/status | head -1"
}

sec_extD() {
  title "Extension D: HA failover"
  evidence extD-1-both-up "Both backends up: A and B alternate" "$LOOP6"
  pause "Mac 3: STOP Backend A (Ctrl+C in its Terminal)"
  evidence extD-2-a-down "Backend A down: every request still succeeds via B" "$LOOP6"
  pause "Mac 3: START Backend A again (python3 backends/backend-a/server.py)"
  countdown 12 "waiting for nginx's fail_timeout (10 s) to retry Backend A"
  evidence extD-3-a-back "Backend A back: balancing resumes" "$LOOP6"
}

sec_extE() {
  title "Extension E: DNS-based edge migration (this Mac = client with a cached answer)"
  pause "Mac 3: run ./scripts/mac3.sh extE and wait until the standby edge is up"
  flush_dns_cache
  evidence extE-1-old-edge "Before the cutover: served by the old edge" "$CURL -sI https://$DOMAIN/api/status | grep -i -E '^(HTTP|x-edge|x-backend)'"
  info "Cutting DNS over to the standby edge ($MAC3_IP) on this Mac…"
  dns_point "$MAC3_IP"
  evidence extE-2-cached-client "Right after the cutover: THIS client still hits the old edge (cached DNS answer)" \
    "$CURL -sI https://$DOMAIN/api/status | grep -i -E '^(HTTP|x-edge)'; dscacheutil -q host -a name $DOMAIN | grep ip_address"
  pause "Mac 4: run  ./scripts/mac4.sh extE  (the fresh client)"
  countdown 32 "waiting for this Mac's cached answer to expire"
  evidence extE-3-after-ttl "After the TTL: this client also moves to the standby edge" \
    "$CURL -sI https://$DOMAIN/api/status | grep -i -E '^(HTTP|x-edge)'"
  info "Cutting back to the main edge ($MAC2_IP)…"
  dns_point "$MAC2_IP"; flush_dns_cache
  pause "Mac 4: run  ./scripts/mac4.sh dns-point $MAC2_IP   and Mac 3: press Enter to stop the standby edge"
  evidence extE-4-cut-back "Cut back to the main edge" "$CURL -sI https://$DOMAIN/api/status | grep -i -E '^(HTTP|x-edge)'"
}

if [[ ${1:-} == dns-point ]]; then
  [[ -n ${2:-} ]] || { echo "Usage: $0 dns-point <ip>"; exit 1; }
  sudo -v && dns_point "$2"; exit
fi
run_sections "${1:-check}"
