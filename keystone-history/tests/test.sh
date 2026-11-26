#!/bin/sh

HERE=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
FAIL=0
PASS=0

ok() { PASS=$((PASS+1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }

mkdir -p "$W/bin"
cat > "$W/bin/ubus" <<'X'
#!/bin/sh
echo "ubus $*" >> "$FAKE_LOG"
case "$1 $2 $3" in
"list qmodem "*) [ -n "$FAKE_QMODEM" ] && echo qmodem && exit 0; exit 1 ;;
"call qmodem cell_info") cat "$FAKE_CELL" ;;
"call qmodem get_current_band") cat "$FAKE_BAND" ;;
"call network.interface dump") cat "$FAKE_DUMP" ;;
esac
X
cat > "$W/bin/mmcli" <<'X'
#!/bin/sh
echo "mmcli $*" >> "$FAKE_LOG"
[ -n "$FAKE_MM" ] || { echo "error: couldn't find the ModemManager process in the bus" >&2; exit 1; }
case "$*" in
*--signal-setup*) exit 0 ;;
*--signal-get*) cat "$FAKE_MM" ;;
esac
X
chmod +x "$W/bin/mmcli"
cat > "$W/bin/ping" <<'X'
#!/bin/sh
echo "ping $*" >> "$FAKE_LOG"
[ -n "$FAKE_PING_FAIL" ] && exit 1
echo "64 bytes from 8.8.8.8: seq=0 ttl=117 time=23.4 ms"
X
cat > "$W/bin/uci" <<'X'
#!/bin/sh
case "$*" in
*"show qmodem"*) echo "qmodem.m1=modem-device" ;;
*keystone-history.main.ping_target*) [ -n "$FAKE_TARGET" ] && echo "$FAKE_TARGET" || exit 1 ;;
*keystone-history.main.tcp_target*) [ -n "$FAKE_TCP" ] && echo "$FAKE_TCP" || exit 1 ;;
*"set keystone-history.main.keep_days="*) echo "${2#*=}" > "$FAKE_KEEP" ;;
*keystone-history.main.keep_days*) [ -f "$FAKE_KEEP" ] && cat "$FAKE_KEEP" || exit 1 ;;
*commit*) echo "uci $*" >> "$FAKE_LOG" ;;
*"set keystone-history."*) k=${2%%=*}; grep -v "^$k=" "$FAKE_UCIDB" > "$FAKE_UCIDB.n" 2>/dev/null; echo "$2" >> "$FAKE_UCIDB.n"; mv "$FAKE_UCIDB.n" "$FAKE_UCIDB" ;;
*"delete keystone-history."*) eval k=\${$#}; grep -v "^$k[.=]" "$FAKE_UCIDB" > "$FAKE_UCIDB.n" 2>/dev/null; mv "$FAKE_UCIDB.n" "$FAKE_UCIDB" ;;
*"get keystone-history."*) eval k=\${$#}; v=$(sed -n "s/^$k=//p" "$FAKE_UCIDB" 2>/dev/null); [ -n "$v" ] && echo "$v" || exit 1 ;;
*"show keystone-history"*) cat "$FAKE_UCIDB" 2>/dev/null ;;
esac
X
cat > "$W/bin/date" <<'X'
#!/bin/sh
case "$1" in
+%s) echo "$FAKE_NOW" ;;
+%Y-%m) echo "${FAKE_MONTH:-2026-11}" ;;
+%F) echo "${FAKE_DAY:-2026-11-20}" ;;
esac
X
printf '#!/bin/sh
exec sh "%s/files/keystone-history" "$@"
' "$HERE" > "$W/bin/collector"
cat > "$W/bin/curl" <<'X'
#!/bin/sh
echo "curl $*" >> "$FAKE_LOG"
[ -n "$FAKE_CURL" ] && { printf "%s" "$FAKE_CURL"; exit ${FAKE_CURL_RC:-0}; }
exit 1
X
cat > "$W/bin/vnstat" <<'X'
#!/bin/sh
[ -n "$FAKE_VNSTAT" ] && echo "$FAKE_VNSTAT" && exit 0
exit 1
X
chmod +x "$W/bin/"*

