#!/bin/sh

HERE=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d) || exit 1
FAIL=0
PASS=0

ok() { PASS=$((PASS+1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }

mkdir -p "$W/g5" "$W/bin"
export KS_5G="$W/g5" UBUS="$W/bin/ubus" UCI="$W/bin/uci" PGREP="$W/bin/pgrep" REBOOT="$W/bin/reboot" FAKE_LOG="$W/log"
export KS_SIM_CACHE="$W/simcache/sim" KS_SIM_CHECKED="$W/simcache/sim.checked" KS_UPTIME="$W/uptime" KS_5G_REBOOT="$W/bin/reboot5g"
echo "90000.00 1.00" > "$W/uptime"
cat > "$W/bin/ubus" <<'X'
#!/bin/sh
case "$1 $2 $3" in
"list qmodem "*) [ -n "$FAKE_QMODEM" ] && echo qmodem && exit 0; exit 1 ;;
"call qmodem sim_info") [ -n "$FAKE_ICCID" ] && printf '{\n"modem_info": [\n{\n"key": "ICCID",\n"value": "%s"\n}\n]\n}\n' "$FAKE_ICCID" ;;
"call fxs status") [ -n "$FAKE_FXS" ] && echo "{ \"state\": \"$FAKE_FXS\", \"offhook\": \"0\" }" || exit 4 ;;
"call qmodem do_reboot") echo "qmodem $4" >> "$FAKE_LOG" ;;
*) exit 1 ;;
esac
X
cat > "$W/bin/uci" <<'X'
#!/bin/sh
case "$*" in *"show qmodem"*) echo "qmodem.m1=modem-device" ;; *) exit 1 ;; esac
X
cat > "$W/bin/pgrep" <<'X'
#!/bin/sh
[ -n "$FAKE_UPGRADE" ]
X
cat > "$W/bin/reboot" <<'X'
#!/bin/sh
echo reboot >> "$FAKE_LOG"
X
printf '#!/bin/sh\necho "5g $*" >> "$FAKE_LOG"\n' > "$W/bin/reboot5g.off"
chmod +x "$W/bin/"*

. "$HERE/files/common.sh" || { echo "FAIL source common.sh"; exit 1; }

eq "period mid" "$(ks_period_start 2026-11-20 15)" 2026-11-15
eq "period before day" "$(ks_period_start 2026-11-10 15)" 2026-10-15
eq "period 31 in Feb" "$(ks_period_start 2027-02-28 31)" 2027-02-28
eq "period 31 in Mar early" "$(ks_period_start 2027-03-05 31)" 2027-02-28
eq "period leap" "$(ks_period_start 2028-02-29 30)" 2028-02-29
eq "period year wrap" "$(ks_period_start 2027-01-03 20)" 2026-12-20
eq "period day 1" "$(ks_period_start 2026-11-01 1)" 2026-11-01
eq "period 30 in Feb before" "$(ks_period_start 2027-02-27 30)" 2027-01-30
eq "period end" "$(ks_period_end 2026-11-20 15)" 2026-12-14
eq "period end month" "$(ks_period_end 2026-11-20 1)" 2026-11-30
eq "period end before short month" "$(ks_period_end 2027-01-31 31)" 2027-02-27
eq "period bad day falls back to 1" "$(ks_period_start 2026-11-20 x)" 2026-11-01

eq "sim key default" "$(ks_sim_key)" main
[ -e "$W/simcache/sim" ] && bad "default key is not remembered" || ok "default key is not remembered"
printf '{"rsrp":"-90","iccid": "8994-0123"}\n' > "$W/g5/metrics_a.json"
eq "sim key from 5gmodem" "$(ks_sim_key)" 89940123
eq "sim key remembered" "$(cat "$W/simcache/sim")" 89940123
printf '{"rsrp":"-90","iccid": "-"}\n' > "$W/g5/metrics_a.json"
eq "failed read keeps the last key" "$(ks_sim_key)" 89940123
rm "$W/g5/metrics_a.json"
export FAKE_QMODEM=1 FAKE_ICCID=8994555
touch -d '2020-01-01 00:00' "$W/simcache/sim.checked" 2>/dev/null
eq "sim key from qmodem" "$(ks_sim_key)" 8994555
FAKE_ICCID=8994777
eq "qmodem asked at most every 5 min" "$(ks_sim_key)" 8994555
touch -d '2020-01-01 00:00' "$W/simcache/sim.checked"
eq "sim swap noticed" "$(ks_sim_key)" 8994777
unset FAKE_QMODEM FAKE_ICCID
eq "key survives modem loss" "$(ks_sim_key)" 8994777

J=$(ks_json_str 'a"b\c')
eq "json str backslashes doubled" "$(printf '%s' "$J" | tr -cd '\\' | wc -c | tr -d ' ')" 3
eq "json str length" "${#J}" 9

g() { : > "$W/log"; ks_restart_guarded "$1"; cat "$W/log"; }
eq "guard reboots" "$(g router)" reboot
export FAKE_UPGRADE=1
eq "guard skips during sysupgrade" "$(g router)" ""
unset FAKE_UPGRADE
export FAKE_FXS=talking
eq "guard skips during a call" "$(g router)" ""
export FAKE_FXS=idle
eq "guard ok when phone idle" "$(g router)" reboot
export FAKE_FXS=stopped
eq "guard ok when phone service stopped" "$(g router)" reboot
unset FAKE_FXS
echo "300.00 1.00" > "$W/uptime"
eq "guard skips just after boot" "$(g router)" ""
echo "90000.00 1.00" > "$W/uptime"
eq "modem restart without a modem app does nothing" "$(g modem)" ""
export FAKE_QMODEM=1
eq "modem restart via qmodem" "$(g modem)" 'qmodem {"config_section":"m1","params":{"method":"soft"}}'
mv "$W/bin/reboot5g.off" "$W/bin/reboot5g"
eq "modem restart via 5gmodem" "$(g modem)" "5g soft"
unset FAKE_QMODEM

# The exact line the app writes to crontab, with the guard path swapped for this checkout.
: > "$W/log"
sh -c ". $HERE/files/common.sh && ks_restart_guarded router # keystone-restart"
eq "cron line runs the guard" "$(cat "$W/log")" reboot
: > "$W/log"
echo "300.00 1.00" > "$W/uptime"
sh -c ". $HERE/files/common.sh && ks_restart_guarded router # keystone-restart"
eq "cron line is skipped just after boot" "$(cat "$W/log")" ""
echo "90000.00 1.00" > "$W/uptime"

mkdir -p "$W/t" "$W/e"
echo x > "$W/t/a"
ks_flush "$W/t" "$W/e" "$W/stamp" 0 1000
eq "flush first time" "$(cat "$W/e/a" 2>/dev/null)" x
echo y > "$W/t/a"
ks_flush "$W/t" "$W/e" "$W/stamp" 0 2000
eq "flush waits an hour" "$(cat "$W/e/a")" x
ks_flush "$W/t" "$W/e" "$W/stamp" 1 2001
eq "flush forced" "$(cat "$W/e/a")" y
touch -d '2020-01-01 00:00' "$W/e/a"
ks_flush "$W/t" "$W/e" "$W/stamp" 1 2002
eq "unchanged file not rewritten" "$(find "$W/e/a" -mtime +100)" "$W/e/a"

sh -n "$HERE/files/common.sh" && ok "syntax common.sh" || bad "syntax common.sh"

rm -rf "${W:?}"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
