#!/bin/bash
# Custom Claude Code statusline — 3-row dashboard with column-aligned separators
# Reads JSON from stdin, outputs formatted status line

JSON=$(cat)

# Fail-safe defaults so downstream arithmetic comparisons never see
# empty strings (which throw bash arithmetic errors under set -u or
# when used inside `[ ... -ge ... ]`).
MODEL="unknown"
CTX_USED=0
CTX_SIZE=200000
COST=0
TOTAL_MS=0
API_MS=0
LINES_ADD=0
LINES_REM=0
CACHE_READ=0
CACHE_CREATE=0
RL_5H=""
RL_7D=""
RL_5H_RESET=""
RL_7D_RESET=""

# --- Parse values via NUL-separated jq output ---
# Old version used `eval $(jq -r '...')` which broke on quotes/newlines
# in any model display_name and was a shell-injection surface for any
# tool that could influence the JSON. Read fields into bash vars
# directly via NUL-terminated jq output.
if command -v jq >/dev/null 2>&1; then
  # One line per KEY=value. Values here are numbers or short identifiers
  # (model display_name) so embedded newlines aren't a real concern;
  # gsub strips them just in case.
  while IFS='=' read -r key val; do
    case "$key" in
      MODEL|CTX_USED|CTX_SIZE|COST|TOTAL_MS|API_MS|LINES_ADD|LINES_REM|CACHE_READ|CACHE_CREATE|RL_5H|RL_7D|RL_5H_RESET|RL_7D_RESET)
        printf -v "$key" '%s' "$val"
        ;;
    esac
  done < <(printf '%s' "$JSON" | jq -r '
    def s: tostring | gsub("\n"; " ");
    "MODEL=" + (.model.display_name // "unknown" | s),
    "CTX_USED=" + (.context_window.used_percentage // 0 | s),
    "CTX_SIZE=" + (.context_window.context_window_size // 200000 | s),
    "COST=" + (.cost.total_cost_usd // 0 | s),
    "TOTAL_MS=" + (.cost.total_duration_ms // 0 | s),
    "API_MS=" + (.cost.total_api_duration_ms // 0 | s),
    "LINES_ADD=" + (.cost.total_lines_added // 0 | s),
    "LINES_REM=" + (.cost.total_lines_removed // 0 | s),
    "CACHE_READ=" + (.context_window.current_usage.cache_read_input_tokens // 0 | s),
    "CACHE_CREATE=" + (.context_window.current_usage.cache_creation_input_tokens // 0 | s),
    "RL_5H=" + (.rate_limits.five_hour.used_percentage // "" | s),
    "RL_7D=" + (.rate_limits.seven_day.used_percentage // "" | s),
    "RL_5H_RESET=" + (.rate_limits.five_hour.resets_at // "" | s),
    "RL_7D_RESET=" + (.rate_limits.seven_day.resets_at // "" | s)
  ' 2>/dev/null)
fi

# Defensive: any field still empty after parsing falls back to safe defaults
# so downstream `[ "$pct" -ge "$crit" ]` arithmetic never sees empty.
: "${CTX_USED:=0}" "${CTX_SIZE:=200000}" "${COST:=0}"
: "${TOTAL_MS:=0}" "${API_MS:=0}" "${LINES_ADD:=0}" "${LINES_REM:=0}"
: "${CACHE_READ:=0}" "${CACHE_CREATE:=0}"

# Colors (use $'...' so ESC is a real byte, not literal backslash text)
RST=$'\033[0m'
B=$'\033[1m'
D=$'\033[2m'
GRN=$'\033[38;5;78m'
YEL=$'\033[38;5;220m'
RED=$'\033[38;5;196m'
CYN=$'\033[38;5;117m'
PUR=$'\033[38;5;141m'
GRY=$'\033[38;5;245m'
WHT=$'\033[38;5;255m'
SEP="${GRY}│${RST}"
SEP_WRAP="      ${SEP}      "

# Column widths (visible chars, before separator)
COL1_W=46
COL2_W=52

# Progress bar
make_bar() {
    local pct=$1 width=$2
    local filled=$(( pct * width / 100 ))
    [ "$filled" -gt "$width" ] && filled=$width
    local empty=$(( width - filled ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="▓"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo "$bar"
}

# Color by threshold (high = bad)
pct_color() {
    local pct=$1 warn=${2:-70} crit=${3:-90}
    if [ "$pct" -ge "$crit" ] 2>/dev/null; then echo "$RED"
    elif [ "$pct" -ge "$warn" ] 2>/dev/null; then echo "$YEL"
    else echo "$GRN"; fi
}

# Time formatter
fmt_time() {
    local ms=$1
    if [ "$ms" -ge 3600000 ] 2>/dev/null; then
        printf "%dh %dm" $((ms/3600000)) $(((ms%3600000)/60000))
    elif [ "$ms" -ge 60000 ] 2>/dev/null; then
        printf "%dm %ds" $((ms/60000)) $(((ms%60000)/1000))
    elif [ "$ms" -ge 1000 ] 2>/dev/null; then
        printf "%ds" $((ms/1000))
    else
        printf "0s"
    fi
}

# Time-to-reset formatter: seconds -> "2d 5h" / "3h 20m" / "45m" / "now".
# Used for rate-limit reset countdowns (resets_at is Unix epoch seconds).
fmt_ttl() {
    local s=$1
    [ "$s" -le 0 ] 2>/dev/null && { printf "now"; return; }
    local d=$(( s / 86400 )) h=$(( (s % 86400) / 3600 )) m=$(( (s % 3600) / 60 ))
    if [ "$d" -gt 0 ]; then printf '%dd %dh' "$d" "$h"
    elif [ "$h" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
    else printf '%dm' "$m"; fi
}

# Strip ANSI escapes to measure visible length
strip_ansi() {
    printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# Pad a string (with ANSI) to target visible width
pad_to() {
    local s="$1" target="$2"
    local vis
    vis=$(strip_ansi "$s")
    local len=${#vis}
    local need=$(( target - len ))
    [ "$need" -lt 0 ] && need=0
    printf '%s%*s' "$s" "$need" ""
}

# === Compute values ===

# Posture badge — autocompact + effort, read from the ACTIVE profile's
# settings.json (CLAUDE_CONFIG_DIR resolves per profile; both symlink to the
# same source). Not in the statusline JSON, so we read the config directly.
# Gives the operator a persistent, visible "autocompact is off" indicator the
# TUI otherwise never surfaces.
POSTURE=""
SETTINGS_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
if [ -r "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
    # NOTE: read autoCompactEnabled WITHOUT jq's `//` operator — `//` treats
    # both null AND false as empty, so `.autoCompactEnabled // empty` would
    # swallow an explicit `false` and wrongly report "on". Plain `.x` yields
    # the literal "false"/"true"/"null".
    ac=$(jq -r '.autoCompactEnabled' "$SETTINGS_FILE" 2>/dev/null)
    eff=$(jq -r '.effortLevel // empty' "$SETTINGS_FILE" 2>/dev/null)
    # autoCompactEnabled absent (null) => Claude default ON; explicit false => OFF.
    if [ "$ac" = "false" ]; then ac_txt="off"; ac_c="$GRN"; else ac_txt="on"; ac_c="$YEL"; fi
    [ -n "$eff" ] || eff="default"
    POSTURE="   ${D}AC:${RST}${ac_c}${ac_txt}${RST} ${D}·${RST} ${CYN}${eff}${RST}"
fi

# Rate-limit reset countdowns (resets_at = Unix epoch seconds).
NOW_EPOCH=$(date +%s 2>/dev/null || echo 0)
RL5_TTL=""; RL7_TTL=""
case "$RL_5H_RESET" in ''|*[!0-9]*) ;; *) RL5_TTL=$(fmt_ttl $(( RL_5H_RESET - NOW_EPOCH )) ) ;; esac
case "$RL_7D_RESET" in ''|*[!0-9]*) ;; *) RL7_TTL=$(fmt_ttl $(( RL_7D_RESET - NOW_EPOCH )) ) ;; esac

# Context
ctx_pct=${CTX_USED%.*}
CTX_BAR=$(make_bar "$ctx_pct" 20)
CTX_C=$(pct_color "$ctx_pct")
if [ "$CTX_SIZE" -ge 1000000 ] 2>/dev/null; then CTX_L="1M"; else CTX_L="200k"; fi

# Cache
TOTAL_CACHE=$((CACHE_READ + CACHE_CREATE))
if [ "$TOTAL_CACHE" -gt 0 ] 2>/dev/null; then
    CACHE_PCT=$((CACHE_READ * 100 / TOTAL_CACHE))
else
    CACHE_PCT=0
fi
if [ "$CACHE_PCT" -ge 70 ]; then CACHE_C=$GRN
elif [ "$CACHE_PCT" -ge 40 ]; then CACHE_C=$YEL
else CACHE_C=$RED; fi

# Time
TOTAL_TIME=$(fmt_time "$TOTAL_MS")
API_TIME=$(fmt_time "$API_MS")

# Caveman badge — stable marketplace path first; fall back to versioned cache.
# Cache dir hash changes on plugin update, so hardcoding it drifts and badge disappears.
CAVEMAN=""
CS="$HOME/.claude/plugins/marketplaces/caveman/src/hooks/caveman-statusline.sh"
if [ ! -e "$CS" ]; then
    CS=$(ls -1 "$HOME/.claude/plugins/cache/caveman/caveman/"*/src/hooks/caveman-statusline.sh 2>/dev/null | head -1)
fi
if [ -n "$CS" ] && [ -r "$CS" ]; then
    CAVEMAN=$(bash "$CS" 2>/dev/null)
    [ -n "$CAVEMAN" ] && CAVEMAN="  $CAVEMAN"
fi

# Ponytail badge — same pattern as caveman. Marketplace path first, fall back
# to versioned cache (cache hash changes on update). The script self-resolves
# its .ponytail-active flag via CLAUDE_CONFIG_DIR, so it prints per-profile.
PONYTAIL=""
PS="$HOME/.claude/plugins/marketplaces/ponytail/hooks/ponytail-statusline.sh"
if [ ! -e "$PS" ]; then
    PS=$(ls -1 "$HOME/.claude/plugins/cache/ponytail/ponytail/"*/hooks/ponytail-statusline.sh 2>/dev/null | head -1)
fi
if [ -n "$PS" ] && [ -r "$PS" ]; then
    PONYTAIL=$(bash "$PS" 2>/dev/null)
    [ -n "$PONYTAIL" ] && PONYTAIL="  $PONYTAIL"
fi

# Formatted cost
COST_FMT=$(printf '%.2f' "$COST")

# === Build cells ===

# Profile tag — which account this session burns. CLAUDE_CONFIG_DIR is
# unset for work (default) and ~/.claude-personal for the `clawd` launcher.
_ccd="${CLAUDE_CONFIG_DIR:-}"   # normalize backslashes so a Windows path matches (gap #18)
case "${_ccd//\\//}" in
    */.claude-personal) PROFILE="${B}${YEL}PERSONAL${RST} " ;;
    *)                  PROFILE="${B}${CYN}WORK${RST} " ;;
esac

# Row 1: profile+model+badges  │  context bar  │  time
R1_C1="${PROFILE}${B}${PUR}${MODEL}${RST}${CAVEMAN}${PONYTAIL}"
R1_C2="${CTX_C}${CTX_BAR}   ${ctx_pct}%${RST}   ${D}/ ${CTX_L}${RST}${POSTURE}"
R1_C3="${WHT}${TOTAL_TIME}${RST} ${D}total${RST}     ${GRY}${API_TIME}${RST} ${D}api${RST}"

# Row 2: Usage  $cost  cache%  │  (blank)  │  +/- lines
R2_C1="${D}Usage${RST}      ${CYN}\$${COST_FMT}${RST}      ${CACHE_C}cache ${CACHE_PCT}%${RST}"
R2_C3="${GRN}+${LINES_ADD}${RST}   ${RED}-${LINES_REM}${RST}"

# Row 3: Capacity  5h bar  │  7d bar
if [ -n "$RL_5H" ]; then
    rl5=${RL_5H%.*}
    RL5_BAR=$(make_bar "$rl5" 10)
    RL5C=$(pct_color "$rl5" 50 80)
fi
if [ -n "$RL_7D" ]; then
    rl7=${RL_7D%.*}
    RL7_BAR=$(make_bar "$rl7" 10)
    RL7C=$(pct_color "$rl7" 50 80)
fi
R3_C1="${D}Capacity${RST}      ${D}5h${RST} ${RL5C}${RL5_BAR}   ${rl5}%${RST}${RL5_TTL:+   ${D}↻ ${RST}${GRY}${RL5_TTL}${RST}}"
R3_C2="${D}7d${RST} ${RL7C}${RL7_BAR}   ${rl7}%${RST}${RL7_TTL:+   ${D}↻ ${RST}${GRY}${RL7_TTL}${RST}}"

# === Render ===

# Row 1
pad_to "$R1_C1" "$COL1_W"
printf '%s' "${SEP_WRAP}"
pad_to "$R1_C2" "$COL2_W"
printf '%s' "${SEP_WRAP}"
printf '%s\n\n' "$R1_C3"

# Row 2
pad_to "$R2_C1" "$COL1_W"
printf '%s' "${SEP_WRAP}"
pad_to "" "$COL2_W"
printf '%s' "${SEP_WRAP}"
printf '%s\n\n' "$R2_C3"

# Row 3
if [ -n "$RL_5H" ] || [ -n "$RL_7D" ]; then
    pad_to "$R3_C1" "$COL1_W"
    printf '%s' "${SEP_WRAP}"
    printf '%s\n' "$R3_C2"
fi