cat > "$W/cell.json" <<'X'
{
	"modem_info": [
		{
			"key": "LTE",
			"value": "LTE"
		},
		{
			"key": "RSRP",
			"value": "-95",
			"unit": "dBm"
		},
		{
			"key": "SINR",
			"value": "17",
			"unit": "dB"
		}
	]
}
X
cat > "$W/band.json" <<'X'
{
	"current_band": {
		"status": "ok",
		"cells": [
			{
				"role": "pcc",
				"rat": "LTE",
				"band_name": "B3",
				"channel": "1725",
				"pci": "151"
			}
		]
	}
}
X
cat > "$W/dump.json" <<'X'
{
	"interface": [
		{
			"interface": "lan",
			"up": true,
			"l3_device": "br-lan",
			"route": []
		},
		{
			"interface": "wwan",
			"up": true,
			"l3_device": "wwan0_1",
			"route": [
				{
					"target": "0.0.0.0",
					"mask": 0,
					"nexthop": "10.0.0.1"
				}
			]
		}
	]
}
X

setup() {
	rm -rf "$W/tmp" "$W/etc" "$W/sys" "$W/g5" "$W/log" "$W/keep"
	mkdir -p "$W/tmp" "$W/etc" "$W/g5" "$W/sys/wwan0_1/statistics"
	: > "$W/log"
	echo 1000 > "$W/sys/wwan0_1/statistics/rx_bytes"
	echo 500 > "$W/sys/wwan0_1/statistics/tx_bytes"
	export KS_TMP="$W/tmp" KS_ETC="$W/etc" KS_SYS="$W/sys" KS_5G="$W/g5"
	export MMCLI="$W/bin/mmcli" UBUS="$W/bin/ubus" PING="$W/bin/ping" CURL="$W/bin/curl" UCI="$W/bin/uci" DATE="$W/bin/date"
	export FAKE_KEEP="$W/keep" KS_COLLECTOR="$W/bin/collector"
export FAKE_LOG="$W/log" FAKE_CELL="$W/cell.json" FAKE_BAND="$W/band.json" FAKE_DUMP="$W/dump.json"
	export FAKE_NOW=1000000 FAKE_QMODEM=1 FAKE_UCIDB="$W/ucidb" KS_SIM_CACHE="$W/sim" KS_SIM_CHECKED="$W/sim.checked" KS_COMMON="$HERE/../common/files/common.sh"
	: > "$W/ucidb"; unset FAKE_DAY
	unset FAKE_MM FAKE_PING_FAIL FAKE_TARGET FAKE_CURL FAKE_TCP FAKE_CURL_RC
	export KS_VERSION_FILE="$W/version" KS_MIN_TIME=0 KS_FW_STATS="$W/fw" VNSTAT="$W/bin/vnstat"
	rm -rf "$W/fw"; unset FAKE_VNSTAT
	echo 0.1.0 > "$W/version"
}

collect() { sh "$HERE/files/keystone-history" "$@"; }
rpc() { sh "$HERE/files/keystone-history.rpcd" "$@"; }
valid() { printf '%s' "$1" | tr -d '\n\t' | grep -Eq '^\{("[a-z]+":(\[[^]]*\]|"[^"]*"),?)+\}$|^\{"points":\[(\[[^]]*\],?)*\],"traffic":\[(\{[^}]*\},?)*\]\}$'; }

setup
collect
eq "qmodem line" "$(cat "$W/tmp/points")" "1000000 -95 17 23.4 151 1725 B3 B3"

setup; FAKE_QMODEM=
collect
eq "no qmodem gives dashes" "$(cat "$W/tmp/points")" "1000000 - - 23.4 - - - -"

setup; FAKE_QMODEM=
cat > "$W/g5/metrics_m_4_1.json" <<'X'
{"rsrp":"-101","rsrq":"-11","sinr":"4","pci":"220","earfcn":"1300","pband":"B3","signal":"60"}
X
collect
eq "5gmodem metrics" "$(cat "$W/tmp/points")" "1000000 -101 4 23.4 220 1300 B3 B3"

setup; export FAKE_PING_FAIL=1
collect
eq "failed ping" "$(cut -d' ' -f4 "$W/tmp/points")" "-"

setup
collect
grep -q '^ping -c 1 -W 2 -I wwan0_1 8.8.8.8$' "$W/log" && ok "ping bound to wan device" || bad "ping bound to wan device: $(grep ping "$W/log")"

setup; export FAKE_TARGET=1.1.1.1
collect
grep -q -- '-I wwan0_1 1.1.1.1$' "$W/log" && ok "ping target from uci" || bad "ping target from uci"

setup; echo '{"interface":[]}' > "$W/dump2.json"; FAKE_DUMP="$W/dump2.json"
mkdir -p "$W/sys/wwan0/statistics"; echo 5 > "$W/sys/wwan0/statistics/rx_bytes"; echo 5 > "$W/sys/wwan0/statistics/tx_bytes"
collect
grep -q -- '-I wwan0 ' "$W/log" && ok "wan falls back to wwan0" || bad "wan falls back to wwan0"

