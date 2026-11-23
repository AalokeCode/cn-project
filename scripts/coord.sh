#!/bin/bash
# Client for the team coordination board on Mac 2 (scripts/coord-server.py, port 8099).
# Set who you are once per shell:  export COORD_ME=mac3
#
#   ./scripts/coord.sh send <mac1|mac2|mac3|mac4|all> "<text>"   post a message
#   ./scripts/coord.sh read                                       new messages for me since last read
#   ./scripts/coord.sh wait [seconds]                             block until a new message for me arrives (default 600 s)
#   ./scripts/coord.sh board                                      the whole conversation
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/scripts/team.env"
URL="http://$MAC2_IP:8099"
ME="${COORD_ME:?set COORD_ME=mac1|mac2|mac3|mac4 first}"
STATE="$REPO/coord/.last-$ME"
mkdir -p "$REPO/coord"
last() { cat "$STATE" 2>/dev/null || echo 0; }

fetch() {  # print messages after $(last) not sent by me; update the marker; return 1 if none
  local json
  json=$(curl -s --max-time 5 "$URL/read?me=$ME&since=$(last)") || { echo "board unreachable at $URL" >&2; return 2; }
  python3 -I -c '
import json, sys
msgs = json.loads(sys.argv[1]); me = sys.argv[2]; state = sys.argv[3]
if msgs:
    open(state, "w").write(str(msgs[-1]["id"]))
new = [m for m in msgs if m["from"] != me]
for m in new:
    print("#%(id)s %(time)s %(from)s -> %(to)s: %(text)s" % m)
sys.exit(0 if new else 1)
' "$json" "$ME" "$STATE"
}

case "${1:-}" in
  send)
    [[ $# -ge 3 ]] || { echo "usage: $0 send <to> <text>"; exit 1; }
    body=$(python3 -I -c 'import json,sys; print(json.dumps({"from":sys.argv[1],"to":sys.argv[2],"text":sys.argv[3]}))' "$ME" "$2" "$3")
    curl -s --max-time 5 -H 'Content-Type: application/json' -d "$body" "$URL/send"; echo ;;
  read)  fetch || echo "(no new messages)" ;;
  wait)
    end=$(( $(date +%s) + ${2:-600} ))
    while (( $(date +%s) < end )); do fetch && exit 0; sleep 3; done
    echo "(no message within ${2:-600} s)"; exit 1 ;;
  board) curl -s --max-time 5 "$URL/board" ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
