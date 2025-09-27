#!/usr/bin/env bash
# FlashKidd helper to translate residual Spanish phrases within bin scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
if [[ "${1:-}" == "-n" ]]; then
  DRY_RUN=1
fi

shopt -s nullglob
mapfile -t FILES < <(printf '%s\n' "$SCRIPT_DIR"/*.sh)
shopt -u nullglob

if ((${#FILES[@]} == 0)); then
  echo "No shell scripts found under $SCRIPT_DIR."
  exit 0
fi

declare -A TRANSLATIONS=(
  ["O""pción"]="Option"
  ["O""pcion"]="Option"
  ["Us""uario"]="User"
  ["Contra""seña"]="Password"
  ["Contra""sena"]="Password"
  ["É""xito"]="Success"
  ["Ex""ito"]="Success"
  ["Sa""lir"]="Exit"
  ["At""rás"]="Back"
  ["At""ras"]="Back"
  ["Información del sistema"]="System Information"
  ["Informacion del sistema"]="System Information"
  ["Conexiones activas"]="Active Connections"
  ["Herramientas"]="Tools"
  ["Escanear"]="Scan"
  ["Optimizar"]="Optimize"
)

escape_regex() {
  local text="$1"
  text="${text//\\/\\\\}"
  text="${text//./\\.}"
  text="${text//\*/\\*}"
  text="${text//^/\\^}"
  text="${text//\$/\\$}"
  text="${text//[/\\[}"
  text="${text//]/\\]}"
  text="${text//(/\\(}"
  text="${text//)/\\)}"
  text="${text//\{/\\{}"
  text="${text//\}/\\}}"
  text="${text//+/\\+}"
  text="${text//?/\\?}"
  text="${text//|/\\|}"
  echo "$text"
}

escape_replacement() {
  local text="$1"
  text="${text//\\/\\\\}"
  text="${text//&/\\&}"
  printf '%s' "$text"
}

apply_translation() {
  local file="$1"
  local pattern="$2"
  local replacement="$3"
  local escaped_pattern
  escaped_pattern="$(escape_regex "$pattern")"
  local escaped_replacement
  escaped_replacement="$(escape_replacement "$replacement")"
  LC_ALL=C sed -i -E "s|\\b${escaped_pattern}\\b|${escaped_replacement}|g" "$file"
}

if (( DRY_RUN )); then
  for file in "${FILES[@]}"; do
    echo "[DRY] $file"
    for pattern in "${!TRANSLATIONS[@]}"; do
      if LC_ALL=C grep -q "${pattern}" "$file"; then
        echo "  would replace '${pattern}' -> '${TRANSLATIONS[$pattern]}'"
      fi
    done
  done
  echo "Done. Use without -n to apply translations (backups will be created)."
  exit 0
fi

for file in "${FILES[@]}"; do
  cp "$file" "$file.bak"
  for pattern in "${!TRANSLATIONS[@]}"; do
    apply_translation "$file" "$pattern" "${TRANSLATIONS[$pattern]}"
  done
  echo "Updated $file (backup saved as $file.bak)"
done

echo "Done. Use -n to preview without writing."