setup
printf '%s\n' "$((1000000-8*86400)) -90 10 20 1 2 B1" "$((1000000-86400)) -91 11 21 1 2 B1" > "$W/tmp/points"
collect
eq "old points trimmed" "$(wc -l < "$W/tmp/points" | tr -d ' ')" "2"

setup
collect
echo 3000 > "$W/sys/wwan0_1/statistics/rx_bytes"; echo 800 > "$W/sys/wwan0_1/statistics/tx_bytes"
FAKE_NOW=1000120 collect
eq "traffic delta" "$(cat "$W/tmp/traffic.2026-11")" "2000 300"
echo 100 > "$W/sys/wwan0_1/statistics/rx_bytes"; echo 50 > "$W/sys/wwan0_1/statistics/tx_bytes"
FAKE_NOW=1000240 collect
eq "counter reset counts new bytes" "$(cat "$W/tmp/traffic.2026-11")" "2100 350"

setup
collect
[ -s "$W/etc/points" ] && ok "first run flushes" || bad "first run flushes"
rm "$W/etc/points"
FAKE_NOW=1000120 collect
[ ! -e "$W/etc/points" ] && ok "no flush within the hour" || bad "no flush within the hour"
FAKE_NOW=1003700 collect
[ -s "$W/etc/points" ] && ok "flush after an hour" || bad "flush after an hour"

setup
awk 'BEGIN{for(i=0;i<40000;i++)printf "%d -90 10 20 100 1725 B3_(1800_MHz)\n",1000000+i}' > "$W/tmp/points"
FAKE_NOW=1040000 collect
S=$(wc -c < "$W/etc/points" | tr -d ' ')
[ "$S" -le 1050000 ] && ok "flash copy capped" || bad "flash copy capped ($S)"
tail -n 1 "$W/etc/points" | grep -q '^1040000 ' && ok "cap drops oldest" || bad "cap drops oldest"

setup
printf '%s\n' "100 -90 10 20 1 2 B1" "200 -91 - 21 1 2 B_3" "300 -92 12 22 1 2 B1" > "$W/tmp/points"
echo "5 7" > "$W/tmp/traffic.2026-11"
OUT=$(echo '{"from":150,"to":300}' | rpc call history)
eq "history filters" "$OUT" '{"points":[[200,-91,null,21,1,2,"B 3"],[300,-92,12,22,1,2,"B1"]],"traffic":[{"month":"2026-11","down":5,"up":7}]}'
valid "$OUT" && ok "history json valid" || bad "history json valid"

setup
OUT=$(echo '{"from":1,"to":2}' | rpc call history)
eq "empty history" "$OUT" '{"points":[],"traffic":[]}'

setup
OUT=$(rpc call info)
eq "info" "$OUT" '{"version":"0.1.0","sources":["qmodem","ping","traffic"],"keep_days":7,"max_days":30,"ping_method":"none","active_sim":"main","plans":[]}'
FAKE_QMODEM=
OUT=$(rpc call info)
eq "info without qmodem" "$OUT" '{"version":"0.1.0","sources":["ping","traffic"],"keep_days":7,"max_days":30,"ping_method":"none","active_sim":"main","plans":[]}'

setup
case "$(rpc list)" in *'"info"'*'"history"'*'"set"'*) ok "list" ;; *) bad "list" ;; esac

setup
collect
rm "$W/etc/points"
FAKE_NOW=1000060 collect flush
[ -s "$W/etc/points" ] && ok "flush argument saves within the hour" || bad "flush argument saves within the hour"

setup
printf '%s\n' '100 -90 10 20 1 2 B1_"x\' > "$W/tmp/points"
OUT=$(echo '{"from":0,"to":200}' | rpc call history)
eq "history strips quote and backslash" "$OUT" '{"points":[[100,-90,10,20,1,2,"B1 x"]],"traffic":[]}'
setup; FAKE_QMODEM=
printf '%s\n' '{"rsrp":"-90","pband":"B3\"q\\"}' > "$W/g5/metrics_m.json"
collect
case "$(cut -d' ' -f7 "$W/tmp/points")" in *'"'*|*'\'*) bad "collector strips quote and backslash" ;; *) ok "collector strips quote and backslash" ;; esac

setup
cat > "$W/dump3.json" <<'X'
{
	"interface": [
		{
			"interface": "wan",
			"up": true,
			"l3_device": "eth1",
			"proto": "dhcp",
			"route": [
				{
					"target": "0.0.0.0",
					"mask": 0
				}
			]
		},
		{
			"interface": "wwan",
			"up": true,
			"l3_device": "rmnet_data0",
			"proto": "qmi",
			"route": []
		}
	]
}
X
FAKE_DUMP="$W/dump3.json"
collect
grep -q -- '-I rmnet_data0 ' "$W/log" && ok "modem interface preferred over ethernet wan" || bad "modem interface preferred over ethernet wan"

