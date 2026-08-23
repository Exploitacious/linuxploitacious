#!/usr/bin/env bash
# test_hpill.sh — minimal self-check for the hpill status renderer.
set -u
H="$(dirname "$0")/.local/bin/hpill"
fails=0
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; fails=$((fails+1)); }
out="$("$H" cpu)"; case "$out" in *%*) ok "cpu prints a percent" ;; *) bad "cpu prints a percent (got '$out')" ;; esac
out="$("$H" ram)"; case "$out" in */*G*) ok "ram prints used/total G" ;; *) bad "ram prints used/total G (got '$out')" ;; esac
"$H" bogus >/dev/null 2>&1; [ $? -eq 2 ] && ok "unknown pill exits 2" || bad "unknown pill exits 2"
out="$(HOME=/nonexistent "$H" blocked)"; [ -z "$out" ] && ok "blocked is empty without the registry" || bad "blocked empty without registry (got '$out')"
out="$("$H" clock)"; [ -n "$out" ] && ok "clock prints" || bad "clock prints"
[ "$fails" -eq 0 ] && { echo "hpill selftest: OK"; exit 0; } || { echo "hpill selftest: $fails FAILED"; exit 1; }
