#!/bin/bash
# Shared helpers for the Phase 2 evidence scripts (sourced by macN.sh, not run directly).

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=team.env
source "$REPO/scripts/team.env"
PHASE2="$REPO/configuration/phase2"
for v in MAC1_IP MAC2_IP MAC3_IP MAC4_IP TEAM; do
  [[ -n ${!v} ]] || { echo "scripts/team.env: $v is empty. Fill in all four IPs and TEAM first."; exit 1; }
done

B=$'\e[1m'; R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; N=$'\e[0m'
FAILED=0

ok()    { echo "  ${G}✔${N} $*"; }
bad()   { echo "  ${R}✘${N} $*"; FAILED=$((FAILED + 1)); }
info()  { echo "  ${Y}→${N} $*"; }
title() { echo; echo "${B}━━ $* ━━${N}"; }
pause() { echo; read -r -p "${Y}⏸  $*  [press Enter when done]${N} " _; }
ask()   { local a; while read -r -t 1 -n 1000 _; do :; done; read -r -p "  ${Y}?${N} $* [y/N] " a; [[ $a == [yY]* ]]; }

my_ip() { ipconfig getifaddr en0 2>/dev/null; }

# dig_a <server> : the A record for $DOMAIN from <server>, or empty (never error text)
dig_a() { dig @"$1" "$DOMAIN" +short +time=2 +tries=1 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -1; }

# ---------------------------------------------------------------------------
# Evidence: run a command, show it live, and save command + output with a
# header (machine, IP, time) to Evidence/phase2/<mac>/<name>.txt
# Usage: evidence <name> "<description>" "<shell command>"
# ---------------------------------------------------------------------------
evidence() {
  local name=$1 desc=$2 cmd=$3 f="$EVID_DIR/$1.txt"
  mkdir -p "$EVID_DIR"
  {
    echo "# $desc"
    echo "# Machine: $ME ($(hostname -s)), en0 = $(my_ip)"
    echo "# Time:    $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo
    echo "\$ $cmd"
  } > "$f"
  echo; echo "  ${B}\$ $cmd${N}"
  bash -c "$cmd" 2>&1 | tee -a "$f"
  echo "  ${G}saved${N} Evidence/phase2/$(basename "$EVID_DIR")/$name.txt"
}

countdown() {  # countdown <seconds> <message>
  local i
  for ((i = $1; i > 0; i--)); do printf "\r  ${Y}⏳${N} %s: %2ds " "$2" "$i"; sleep 1; done
  printf "\r%60s\r" ""
}

flush_dns_cache() { sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; }

# ---------------------------------------------------------------------------
# Config rendering: the repo configs contain the Phase 1 IPs; replace them
# with the IPs and team letter from team.env (the configs hold @MAC1_IP@ ... @TEAM@ tokens).
# ---------------------------------------------------------------------------
render() {
  sed -e "s/@MAC1_IP@/$MAC1_IP/g; s/@MAC2_IP@/$MAC2_IP/g; s/@MAC3_IP@/$MAC3_IP/g; s/@MAC4_IP@/$MAC4_IP/g; s/@TEAM@/$TEAM/g" "$1"
}

# install_rendered <rendered-file> <destination>: keeps a one-time .phase1.bak of the original
install_rendered() {
  local src=$1 dst=$2
  if [[ -f $dst && ! -f $dst.phase1.bak ]]; then
    sudo cp "$dst" "$dst.phase1.bak" && info "backed up the old config to $dst.phase1.bak"
  fi
  sudo mkdir -p "$(dirname "$dst")"
  sudo cp "$src" "$dst" && ok "installed $(basename "$dst")"
}

# ---------------------------------------------------------------------------
# Preflight checks (each prints ✔ or ✘; ✘ increments FAILED)
# ---------------------------------------------------------------------------
check_sudo() { echo "  This script needs your Mac password for a few steps (sudo)."; sudo -v || exit 1; }

check_repo() {
  # Only warns if your branch is behind its GitHub copy; works on any branch.
  local up behind
  up=$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || { info "no upstream branch: skipping the update check"; return; }
  if ! git -C "$REPO" fetch -q 2>/dev/null; then bad "could not reach GitHub to check for updates"; return; fi
  behind=$(git -C "$REPO" rev-list --count "HEAD..$up" 2>/dev/null || echo "?")
  if [[ $behind == 0 ]]; then ok "repo is up to date with $up"
  else bad "repo is $behind commit(s) behind $up: run ${B}git pull${N} and start this script again"; fi
}