setup
cat > "$W/dump4.json" <<'X'
{
	"interface": [
		{
			"interface": "vpn",
			"up": true,
			"l3_device": "tun0",
			"proto": "openvpn",
			"route": [
				{
					"target": "0.0.0.0",
					"mask": 0
				}
			]
		},
		{
			"interface": "wan",
			"up": true,
			"l3_device": "eth1",
			"proto": "dhcp",
			"route": [
				{
					"target": "0.0.0.0",
					"mask": 0
				}
			]
		}
	]
}
X
FAKE_DUMP="$W/dump4.json"
collect
grep -q -- '-I eth1 ' "$W/log" && ok "tunnel skipped for default route" || bad "tunnel skipped for default route"

setup
cat > "$W/dump5.json" <<'X'
{
	"interface": [
		{
			"interface": "vpn",
			"up": true,
			"l3_device": "wg0",
			"proto": "wireguard",
			"route": [
				{
					"target": "0.0.0.0",
					"mask": 0
				}
			]
		}
	]
}
X
FAKE_DUMP="$W/dump5.json"
collect
grep -q -- '-I wwan0 ' "$W/log" && ok "only a tunnel falls back to wwan0" || bad "only a tunnel falls back to wwan0"

setup; FAKE_QMODEM=
echo '{"rsrp":"-90","pci":"7","pband":"B3"}' > "$W/g5/metrics_m.json"
touch -t 202001010000 "$W/g5/metrics_m.json"
collect
eq "stale 5gmodem metrics ignored" "$(cut -d' ' -f2,5 "$W/tmp/points")" "- -"
setup
cat "$W/cell.json" > /dev/null
echo '{"rsrp":"-90","pci":"7","pband":"B3"}' > "$W/g5/metrics_m.json"
touch -t 202001010000 "$W/g5/metrics_m.json"
collect
eq "stale 5gmodem falls through to qmodem" "$(cut -d' ' -f2,5 "$W/tmp/points")" "-95 151"

setup
export KS_MIN_TIME=1704067200
collect
[ ! -e "$W/tmp/points" ] && [ ! -e "$W/etc/points" ] && ok "bogus clock records nothing" || bad "bogus clock records nothing"
export KS_MIN_TIME=0

setup
collect
echo 9999999 > "$W/tmp/flushed"
rm "$W/etc/points"
FAKE_NOW=1000120 collect
[ -s "$W/etc/points" ] && ok "flush when the clock went backwards" || bad "flush when the clock went backwards"


setup
D=86400
printf '%s\n' "$((1000000-10*D)) -90 10 20 1 2 B1" "$((1000000-D)) -91 11 21 1 2 B1" > "$W/old"
cp "$W/old" "$W/tmp/points"
collect
eq "default keeps 7 days" "$(wc -l < "$W/tmp/points" | tr -d ' ')" "2"
setup
printf '%s\n' "$((1000000-8*D)) -90 10 20 1 2 B1" > "$W/tmp/points"
collect
eq "default drops 8 day old reading" "$(wc -l < "$W/tmp/points" | tr -d ' ')" "1"

setup; echo 14 > "$W/keep"
cp "$W/old" "$W/tmp/points"
collect
eq "keep_days 14 keeps 10 day old reading" "$(wc -l < "$W/tmp/points" | tr -d ' ')" "3"
setup; echo 7 > "$W/keep"
cp "$W/old" "$W/tmp/points"
collect
eq "keep_days 7 drops 10 day old reading" "$(wc -l < "$W/tmp/points" | tr -d ' ')" "2"

for v in 0 31 -3 abc 3.5 08 '' 99999999999999999999; do
	setup; printf '%s\n' "$v" > "$W/keep"
	cp "$W/old" "$W/tmp/points"
	collect
	eq "invalid keep_days '$v' falls back to 7" "$(wc -l < "$W/tmp/points" | tr -d ' ')" "2"
done

setup
OUT=$(echo '{"keep_days":0}' | rpc call set)
eq "set rejects 0" "$OUT" '{"error":"keep_days must be 1-30"}'
OUT=$(echo '{"keep_days":31}' | rpc call set)
eq "set rejects 31" "$OUT" '{"error":"keep_days must be 1-30"}'
OUT=$(echo '{"keep_days":"x"}' | rpc call set)
eq "set rejects text" "$OUT" '{"error":"keep_days must be 1-30"}'
OUT=$(echo '{}' | rpc call set)
eq "set rejects missing value" "$OUT" '{"error":"keep_days must be 1-30"}'
[ ! -e "$W/keep" ] && ok "rejected set writes nothing" || bad "rejected set writes nothing"

