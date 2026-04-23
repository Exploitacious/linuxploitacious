#!/bin/bash
# Custom Claude Code statusline — 4-quadrant dashboard
# Reads JSON from stdin, outputs formatted status line

JSON=$(cat)

# --- Parse all values in one jq call ---
eval $(echo "$JSON" | jq -r '
  "MODEL='"'"'\(.model.display_name // "unknown")'"'"'",
  "CTX_USED=\(.context_window.used_percentage // 0)",
  "CTX_SIZE=\(.context_window.context_window_size // 200000)",
  "COST=\(.cost.total_cost_usd // 0)",
  "TOTAL_MS=\(.cost.total_duration_ms // 0)",
  "API_MS=\(.cost.total_api_duration_ms // 0)",
  "LINES_ADD=\(.cost.total_lines_added // 0)",
  "LINES_REM=\(.cost.total_lines_removed // 0)",
  "CACHE_READ=\(.context_window.current_usage.cache_read_input_tokens // 0)",
  "CACHE_CREATE=\(.context_window.current_usage.cache_creation_input_tokens // 0)",
  "RL_5H=\(.rate_limits.five_hour.used_percentage // "")",
  "RL_7D=\(.rate_limits.seven_day.used_percentage // "")"
' 2>/dev/null)

# Terminal width
COLS=$(tput cols 2>/dev/null || echo 120)

# Colors
RST='\033[0m'
B='\033[1m'
D='\033[2m'
GRN='\033[38;5;78m'
YEL='\033[38;5;220m'
RED='\033[38;5;196m'
CYN='\033[38;5;117m'
PUR='\033[38;5;141m'
GRY='\033[38;5;245m'
WHT='\033[38;5;255m'

# Progress bar: make_bar <percent> <width>
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

# Strip ANSI for measuring visible length
strip_ansi() {
    printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# Print a row: left-aligned text + right-aligned text padded to terminal width
print_row() {
    local left="$1" right="$2"
    local left_vis right_vis
    left_vis=$(strip_ansi "$left")
    right_vis=$(strip_ansi "$right")
    local left_len=${#left_vis}
    local right_len=${#right_vis}
    local gap=$(( COLS - left_len - right_len ))
    [ "$gap" -lt 2 ] && gap=2
    printf '%b' "$left"
    printf '%*s' "$gap" ""
    printf '%b' "$right"
    printf '\n'
}

# === Compute values ===

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

# Caveman badge
CAVEMAN=""
CS="$HOME/.claude/plugins/cache/caveman/caveman/c2ed24b3e5d4/hooks/caveman-statusline.sh"
if [ -x "$CS" ]; then
    CAVEMAN=$(bash "$CS" 2>/dev/null)
    [ -n "$CAVEMAN" ] && CAVEMAN="  $CAVEMAN"
fi

# === TOP LEFT: Model + Tags ===
TOP_LEFT="${B}${PUR}${MODEL}${RST}${CAVEMAN}"

# === TOP RIGHT: Context bar  5h bar  7d bar ===
TOP_RIGHT="${CTX_C}${CTX_BAR}  ${ctx_pct}%${RST} ${D}/ ${CTX_L}${RST}"

if [ -n "$RL_5H" ]; then
    rl5=${RL_5H%.*}
    RL5_BAR=$(make_bar "$rl5" 10)
    RL5C=$(pct_color "$rl5" 50 80)
    TOP_RIGHT="${TOP_RIGHT}   ${D}5h${RST} ${RL5C}${RL5_BAR} ${rl5}%${RST}"
fi
if [ -n "$RL_7D" ]; then
    rl7=${RL_7D%.*}
    RL7_BAR=$(make_bar "$rl7" 10)
    RL7C=$(pct_color "$rl7" 50 80)
    TOP_RIGHT="${TOP_RIGHT}  ${D}7d${RST} ${RL7C}${RL7_BAR} ${rl7}%${RST}"
fi

# === BOTTOM LEFT: Cost + Cache ===
BOT_LEFT="${CYN}\$$(printf '%.2f' "$COST")${RST}   ${CACHE_C}cache ${CACHE_PCT}%${RST}"

# === BOTTOM RIGHT: Time + Changes ===
BOT_RIGHT="${WHT}${TOTAL_TIME}${RST} ${D}total${RST}  ${GRY}${API_TIME}${RST} ${D}api${RST}   ${GRN}+${LINES_ADD}${RST} ${RED}-${LINES_REM}${RST}"

# === Render ===
print_row "$TOP_LEFT" "$TOP_RIGHT"
print_row "$BOT_LEFT" "$BOT_RIGHT"
