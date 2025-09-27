#!/usr/bin/env bash
# FlashKidd Recon & Advisor
# Performs lightweight port reconnaissance and emits human-readable or JSON reports.
set -euo pipefail

cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

pick_nc() {
  if cmd_exists nc; then
    if nc -h 2>&1 | grep -qi "OpenBSD"; then
      echo "$(command -v nc)"
      return 0
    fi
  fi
  if cmd_exists nc.openbsd; then
    echo "$(command -v nc.openbsd)"
    return 0
  fi
  if cmd_exists netcat-openbsd; then
    echo "$(command -v netcat-openbsd)"
    return 0
  fi
  if cmd_exists busybox && busybox nc -h >/dev/null 2>&1; then
    echo "busybox nc"
    return 0
  fi
  if cmd_exists nc; then
    echo "$(command -v nc)"
    return 0
  fi
  if [[ -x /bin/nc ]]; then
    echo "/bin/nc"
    return 0
  fi
  echo ""
}

usage() {
  cat <<USAGE
Usage: $(basename "$0") [IP_ADDRESS] [--json]

Perform a basic TCP reachability probe against common service ports.
Provide an IP to override automatic detection. Use --json for JSON output.
USAGE
}

MODE="human"
IP_ARG=""
while (($#)); do
  case "$1" in
    --json)
      MODE="json"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$IP_ARG" ]]; then
        IP_ARG="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

DEFAULT_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
DEFAULT_IP="${DEFAULT_IP:-127.0.0.1}"
TARGET_IP="${IP_ARG:-$DEFAULT_IP}"
PORTS=(22 80 443 1194 8080 3128 53)
NC_CHOICE="$(pick_nc)"
declare -a NC_CMD=()
if [[ -n "$NC_CHOICE" ]]; then
  # shellcheck disable=SC2206 # intentional splitting for multi-word commands
  NC_CMD=($NC_CHOICE)
fi
declare -A STATUS=()

probe_port() {
  local ip="$1"
  local port="$2"
  if ((${#NC_CMD[@]} > 0)); then
    if "${NC_CMD[@]}" -z -w 1 "$ip" "$port" >/dev/null 2>&1; then
      echo "open"
    else
      echo "closed"
    fi
  else
    echo "unknown"
  fi
}

for port in "${PORTS[@]}"; do
  STATUS["$port"]="$(probe_port "$TARGET_IP" "$port")"
done

collect_advice() {
  local -a advice=()
  [[ "${STATUS[443]}" == "open" ]] && advice+=("SSH over TLS / V2Ray WS+TLS / Xray TLS feasible.")
  [[ "${STATUS[80]}" == "open" ]] && advice+=("HTTP proxy / WebSocket (no TLS) feasible.")
  [[ "${STATUS[22]}" == "open" ]] && advice+=("Direct SSH available.")
  [[ "${STATUS[1194]}" == "open" ]] && advice+=("OpenVPN (UDP/TCP) likely feasible.")
  if [[ "${STATUS[8080]}" == "open" || "${STATUS[3128]}" == "open" ]]; then
    advice+=("HTTP proxy (Squid/HTTP) feasible.")
  fi
  [[ "${STATUS[53]}" == "open" ]] && advice+=("DNS tunneling possible (low throughput; caution).")
  printf '%s\n' "${advice[@]}"
}

print_banner() {
  echo "FlashKidd SSH — Recon & Advisor"
  echo "================================"
}

print_human() {
  print_banner
  echo
  echo "🔍 Recon Report for $TARGET_IP"
  echo "Time: $(iso_now)"
  echo
  for port in "${PORTS[@]}"; do
    case "${STATUS[$port]}" in
      open)
        echo "✅ Port $port OPEN"
        ;;
      closed)
        echo "❌ Port $port CLOSED"
        ;;
      *)
        echo "⚠️  Port $port UNKNOWN"
        ;;
    esac
  done
  echo
  echo "📡 Advisor"
  local had_output=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "- $line"
    had_output=1
  done < <(collect_advice)
  if [[ $had_output -eq 0 ]]; then
    echo "- No service-specific recommendations at this time."
  fi
  if ((${#NC_CMD[@]} == 0)); then
    echo
    echo "Tip: Netcat not found. Install with: sudo apt-get update && sudo apt-get install -y netcat-openbsd"
  fi
}

json_escape() {
  local input="$1"
  input=$(printf '%s' "$input" | sed -e 's/\\/\\\\/g' -e 's/"/\"/g')
  printf '%s' "$input"
}

print_json() {
  local timestamp
  timestamp="$(iso_now)"
  printf '{"ip":"%s","timestamp":"%s","ports":{' "$(json_escape "$TARGET_IP")" "$(json_escape "$timestamp")"
  local first=1
  for port in "${PORTS[@]}"; do
    if [[ $first -eq 0 ]]; then
      printf ','
    fi
    printf '"%s":"%s"' "$port" "${STATUS[$port]}"
    first=0
  done
  printf '},"advice":['
  local -a advice_array=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    advice_array+=("$line")
  done < <(collect_advice)
  for i in "${!advice_array[@]}"; do
    [[ $i -gt 0 ]] && printf ','
    printf '"%s"' "$(json_escape "${advice_array[$i]}")"
  done
  printf ']}'
  printf '\n'
  if ((${#NC_CMD[@]} == 0)); then
    >&2 echo "Tip: Netcat not found. Install with: sudo apt-get update && sudo apt-get install -y netcat-openbsd"
  fi
}

if [[ "$MODE" == "json" ]]; then
  print_json
else
  print_human
fi

if [[ "$MODE" != "json" && -t 0 && -t 1 ]]; then
  echo
  read -rp "Press Enter to return to the main menu…" _ || true
fi