setup
printf '%s\n' "$((1000000-5*D)) -90 10 20 1 2 B1" "$((1000000-D)) -91 11 21 1 2 B1" > "$W/tmp/points"
cp "$W/tmp/points" "$W/etc/points"
OUT=$(echo '{"keep_days":3}' | rpc call set)
eq "set returns keep_days" "$OUT" '{"keep_days":3}'
eq "set stored in uci" "$(cat "$W/keep")" "3"
grep -q '^uci commit keystone-history$' "$W/log" && ok "set commits uci" || bad "set commits uci"
eq "set prunes ram copy at once" "$(wc -l < "$W/tmp/points" | tr -d ' ')" "1"
eq "set prunes flash copy at once" "$(wc -l < "$W/etc/points" | tr -d ' ')" "1"
eq "info shows new keep_days" "$(rpc call info)" '{"version":"0.1.0","sources":["qmodem","ping","traffic"],"keep_days":3,"max_days":30,"ping_method":"none","active_sim":"main","plans":[]}'

setup; echo 30 > "$W/keep"
case "$(rpc call info)" in *'"keep_days":30,"max_days":30,'*) ok "info shows 30" ;; *) bad "info shows 30" ;; esac
echo 99 > "$W/keep"
case "$(rpc call info)" in *'"keep_days":7,'*) ok "info invalid keep_days shows 7" ;; *) bad "info invalid keep_days shows 7" ;; esac

capcheck() {
	setup; echo "$1" > "$W/keep"
	awk -v n="$2" 'BEGIN{for(i=0;i<n;i++)printf "%d -90 10 20 100 1725 B3_(1800_MHz)\n",1000000+i}' > "$W/tmp/points"
	FAKE_NOW=$((1000000 + $2)) collect
	S=$(wc -c < "$W/etc/points" | tr -d ' ')
	R=$(wc -c < "$W/tmp/points" | tr -d ' ')
	[ "$S" -le "$3" ] && [ "$S" -gt $(($3 - 100)) ] && [ "$R" -le "$3" ] && ok "$4" || bad "$4 (flash $S ram $R want $3)"
}
capcheck 1 40000 1000000 "keep_days 1 cap is 1 MB"
capcheck 14 70000 2100000 "keep_days 14 cap scales to 2.1 MB"
capcheck 30 150000 4000000 "keep_days 30 cap stops at 4 MB"


setup; FAKE_QMODEM=
printf '%s\n' '{"rsrp":"-90","pband":"B3 (1800 MHz) @20 MHz"}' > "$W/g5/metrics_m.json"
collect
eq "band keeps zeros" "$(cut -d' ' -f7 "$W/tmp/points")" "B3_(1800_MHz)_@20_MHz"

setup
collect
eq "icmp method" "$(cat "$W/tmp/method")" "icmp"
eq "icmp info" "$(rpc call info | sed -n 's/.*\("ping_method":"[a-z]*"\).*/\1/p')" '"ping_method":"icmp"'
grep -q '^curl' "$W/log" && bad "curl not used when icmp works" || ok "curl not used when icmp works"

setup; export FAKE_PING_FAIL=1 FAKE_CURL=0.0734
collect
eq "tcp fallback ms" "$(cut -d' ' -f4 "$W/tmp/points")" "73"
eq "tcp method" "$(cat "$W/tmp/method")" "tcp"
eq "tcp info" "$(rpc call info | sed -n 's/.*\("ping_method":"[a-z]*"\).*/\1/p')" '"ping_method":"tcp"'
grep -q '^curl --interface wwan0_1 -o /dev/null -s -m 3 -w %{time_connect} http://1.1.1.1/$' "$W/log" && ok "curl bound to wan device" || bad "curl bound to wan device: $(grep curl "$W/log")"

setup; export FAKE_PING_FAIL=1 FAKE_CURL=0.000000
collect
eq "tcp zero is a dash" "$(cut -d' ' -f4 "$W/tmp/points")" "-"

setup; export FAKE_PING_FAIL=1
collect
eq "neither gives dash" "$(cut -d' ' -f4 "$W/tmp/points")" "-"
eq "none method" "$(cat "$W/tmp/method")" "none"

setup; export FAKE_PING_FAIL=1 FAKE_CURL=0.05 CURL="$W/bin/nocurl"
collect
eq "no curl installed" "$(cut -d' ' -f4 "$W/tmp/points")" "-"