check_ip() {
  local have; have=$(my_ip)
  if [[ $have == "$1" ]]; then ok "this Mac's IP is $1 (matches team.env)"
  else bad "this Mac's IP is '${have:-none}' but team.env says $1: update scripts/team.env, push, and everyone pulls"; fi
}

check_ping() {  # check_ping <name> <ip> ...
  while (($#)); do
    if ping -c 1 -t 2 "$2" >/dev/null 2>&1; then ok "can reach $1 ($2)"
    else bad "cannot ping $1 ($2): is it on the same Wi-Fi and awake?"; fi
    shift 2
  done
}

check_cmd() {  # check_cmd <command> <install hint>
  if command -v "$1" >/dev/null 2>&1 || [[ -x $1 ]]; then ok "$(basename "$1") is installed"
  else bad "$(basename "$1") is not installed: $2"; fi
}

check_ca() {
  if [[ -f $CA_FILE ]]; then ok "team CA certificate found ($CA_FILE)"
  else bad "team CA not found at $CA_FILE: copy rootCA.pem from Mac 2 (folder shown by 'mkcert -CAROOT' on Mac 2) to that path"; fi
}

# Client DNS: both team DNS servers, primary first. Offers to fix.
check_resolvers() {
  local want="$MAC1_IP $MAC4_IP" have
  have=$(networksetup -getdnsservers "$WIFI_SERVICE" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')
  if [[ $have == "$want" ]]; then ok "DNS servers are $want (primary, backup)"; return; fi
  echo "  ${R}✘${N} DNS servers are '${have}', should be '$want'"
  if [[ -z $(dig_a "$MAC1_IP") && -z $(dig_a "$MAC4_IP") ]]; then
    bad "not switching DNS servers: neither team DNS server answers yet (this Mac would lose all name lookups)"; return
  fi
  if ask "Set this Mac's DNS servers to $want now?"; then
    sudo networksetup -setdnsservers "$WIFI_SERVICE" $want && flush_dns_cache && ok "DNS servers set to $want"
  else FAILED=$((FAILED + 1)); fi
}

# Backend on THIS Mac must be running the Phase 2 code (sends ETag).
check_local_backend() {  # check_local_backend <port> <letter> <path-to-server.py>
  local h; h=$(curl -sI --max-time 3 "http://localhost:$1/api/status" 2>/dev/null)
  if [[ -z $h ]]; then
    bad "Backend $2 is not running: in a separate Terminal run ${B}python3 $3${N} and keep it open"
  elif ! grep -qi '^etag' <<<"$h"; then
    bad "Backend $2 is running OLD code: stop it (Ctrl+C) and start it again with ${B}python3 $3${N}"
  else ok "Backend $2 is running the Phase 2 code on port $1"; fi
}

# dnsmasq on THIS Mac (Mac 1 / Mac 4): config matches repo + running + answering.
# Offers to install the config and (re)start dnsmasq.
check_dnsmasq() {  # check_dnsmasq <repo-config> <my-ip>
  local tmp; tmp=$(mktemp); render "$1" > "$tmp"
  if [[ ! -x $DNSMASQ_BIN ]]; then bad "dnsmasq not installed: brew install dnsmasq"; rm -f "$tmp"; return; fi
  if sudo launchctl list 2>/dev/null | grep -qE "homebrew.mxcl.dnsmasq|sh.brew.dnsmasq"; then
    echo "  ${R}✘${N} dnsmasq is managed by 'brew services'; these scripts start it directly (like in Phase 1)"
    if ask "Stop the brew service so this script can manage dnsmasq?"; then sudo brew services stop dnsmasq >/dev/null 2>&1
    else FAILED=$((FAILED + 1)); rm -f "$tmp"; return; fi
  fi
  if ! sudo "$DNSMASQ_BIN" --test -C "$tmp" >/dev/null 2>&1; then bad "rendered dnsmasq config failed the syntax check"; rm -f "$tmp"; return; fi
  if ! cmp -s "$tmp" "$DNSMASQ_CONF"; then
    echo "  ${R}✘${N} installed dnsmasq.conf is not the Phase 2 version"
    if ask "Install $(basename "$1") (with your team.env IPs) and restart dnsmasq?"; then
      install_rendered "$tmp" "$DNSMASQ_CONF"; dnsmasq_restart
    else bad "dnsmasq config not installed (answered no)"; rm -f "$tmp"; return; fi
  fi
  rm -f "$tmp"
  if ! pgrep -x dnsmasq >/dev/null; then
    if ask "dnsmasq is not running. Start it?"; then dnsmasq_start; else bad "dnsmasq is not running"; return; fi
  fi
  local ans; ans=$(dig_a "$2")
  if [[ $ans == "$MAC2_IP" ]]; then ok "dnsmasq on this Mac answers $DOMAIN -> $MAC2_IP"
  else bad "dnsmasq on this Mac answers '$ans' for $DOMAIN (expected $MAC2_IP)"; fi
}

# nginx is "running" if an nginx process is listening on TCP 443 (more reliable than pgrep)
nginx_running() { sudo lsof -nP -iTCP:443 -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qx nginx; }

dnsmasq_start()   { sudo "$DNSMASQ_BIN" -C "$DNSMASQ_CONF"; sleep 1; }
dnsmasq_stop()    { sudo pkill -x dnsmasq; sleep 1; }
dnsmasq_restart() { dnsmasq_stop; dnsmasq_start; }

# Point app/api.team${TEAM}.test at <ip> on THIS Mac's dnsmasq (used by Ext B and E).
dns_point() {
  sudo sed -i '' -E "s#^address=/(app|api)\.team${TEAM}\.test/.*#address=/\1.team${TEAM}.test/$1#" "$DNSMASQ_CONF"
  dnsmasq_restart
  info "this Mac's DNS now answers $DOMAIN -> $(dig_a "$(my_ip)")"
}

# Remote-service checks (only report; the owner fixes on their Mac)
check_edge() {
  local codes="" i h
  for i in 1 2 3 4; do
    h=$(curl -sI --cacert "$CA_FILE" --max-time 5 "https://$DOMAIN/api/status" 2>/dev/null)
    codes+=$(awk 'tolower($1) ~ /^x-backend:/ {print $2}' <<<"$h" | tr -d '\r')
  done
  if [[ -z $codes ]]; then bad "https://$DOMAIN/ does not answer: Mac 2 checks nginx (run ./scripts/mac2.sh)"
  elif [[ $codes == *A* && $codes == *B* ]]; then ok "https://$DOMAIN/ works and balances across A and B"
  else bad "edge only returned backend(s) '$codes': start the missing backend (Mac 3 = A, Mac 4 = B)"; fi
  if grep -qi '^etag' <<<"$h"; then ok "backends are running the Phase 2 code (ETag present)"
  else bad "responses have no ETag: Mac 3 / Mac 4 must restart their backends with the new code"; fi
}

check_remote_dns() {  # check_remote_dns <name> <ip>
  local ans; ans=$(dig_a "$2")
  if [[ $ans == "$MAC2_IP" ]]; then ok "$1 DNS ($2) answers $DOMAIN -> $MAC2_IP"
  else bad "$1 DNS ($2) answers '${ans:-nothing}' (expected $MAC2_IP)"; fi
}

preflight_result() {
  echo
  if ((FAILED == 0)); then echo "  ${G}${B}All checks passed.${N}"; return 0; fi
  echo "  ${R}${B}$FAILED check(s) failed.${N} Fix them (or ask the person named), then run this script again."
  echo "  No evidence is collected until every check passes."
  exit 1
}

# Section dispatcher (sections are run one at a time, in lockstep with the team;
# see the run sheet in scripts/README.md):
#   ./macN.sh check     -> preflight only
#   ./macN.sh phase1    -> preflight, then the Phase 1 re-takes
#   ./macN.sh extX      -> one extension (no full preflight: the network is mid-demo)
#   ./macN.sh list      -> show this Mac's sections
run_sections() {
  local want=${1:-check}
  case $want in
    list)  echo "Sections for $ME: check ${SECTIONS[*]}"; exit 0 ;;
    check) preflight; echo "  Next: follow the run sheet in scripts/README.md"; exit 0 ;;
  esac
  if ! printf '%s\n' "${SECTIONS[@]}" | grep -qx "$want"; then
    echo "Unknown section '$want'. Sections: check ${SECTIONS[*]}"; exit 1
  fi
  if [[ $want == phase1 ]]; then preflight; else check_sudo; fi
  "sec_$want"
  title "Section '$want' done. Evidence saved in Evidence/phase2/$(basename "$EVID_DIR")/"
}
