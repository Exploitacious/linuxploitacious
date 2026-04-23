#!/bin/bash
# Custom Claude Code statusline — comprehensive dashboard
# Reads JSON from stdin, outputs formatted status line

JSON=$(cat)

# --- Parse all values in one jq call for performance ---
eval $(echo "$JSON" | jq -r '
  "MODEL='"'"'\(.model.display_name // "unknown")'"'"'",
  "CTX_USED=\(.context_window.used_percentage // 0)",
  "CTX_SIZE=\(.context_window.context_window_size // 200000)",
  "COST=\(.cost.total_cost_usd // 0)",
  "TOTAL_MS=\(.cost.total_duration_ms // 0)",
  "API_MS=\(.cost.total_api_duration_ms // 0)",
  "LINES_ADD=\(.cost.total_lines_added // 0)",
  "LINES_REM=\(.cost.total_lines_removed // 0)",
  "INPUT_TOK=\(.context_window.current_usage.input_tokens // 0)",
  "CACHE_READ=\(.context_window.current_usage.cache_read_input_tokens // 0)",
  "CACHE_CREATE=\(.context_window.current_usage.cache_creation_input_tokens // 0)",
  "OUTPUT_TOK=\(.context_window.current_usage.output_tokens // 0)",
  "TOTAL_IN=\(.context_window.total_input_tokens // 0)",
  "TOTAL_OUT=\(.context_window.total_output_tokens // 0)",
  "RL_5H=\(.rate_limits.five_hour.used_percentage // "")",
  "RL_7D=\(.rate_limits.seven_day.used_percentage // "")"
' 2>/dev/null)

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
SEP="${GRY}│${RST}"

# Context bar color
ctx_pct=${CTX_USED%.*}
if [ "$ctx_pct" -ge 90 ] 2>/dev/null; then BAR_C=$RED
elif [ "$ctx_pct" -ge 70 ] 2>/dev/null; then BAR_C=$YEL
else BAR_C=$GRN; fi

# Progress bar (20 wide)
BAR_W=20
filled=$(( ctx_pct * BAR_W / 100 ))
[ "$filled" -gt "$BAR_W" ] && filled=$BAR_W
empty=$(( BAR_W - filled ))
BAR=""
for ((i=0; i<filled; i++)); do BAR+="▓"; done
for ((i=0; i<empty; i++)); do BAR+="░"; done

# Context size label
if [ "$CTX_SIZE" -ge 1000000 ] 2>/dev/null; then CTX_L="1M"; else CTX_L="200k"; fi

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

# Token formatter
fmt_tok() {
    local t=$1
    if [ "$t" -ge 1000000 ] 2>/dev/null; then
        printf "%.1fM" "$(echo "scale=1; $t/1000000" | bc 2>/dev/null || echo 0)"
    elif [ "$t" -ge 1000 ] 2>/dev/null; then
        printf "%.1fk" "$(echo "scale=1; $t/1000" | bc 2>/dev/null || echo 0)"
    else
        printf "%d" "$t"
    fi
}

TOTAL_TIME=$(fmt_time "$TOTAL_MS")
API_TIME=$(fmt_time "$API_MS")

# Cache hit rate
TOTAL_CACHE=$((CACHE_READ + CACHE_CREATE))
if [ "$TOTAL_CACHE" -gt 0 ] 2>/dev/null; then
    CACHE_PCT=$((CACHE_READ * 100 / TOTAL_CACHE))
else
    CACHE_PCT=0
fi
if [ "$CACHE_PCT" -ge 70 ]; then CACHE_C=$GRN
elif [ "$CACHE_PCT" -ge 40 ]; then CACHE_C=$YEL
else CACHE_C=$RED; fi

# Caveman badge
CAVEMAN=""
CS="$HOME/.claude/plugins/cache/caveman/caveman/c2ed24b3e5d4/hooks/caveman-statusline.sh"
if [ -x "$CS" ]; then
    CAVEMAN=$(bash "$CS" 2>/dev/null)
    [ -n "$CAVEMAN" ] && CAVEMAN="  $CAVEMAN"
fi

# ═══════════════════════════════════════════════════════════
# LINE 1:  Model  │  Context Bar  │  Cost  │  Time  │  Lines
# ═══════════════════════════════════════════════════════════
printf "${B}${PUR}%s${RST}" "$MODEL"
printf "${CAVEMAN}"
printf "   ${SEP}   "
printf "${BAR_C}${BAR}  %d%%${RST} ${D}/ ${CTX_L}${RST}" "$ctx_pct"
printf "   ${SEP}   "
printf "${CYN}\$%.2f${RST}" "$COST"
printf "   ${SEP}   "
printf "${WHT}%s${RST} ${D}total${RST}  ${GRY}%s${RST} ${D}api${RST}" "$TOTAL_TIME" "$API_TIME"

if [ "$LINES_ADD" -gt 0 ] 2>/dev/null || [ "$LINES_REM" -gt 0 ] 2>/dev/null; then
    printf "   ${SEP}   "
    printf "${GRN}+%d${RST} ${RED}-%d${RST}" "$LINES_ADD" "$LINES_REM"
fi

printf "\n"

# ═══════════════════════════════════════════════════════════
# LINE 2:  Tokens  │  Cache  │  Session Totals  │  Rate Limits
# ═══════════════════════════════════════════════════════════
printf "${D}turn${RST}  ${WHT}$(fmt_tok $INPUT_TOK)${RST} ${D}in${RST}  ${WHT}$(fmt_tok $OUTPUT_TOK)${RST} ${D}out${RST}"
printf "   ${SEP}   "
printf "${CACHE_C}cache %d%%${RST}  ${D}($(fmt_tok $CACHE_READ) read / $(fmt_tok $CACHE_CREATE) write)${RST}" "$CACHE_PCT"
printf "   ${SEP}   "
printf "${D}session${RST}  ${WHT}$(fmt_tok $TOTAL_IN)${RST} ${D}in${RST}  ${WHT}$(fmt_tok $TOTAL_OUT)${RST} ${D}out${RST}"

if [ -n "$RL_5H" ] || [ -n "$RL_7D" ]; then
    printf "   ${SEP}   "
    if [ -n "$RL_5H" ]; then
        rl5=${RL_5H%.*}
        if [ "$rl5" -ge 80 ] 2>/dev/null; then RL5C=$RED
        elif [ "$rl5" -ge 50 ] 2>/dev/null; then RL5C=$YEL
        else RL5C=$GRN; fi
        printf "${RL5C}5h %d%%${RST}" "$rl5"
    fi
    if [ -n "$RL_7D" ]; then
        rl7=${RL_7D%.*}
        if [ "$rl7" -ge 80 ] 2>/dev/null; then RL7C=$RED
        elif [ "$rl7" -ge 50 ] 2>/dev/null; then RL7C=$YEL
        else RL7C=$GRN; fi
        [ -n "$RL_5H" ] && printf "  "
        printf "${RL7C}7d %d%%${RST}" "$rl7"
    fi
fi

printf "\n"