setup
collect
collect
eq "same second written once" "$(wc -l < "$W/tmp/points" | tr -d ' ')" "1"
FAKE_NOW=1000120 collect
eq "next second written" "$(wc -l < "$W/tmp/points" | tr -d ' ')" "2"

setup
echo '{"rsrp":"-90","pci":"7","pband":"B3"}' > "$W/g5/metrics_m.json"
case "$(rpc call info)" in *'"sources":["qmodem","5gmodem","ping"'*) ok "info lists 5gmodem" ;; *) bad "info lists 5gmodem" ;; esac


setup; export FAKE_PING_FAIL=1 FAKE_CURL=0.15 FAKE_CURL_RC=28
collect
eq "tcp time taken despite curl exit 28" "$(cut -d' ' -f4 "$W/tmp/points")" "150"

setup; export FAKE_PING_FAIL=1 FAKE_CURL=0.1 FAKE_TCP=9.9.9.9
collect
grep -q 'http://9.9.9.9/$' "$W/log" && ok "tcp_target from uci" || bad "tcp_target from uci"
for v in 'a b' 'x;rm' 'http://x' ; do
	setup; export FAKE_PING_FAIL=1 FAKE_CURL=0.1 FAKE_TCP="$v"
	collect
	grep -q 'http://1.1.1.1/$' "$W/log" && ok "invalid tcp_target '$v' uses 1.1.1.1" || bad "invalid tcp_target '$v' uses 1.1.1.1"
done

setup; FAKE_QMODEM=
C=$(printf '\001')
TB=$(printf '\t')
printf '{"rsrp":"-90","pband":"B3 (1800 MHz) @20 MHz%s%s"}\n' "$C" "$TB" > "$W/g5/metrics_m.json"
grep -q "$C" "$W/g5/metrics_m.json" && ok "fixture has control chars" || bad "fixture has control chars"
collect
eq "control chars stripped, digits kept" "$(cut -d' ' -f7 "$W/tmp/points")" "B3_(1800_MHz)_@20_MHz"

setup
collect
echo 3000 > "$W/sys/wwan0_1/statistics/rx_bytes"
echo 800 > "$W/sys/wwan0_1/statistics/tx_bytes"
FAKE_NOW=1000120 collect
eq "daily first write" "$(cat "$W/tmp/daily.main")" "2026-11-20 2000 300"
echo 3500 > "$W/sys/wwan0_1/statistics/rx_bytes"
FAKE_DAY=2026-11-21 FAKE_NOW=1000240 collect
eq "daily rolls day" "$(tail -n 1 "$W/tmp/daily.main")" "2026-11-21 500 0"
eq "monthly still written" "$(cat "$W/tmp/traffic.2026-11")" "2500 300"

setup
i=1; while [ $i -le 105 ]; do printf '2026-%02d-%02d 1 1\n' $(( (i - 1) / 28 + 1 )) $(( (i - 1) % 28 + 1 )); i=$((i + 1)); done > "$W/tmp/daily.main"
collect
eq "daily cap 100" "$(wc -l < "$W/tmp/daily.main" | tr -d ' ')" 100

setup
printf '2026-11-14 100 1\n2026-11-15 10 1\n2026-11-20 20 2\n' > "$W/tmp/daily.main"
OUT=$(echo '{"sim":"main","plan":"capped","allowance_gb":50,"billing_day":15}' | rpc call set_plan)
eq "set_plan saves" "$OUT" '{"sim":"main","plan":"capped","allowance_gb":50,"billing_day":15,"period_start":"2026-11-15","period_end":"2026-12-14","down":30,"up":3}'
OUT=$(rpc call info)
case $OUT in *'"plans":[{"sim":"main","plan":"capped","allowance_gb":50,"billing_day":15,"period_start":"2026-11-15","period_end":"2026-12-14","down":30,"up":3}]}') ok "plan period sum" ;; *) bad "plan period sum ($OUT)" ;; esac
OUT=$(echo '{"sim":"main","plan":"none"}' | rpc call set_plan)
OUT=$(rpc call info)
case $OUT in *'"plans":[{"sim":"main","plan":"","allowance_gb":0,"billing_day":1,"period_start":"2026-11-01","period_end":"2026-11-30","down":130,"up":4,"since":"2026-11-14"}]}') ok "plan none uses calendar month, and says counting began on the 14th" ;; *) bad "plan none uses calendar month ($OUT)" ;; esac

