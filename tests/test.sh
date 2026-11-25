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
*keystone.main.ping_target*) [ -n "$FAKE_TARGET" ] && echo "$FAKE_TARGET" || exit 1 ;;
esac
X
cat > "$W/bin/date" <<'X'
#!/bin/sh
case "$1" in
+%s) echo "$FAKE_NOW" ;;
+%Y-%m) echo "${FAKE_MONTH:-2026-11}" ;;
esac
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
	rm -rf "$W/tmp" "$W/etc" "$W/sys" "$W/g5" "$W/log"
	mkdir -p "$W/tmp" "$W/etc" "$W/g5" "$W/sys/wwan0_1/statistics"
	: > "$W/log"
	echo 1000 > "$W/sys/wwan0_1/statistics/rx_bytes"
	echo 500 > "$W/sys/wwan0_1/statistics/tx_bytes"
	export KS_TMP="$W/tmp" KS_ETC="$W/etc" KS_SYS="$W/sys" KS_5G="$W/g5"
	export UBUS="$W/bin/ubus" PING="$W/bin/ping" UCI="$W/bin/uci" DATE="$W/bin/date"
	export FAKE_LOG="$W/log" FAKE_CELL="$W/cell.json" FAKE_BAND="$W/band.json" FAKE_DUMP="$W/dump.json"
	export FAKE_NOW=1000000 FAKE_QMODEM=1
	unset FAKE_PING_FAIL FAKE_TARGET
	export KS_VERSION_FILE="$W/version" KS_MIN_TIME=0
	echo 0.1.0 > "$W/version"
}

collect() { sh "$HERE/files/keystone-collect" "$@"; }
rpc() { sh "$HERE/files/keystone.rpcd" "$@"; }
valid() { printf '%s' "$1" | tr -d '\n\t' | grep -Eq '^\{("[a-z]+":(\[[^]]*\]|"[^"]*"),?)+\}$|^\{"points":\[(\[[^]]*\],?)*\],"traffic":\[(\{[^}]*\},?)*\]\}$'; }

setup
collect
eq "qmodem line" "$(cat "$W/tmp/points")" "1000000 -95 17 23.4 151 1725 B3"

setup; FAKE_QMODEM=
collect
eq "no qmodem gives dashes" "$(cat "$W/tmp/points")" "1000000 - - 23.4 - - -"

setup; FAKE_QMODEM=
cat > "$W/g5/metrics_m_4_1.json" <<'X'
{"rsrp":"-101","rsrq":"-11","sinr":"4","pci":"220","earfcn":"1300","pband":"B3","signal":"60"}
X
collect
eq "5gmodem metrics" "$(cat "$W/tmp/points")" "1000000 -101 4 23.4 220 1300 B3"

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
[ "$S" -le 1000000 ] && ok "flash copy capped" || bad "flash copy capped ($S)"
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
eq "info" "$OUT" '{"version":"0.1.0","sources":["qmodem","ping","traffic"]}'
FAKE_QMODEM=
OUT=$(rpc call info)
eq "info without qmodem" "$OUT" '{"version":"0.1.0","sources":["ping","traffic"]}'

setup
case "$(rpc list)" in *'"info"'*'"history"'*) ok "list" ;; *) bad "list" ;; esac

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


for f in keystone-collect keystone.rpcd keystone-helper.init; do
	sh -n "$HERE/files/$f" && ok "syntax $f" || bad "syntax $f"
done

rm -rf "$W"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
