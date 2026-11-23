#!/bin/bash
# Mac 4 evidence that does not need the other Macs to change anything (no sudo; HTTPS uses the team CA, never -k).
# Usage: ./scripts/mac4-solo.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ME="Mac 4 (Backend B + backup DNS + client)"
EVID_DIR="$REPO/Evidence/phase2/mac4"
PORT=3002
CURL="curl --cacert '$CA_FILE'"

title "Phase 1 re-takes on Mac 4"
evidence p1-01-network-info "Task A: Mac 4 IP, mask, gateway, interface, MAC" \
  "networksetup -getinfo '$WIFI_SERVICE'; echo; echo 'en0 MAC (on the wire):'; ifconfig en0 | grep ether"
evidence p1-02-ping "Task A: Mac 4 pings Mac 1, 2, 3" \
  "for ip in $MAC1_IP $MAC2_IP $MAC3_IP; do ping -c 3 \$ip | tail -2; done"
evidence p1-03-resolver "Task B / Ext A: Mac 4 lists primary (Mac 1) then backup (Mac 4) DNS" \
  "networksetup -getdnsservers '$WIFI_SERVICE'; scutil --dns | grep nameserver | sort -u"
evidence p1-04-dig "Task B: Mac 4 resolves $DOMAIN through the team DNS" "dig $DOMAIN"
evidence p1-05-https-by-name "Task E: Mac 4 opens the app by name over HTTPS, cert verified with the team CA (no -k)" \
  "$CURL -s -i https://$DOMAIN/api/status | grep -i -E '^(HTTP|x-backend|cache-control|etag|server)'; echo; $CURL -s -o /dev/null -w 'TLS verify result: %{ssl_verify_result} (0 = OK), HTTP %{http_version}\\n' https://$DOMAIN/"
evidence p1-08-load-balancing "Task D: repeated requests by name are spread across Backend A and Backend B" \
  "for i in 1 2 3 4 5 6 7 8; do $CURL -sI https://$DOMAIN/api/status | grep -i '^x-backend'; done"
evidence p1-09-edge-cache "Task F: Cache-Control + ETag through the edge, conditional request to the same backend gives 304" \
  "H=\$($CURL -sI https://$DOMAIN/api/status); echo \"\$H\" | grep -i -E '^(HTTP|x-backend|cache-control|etag)'; E=\$(echo \"\$H\" | awk 'tolower(\$1)==\"etag:\"{print \$2}' | tr -d '\\r'); echo; echo \"If-None-Match: \$E  (sent twice: round-robin alternates, each backend has its own ETag)\"; for i in 1 2; do $CURL -sI -H \"If-None-Match: \$E\" https://$DOMAIN/api/status | grep -i -E '^(HTTP|x-backend|etag)'; echo; done"
evidence p1-06-backend "Task C: Backend B listens on all interfaces and answers both endpoints" \
  "lsof -nP -iTCP:$PORT -sTCP:LISTEN; curl -s -i http://$MAC4_IP:$PORT/; echo; echo; curl -s -i http://$MAC4_IP:$PORT/api/status"
evidence p1-07-backend-304 "Task F: Backend B conditional request (ETag -> 304 Not Modified)" \
  "E=\$(curl -sI http://$MAC4_IP:$PORT/api/status | awk 'tolower(\$1)==\"etag:\"{print \$2}' | tr -d '\r'); echo \"ETag = \$E\"; curl -s -i -H \"If-None-Match: \$E\" http://$MAC4_IP:$PORT/api/status"

title "Extension A: this Mac is the backup DNS"
evidence extA-1-backup-config "Backup DNS has the same project records and TTL as the primary" \
  "grep -E '^(listen-address|interface|address|local-ttl|server)' '$DNSMASQ_CONF'"
evidence extA-2-backup-running "Backup dnsmasq is running on $MAC4_IP:53 and answering" \
  "ps -o pid,user,command -p \$(pgrep -x dnsmasq); netstat -an -p udp | grep -E '\\.53 '; dig @$MAC4_IP $DOMAIN +noall +answer; dig @$MAC4_IP api.team$TEAM.test +noall +answer"
evidence extA-3-both-servers "Same answer from primary (Mac 1) and backup (Mac 4)" \
  "for s in $MAC1_IP $MAC4_IP; do echo \"server \$s:\"; dig @\$s $DOMAIN +noall +answer +stats | grep -E 'IN[[:space:]]+A|SERVER|Query time'; done"
evidence extA-4-backup-forwards "Backup DNS still forwards non-project names (clients keep internet)" \
  "dig @$MAC4_IP example.com +short | head -3"

title "Extension B: TTL as served by the backup"
evidence extB-1-ttl "Project record carries the 30 s TTL (local-ttl=30); second query shows the countdown" \
  "dig @$MAC4_IP $DOMAIN +noall +answer; sleep 5; dig $DOMAIN +noall +answer"