setup
OUT=$(echo '{"sim":"main","plan":"unlimited","billing_day":32}' | rpc call set_plan)
case $OUT in *error*) ok "set_plan bad day" ;; *) bad "set_plan bad day ($OUT)" ;; esac
OUT=$(echo '{"sim":"main","plan":"capped","billing_day":3}' | rpc call set_plan)
case $OUT in *error*) ok "set_plan capped no allowance" ;; *) bad "set_plan capped no allowance ($OUT)" ;; esac
OUT=$(echo '{"sim":"a;b","plan":"unlimited","billing_day":3}' | rpc call set_plan)
case $OUT in *error*) ok "set_plan bad sim" ;; *) bad "set_plan bad sim ($OUT)" ;; esac
OUT=$(echo '{"sim":"main","plan":"loud","billing_day":3}' | rpc call set_plan)
case $OUT in *error*) ok "set_plan bad plan" ;; *) bad "set_plan bad plan ($OUT)" ;; esac
OUT=$(echo '{"sim":"main","plan":"unlimited","billing_day":3}' | rpc call set_plan)
case $OUT in *'"plan":"unlimited"'*) ok "set_plan unlimited no allowance" ;; *) bad "set_plan unlimited no allowance ($OUT)" ;; esac

setup
echo "5000 700" > "$W/tmp/traffic.2026-11"
collect
eq "upgrade seeds the month so far" "$(head -n 1 "$W/tmp/daily.main")" "2026-11-01 5000 700"
echo 9000 > "$W/sys/wwan0_1/statistics/rx_bytes"
FAKE_NOW=1000120 collect
case $(cat "$W/tmp/daily.main") in *"2026-11-20 "*) ok "then counts per day" ;; *) bad "then counts per day" ;; esac
eq "seeds only once" "$(grep -c 2026-11-01 "$W/tmp/daily.main")" 1
setup
collect
eq "fresh install seeds nothing" "$(grep -c 2026-11-01 "$W/tmp/daily.main")" 0

monthsum() { awk -v m="${2:-2026-11}" 'substr($1, 1, 7) == m { d += $2; u += $3 } END { printf "%.0f %.0f\n", d, u }' "$1"; }
setup; mkdir -p "$W/fw"
echo "57000000000 9500000000" > "$W/fw/traffic.sim-main.2026-11"
collect
eq "installed mid-month, the month matches the firmware" "$(monthsum "$W/tmp/daily.main")" "57000000000 9500000000"
eq "the gap is spread over the days never seen" "$(grep -c '^2026-11-' "$W/tmp/daily.main")" 20
eq "evenly" "$(grep '^2026-11-05 ' "$W/tmp/daily.main")" "2026-11-05 3000000000 500000000"
case $(rpc call info) in *'"since"'*) bad "a filled month needs no since" ;; *) ok "a filled month needs no since" ;; esac
echo 2000 > "$W/sys/wwan0_1/statistics/rx_bytes"
FAKE_NOW=1000120 collect
eq "then only new traffic is added" "$(monthsum "$W/tmp/daily.main")" "57000001000 9500000000"
eq "the monthly total follows" "$(cat "$W/tmp/traffic.2026-11")" "57000001000 9500000000"
echo "keystone-history.sim_main.billing_day=15" > "$W/ucidb"
case $(rpc call info) in *'"period_start":"2026-11-15","period_end":"2026-12-14","down":15000001000,"up":2500000000'*) ok "a billing period gets its share" ;; *) bad "a billing period gets its share ($(rpc call info))" ;; esac
setup; mkdir -p "$W/fw"
printf '2026-11-01 80000000000 9499999999\n' > "$W/tmp/daily.main"
echo "57000000000 9500000000" > "$W/fw/traffic.sim-main.2026-11"
collect
eq "a firmware count lower than ours changes nothing" "$(monthsum "$W/tmp/daily.main")" "80000000000 9499999999"
setup; mkdir -p "$W/fw"
echo "1000 1000" > "$W/fw/traffic.sim-main.2026-11"
collect
eq "a gap under a megabyte is left alone" "$(grep -c '^2026-11-' "$W/tmp/daily.main")" 1
setup; export FAKE_VNSTAT="2;wwan0_1;2026-11-20;10;5;15;1 bit/s;2026-11;38000000000;1900000000;39900000000;1 bit/s;9;9;18"; collect
eq "vnstat's month is used when the firmware has none" "$(monthsum "$W/tmp/daily.main")" "38000000000 1900000000"
setup; printf '2026-11-20 0 0\n' > "$W/tmp/daily.other"
export FAKE_VNSTAT="2;wwan0_1;2026-11-20;10;5;15;1 bit/s;2026-11;38000000000;1900000000;39900000000;1 bit/s;9;9;18"; collect
eq "but not with two SIMs, it counts the interface" "$(monthsum "$W/tmp/daily.main")" "0 0"
unset FAKE_VNSTAT

setup
printf 'keystone-history.main=main
keystone-history.main.keep_days=14
' > "$W/ucidb"
echo '{"sim":"main","plan":"capped","allowance_gb":5,"billing_day":3}' | rpc call set_plan > /dev/null
echo '{"sim":"main","plan":"none"}' | rpc call set_plan > /dev/null
eq "a plan for the SIM called main leaves the settings alone" "$(sed -n 's/^keystone-history.main=//p' "$W/ucidb")" main
eq "keep_days survives removing that plan" "$(sed -n 's/^keystone-history.main.keep_days=//p' "$W/ucidb")" 14

setup; FAKE_QMODEM=
printf '%s\n' '{"rsrp":"-93","sinr":"15","pci":"151","earfcn":"1725","pband":"B3 (1800 MHz) @20 MHz","s1band":"B1 (2100 MHz) @15 MHz","s2band":"B1 (2100 MHz) @10 MHz","s3band":"-","s4band":"-"}' > "$W/g5/metrics_m.json"
collect
eq "5gmodem bands with CA" "$(cut -d' ' -f7,8 "$W/tmp/points")" "B3_(1800_MHz)_@20_MHz B3+B1+B1"
setup; FAKE_QMODEM=
printf '{"rsrp":"-90","pband":"B3\\x\001","s1band":"n78\\ (3500 MHz)"}\n' > "$W/g5/metrics_m.json"
collect
eq "dirty band names are cleaned" "$(cut -d' ' -f8 "$W/tmp/points")" "B3x+n78"
setup
cat > "$W/band2.json" <<'X'
{
	"current_band": {
		"status": "ok",
		"cells": [
			{ "role": "pcc", "rat": "LTE", "band_name": "B3", "channel": "1725", "pci": "151" },
			{ "role": "nsa", "rat": "NR", "band_name": "N78", "channel": "636666", "pci": "22" }
		]
	}
}
X
FAKE_BAND="$W/band2.json" collect
eq "qmodem bands with NSA" "$(cut -d' ' -f7,8 "$W/tmp/points")" "B3 B3+N78"
setup; FAKE_QMODEM=
cat > "$W/mm.txt" <<'X'
modem.signal.refresh.rate                 : 60
modem.signal.lte.rssi                     : -65.00
modem.signal.lte.rsrq                     : -11.00
modem.signal.lte.rsrp                     : -97.00
modem.signal.lte.snr                      : 12.00
modem.signal.5g.rsrp                      : --
modem.signal.5g.snr                       : --
X
export FAKE_MM="$W/mm.txt"
collect
eq "modemmanager lte" "$(cut -d' ' -f2,3,5,6,7,8 "$W/tmp/points")" "-97.00 12.00 - - - -"
grep -q signal-setup "$W/log" && bad "polling already on is left alone" || ok "polling already on is left alone"
setup; FAKE_QMODEM=
sed 's/^modem.signal.5g.rsrp .*/modem.signal.5g.rsrp : -88.00/; s/^modem.signal.5g.snr .*/modem.signal.5g.snr : 20.50/' "$W/mm.txt" > "$W/mm5.txt"
export FAKE_MM="$W/mm5.txt"
collect
eq "modemmanager 5g wins" "$(cut -d' ' -f2,3 "$W/tmp/points")" "-88.00 20.50"
setup; FAKE_QMODEM=
sed 's/^modem.signal.refresh.rate .*/modem.signal.refresh.rate : 0/; s/^modem.signal.lte.rsrp .*/modem.signal.lte.rsrp : --/; s/^modem.signal.lte.snr .*/modem.signal.lte.snr : --/' "$W/mm.txt" > "$W/mm0.txt"
export FAKE_MM="$W/mm0.txt"
collect
eq "modemmanager polling off turns it on" "$(grep -c -- '--signal-setup=60' "$W/log")" 1
eq "first reading after turning it on" "$(cut -d' ' -f2,3 "$W/tmp/points")" "- -"
setup; FAKE_QMODEM=
collect
eq "no modem at all" "$(cut -d' ' -f8 "$W/tmp/points")" "-"
setup
echo "100 -90 10 20 1 2 B3 B3+B1" > "$W/tmp/points"; echo "200 -91 11 21 1 2 B3" >> "$W/tmp/points"
eq "history stays 7 values" "$(echo '{"from":0,"to":300}' | rpc call history)" '{"points":[[100,-90,10,20,1,2,"B3"],[200,-91,11,21,1,2,"B3"]],"traffic":[]}'

for f in keystone-history keystone-history.rpcd keystone-history.init; do
	sh -n "$HERE/files/$f" && ok "syntax $f" || bad "syntax $f"
done

rm -rf "$W"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
