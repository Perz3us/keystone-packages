#!/bin/sh

HERE=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d) || exit 1
FAIL=0
PASS=0

ok() { PASS=$((PASS+1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
has() { case $2 in *"$3"*) ok "$1" ;; *) bad "$1 (no '$3' in '$2')" ;; esac; }
hasnt() { case $2 in *"$3"*) bad "$1 ('$3' in '$2')" ;; *) ok "$1" ;; esac; }

mkdir -p "$W/bin"
cat > "$W/bin/date" <<'X'
#!/bin/sh
echo "$FAKE_NOW"
X
cat > "$W/bin/uci" <<'X'
#!/bin/sh
eval last=\${$#}
case "$*" in
*commit*) echo "commit" >> "$FAKE_LOG" ;;
*" set "*) k=${last%%=*}; grep -v "^$k=" "$FAKE_UCIDB" > "$FAKE_UCIDB.n" 2>/dev/null; echo "$last" >> "$FAKE_UCIDB.n"; mv "$FAKE_UCIDB.n" "$FAKE_UCIDB"; echo "uci set $last" >> "$FAKE_LOG" ;;
*" get "*) v=$(sed -n "s/^$last=//p" "$FAKE_UCIDB" 2>/dev/null); [ -n "$v" ] && echo "$v" || exit 1 ;;
*" show "*) sed "s/^\([^.=]*\.[^.=]*\.[^=]*\)=\(.*\)/\1='\2'/" "$FAKE_UCIDB" | grep "^$last\." ;;
esac
X
cat > "$W/bin/ping" <<'X'
#!/bin/sh
echo "ping $*" >> "$FAKE_LOG"
[ -z "$FAKE_DOWN" ] && [ -z "$FAKE_NOICMP" ] || exit 1
echo "64 bytes from 8.8.8.8: seq=0 ttl=117 time=${FAKE_MS:-30}.4 ms"
X
cat > "$W/bin/curl" <<'X'
#!/bin/sh
echo "curl $*" >> "$FAKE_LOG"
[ -z "$FAKE_DOWN" ] || { echo 0.000000; exit 7; }
echo "${FAKE_TCP:-0.041000}"
X
cat > "$W/bin/ubus" <<'X'
#!/bin/sh
case "$*" in
*"network.interface dump"*) cat "$FAKE_DUMP" ;;
"list qmodem") [ -n "$FAKE_QMODEM" ] ;;
*"call qmodem set_neighborcell"*) echo "qmodem $*" >> "$FAKE_LOG"; [ -z "$FAKE_QFAIL" ] ;;
*) exit 1 ;;
esac
X
cat > "$W/bin/bands.sh" <<'X'
#!/bin/sh
echo "bands $*" >> "$FAKE_LOG"
exit ${FAKE_BANDS_RC:-0}
X
cat > "$W/bin/atcmd.sh" <<'X'
#!/bin/sh
echo "at $*" >> "$FAKE_LOG"
printf '%s\r\n' "${FAKE_AT:-OK}"
X
cat > "$W/bin/setopt.sh" <<'X'
#!/bin/sh
echo "setopt $*" >> "$FAKE_LOG"
X
chmod +x "$W/bin/"*

dump() {
	cat > "$W/dump.json" <<X
{
	"interface": [
		{
			"interface": "wan",
			"up": true,
			"l3_device": "$1",
			"proto": "$2",
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
}

setup() {
	rm -rf "${W:?}/tmp" "${W:?}/etc" "${W:?}/proc" "${W:?}/kh" "${W:?}/sys"
	mkdir -p "$W/tmp" "$W/etc" "$W/proc" "$W/kh"
	: > "$W/ucidb"; : > "$W/log"
	dump wwan0_1 qmi
	up 600
	export KS_TMP="$W/tmp" KS_ETC="$W/etc" DATE="$W/bin/date" UCI="$W/bin/uci" FAKE_UCIDB="$W/ucidb" FAKE_LOG="$W/log"
	export KS_UPTIME="$W/proc/uptime" KS_COMMON="$HERE/../common/files/common.sh" KS_VERSION_FILE="$W/version"
	export UBUS="$W/bin/ubus" PING="$W/bin/ping" CURL="$W/bin/curl" KS_SYS="$W/sys" FAKE_DUMP="$W/dump.json" KS_HIST="$W/kh"
	export KS_BANDS="$W/bin/bands.sh" KS_ATCMD="$W/bin/atcmd.sh" KS_SETOPT="$W/bin/setopt.sh"
	export FAKE_NOW=1800000000
	unset FAKE_DOWN FAKE_NOICMP FAKE_TCP FAKE_MS FAKE_QMODEM FAKE_QFAIL FAKE_BANDS_RC FAKE_AT KS_TARGETS
	echo 0.1.0 > "$W/version"
}

up() { echo "$1.00 100.00" > "$W/proc/uptime"; }
tick() { sh "$HERE/files/keystone-cellguard" tick; }
rpc() { sh "$HERE/files/keystone-cellguard.rpcd" "$@"; }
arm() { echo "{\"pci\":\"$1\",\"arfcn\":\"$2\",\"nr\":${3:-false}}" | rpc call arm; }
info() { rpc call info; }
run_to() {
	local u=$1 end=$2
	while [ "$u" -le "$end" ]; do up "$u"; FAKE_NOW=$((1800000000 + u)) tick; u=$((u + 15)); done
}

setup
has "list names every method" "$(rpc list)" '"arm"'
eq "info before a lock" "$(info)" '{"version":"0.1.0","lock":null,"last":null}'
eq "arm refuses a missing pci" "$(echo '{"arfcn":"1725"}' | rpc call arm)" '{"error":"pci and arfcn must be numbers"}'
eq "arm refuses words" "$(arm 1x 1725)" '{"error":"pci and arfcn must be numbers"}'

setup
echo "1799999900 -92 10 25 151 1725 B3 B3" > "$W/kh/points"
out=$(arm 503 1725)
has "arm returns the lock" "$out" '"lock":{"pci":503,"earfcn":1725,"nr":false,"phase":"trial","since":1800000000}'
eq "arm saves the baseline" "$(cat "$W/etc/lock")" "1800000000 600 503 1725 lte 1 30 -92 trial"
has "baseline pings the mobile device" "$(cat "$W/log")" "-I wwan0_1 8.8.8.8"
has "a 5G lock" "$(arm 1 627264 true)" '"nr":true'

setup
arm 503 1725 >/dev/null
export FAKE_DOWN=1
run_to 615 720
hasnt "still locked under two minutes down" "$(cat "$W/log")" "bands setcelllock off"
run_to 735 735
has "no service for two minutes removes the lock" "$(cat "$W/log")" "bands setcelllock off"
has "and the 5G lock too" "$(cat "$W/log")" "bands setcelllock5g off"
has "says why" "$(info)" '"last":{"time":1800000735,"reason":"no_service","pci":503,"earfcn":1725,"nr":false}'
has "and forgets the lock" "$(info)" '"lock":null'
has "ack clears the note" "$(rpc call ack)" '"last":null'

setup
up 30
arm 503 1725 >/dev/null
export FAKE_DOWN=1
run_to 30 170
hasnt "a just-booted router is not judged" "$(cat "$W/log")" "bands"

setup
arm 503 1725 >/dev/null
run_to 615 840
eq "a working cell passes the trial" "$(cut -d' ' -f9 "$W/etc/lock")" watch
has "info shows watching" "$(info)" '"phase":"watch"'
hasnt "nothing removed" "$(cat "$W/log")" "bands"
export FAKE_DOWN=1
run_to 855 1140
hasnt "four minutes down keeps a proven lock" "$(cat "$W/log")" "bands"
run_to 1155 1155
has "five minutes down removes it" "$(info)" '"reason":"lost"'

setup
arm 503 1725 >/dev/null
export FAKE_DOWN=1
run_to 615 675
unset FAKE_DOWN
run_to 690 840
hasnt "a short drop after locking is fine" "$(cat "$W/log")" "bands"

setup
arm 503 1725 >/dev/null
for u in 615 630 645 660 675 690 705 720 735 750 765 780 795 810 825 840; do
	up $u
	if [ $((u / 15 % 3)) != 0 ]; then FAKE_DOWN=1 tick; else tick; fi
done
has "dropping more than half the pings is unstable" "$(info)" '"reason":"unstable"'

setup
FAKE_MS=20 arm 503 1725 >/dev/null
FAKE_MS=120 run_to 615 840
has "pings much slower than before" "$(info)" '"reason":"slow"'

setup
FAKE_MS=20 arm 503 1725 >/dev/null
FAKE_MS=45 run_to 615 840
has "a little slower is kept" "$(info)" '"phase":"watch"'

setup
echo "1799999900 -90 10 25 151 1725 B3 B3" > "$W/kh/points"
arm 503 1725 >/dev/null
echo "1800000700 -118 2 40 503 1725 B3 B3" >> "$W/kh/points"
run_to 615 840
has "a much weaker, unusable cell is undone" "$(info)" '"reason":"weak"'

setup
echo "1799999900 -90 10 25 151 1725 B3 B3" > "$W/kh/points"
arm 503 1725 >/dev/null
echo "1800000700 -106 2 40 503 1725 B3 B3" >> "$W/kh/points"
run_to 615 840
has "a weaker cell picked on purpose that still works is kept" "$(info)" '"phase":"watch"'

setup
echo "1799999900 -90 10 25 151 1725 B3 B3" > "$W/kh/points"
arm 503 1725 >/dev/null
echo "1800000700 -106 2 40 151 1725 B3 B3" >> "$W/kh/points"
run_to 615 840
has "a reading from the old cell is not compared" "$(info)" '"phase":"watch"'

setup
dump eth1 dhcp
arm 503 1725 >/dev/null
eq "no mobile link means no device rule" "$(cut -d' ' -f6 "$W/etc/lock")" 0
setup
arm 503 1725 >/dev/null
dump eth1 dhcp
run_to 615 735
has "pings over a backup line do not count as the cell working" "$(info)" '"reason":"no_service"'

setup
cat > "$W/ucidb" <<'X'
5gmodem.cfg01.active_modem=1-1.2
5gmodem.cfg01.at_port=/dev/ttyUSB9
5gmodem.m_1_1_2.at_port=/dev/ttyUSB2
5gmodem.m_1_1_2.celllock=1725,503
X
arm 503 1725 >/dev/null
export FAKE_DOWN=1 FAKE_BANDS_RC=1
run_to 615 735
log=$(cat "$W/log")
has "bands.sh failing falls back to AT" "$log" 'at /dev/ttyUSB2 AT+QNWLOCK="common/4g",0'
has "clears the lock 5gmodem remembers" "$log" "uci set 5gmodem.m_1_1_2.celllock="
has "and reconnects" "$log" "setopt reconnect"
has "removed" "$(info)" '"reason":"no_service"'

setup
printf '%s\n' "5gmodem.cfg01.active_modem=1-1.2" "5gmodem.cfg01.at_port=/dev/ttyUSB2" > "$W/ucidb"
arm 503 1725 >/dev/null
export FAKE_DOWN=1 FAKE_BANDS_RC=1 FAKE_AT=ERROR
run_to 615 735
has "a lock it can't remove stays watched" "$(info)" '"phase":"removing"'
run_to 750 1000
eq "retries back off instead of hammering the modem" "$(grep -c 'bands setcelllock off' "$W/log")" 3
unset FAKE_AT
run_to 1015 1200
has "and is removed on a later try" "$(info)" '"reason":"no_service"'

setup
export KS_BANDS="$W/none" FAKE_QMODEM=1
echo "qmodem.modem1=modem-device" > "$W/ucidb"
arm 503 1725 >/dev/null
export FAKE_DOWN=1
run_to 615 735
has "QModem unlock" "$(cat "$W/log")" '"config_section":"modem1","params":{"rat":"0","pci":""'
has "QModem removed" "$(info)" '"reason":"no_service"'

setup
arm 503 1725 >/dev/null
has "disarm forgets" "$(rpc call disarm)" '"lock":null'
export FAKE_DOWN=1
run_to 615 900
hasnt "nothing to watch after disarm" "$(cat "$W/log")" "bands"

setup
export KS_TARGETS=192.0.2.1
arm 503 1725 >/dev/null
has "test targets override" "$(cat "$W/log")" "192.0.2.1"

setup
echo "keystone-history.main.ping_target=1.1.1.1" > "$W/ucidb"
export FAKE_DOWN=1
arm 503 1725 >/dev/null
log=$(cat "$W/log")
has "own ping target first" "$log" "-I wwan0_1 1.1.1.1"
has "then TCP" "$log" "curl --interface wwan0_1"

setup
export FAKE_NOICMP=1
arm 503 1725 >/dev/null
eq "ping is tried once when it is blocked" "$(grep -c '^ping' "$W/log")" 1
eq "TCP gives the three baseline samples" "$(grep -c '^curl' "$W/log")" 3
unset FAKE_NOICMP
: > "$W/log"
FAKE_DOWN=1 run_to 615 615
has "ping is tried again when TCP fails" "$(cat "$W/log")" "ping -c 1"

setup
arm 503 1725 >/dev/null
( KS_GUARD_LIB=1; . "$HERE/files/keystone-cellguard"; load; FAKE_NOW=1800000100 arm 151 1725 lte; L_PCI=503 L_WALL=1800000000; revert no_service; echo "$?" ) >/dev/null
hasnt "a check started on an old lock never removes a new one" "$(cat "$W/log")" "bands"
has "the new lock stays" "$(info)" '"pci":151'

setup
export FAKE_NOICMP=1
arm 503 1725 >/dev/null
eq "ping blocked: the baseline comes from a TCP connect" "$(cut -d' ' -f7 "$W/etc/lock")" 41
has "over the mobile device" "$(cat "$W/log")" "curl --interface wwan0_1"
run_to 615 840
has "a cell that only answers TCP passes" "$(info)" '"phase":"watch"'
hasnt "and is kept" "$(cat "$W/log")" "bands"

setup
export FAKE_NOICMP=1 FAKE_TCP=0.000400
arm 503 1725 >/dev/null
eq "a TCP answer under 2 ms is a local proxy, not the internet" "$(cut -d' ' -f7 "$W/etc/lock")" -

setup
export FAKE_DOWN=1
mkdir -p "$W/sys/wwan0_1/statistics"
echo 1000 > "$W/sys/wwan0_1/statistics/rx_bytes"
arm 503 1725 >/dev/null
u=615
while [ $u -le 900 ]; do
	echo $((1000 + u)) > "$W/sys/wwan0_1/statistics/rx_bytes"
	up $u; FAKE_NOW=$((1800000000 + u)) tick
	u=$((u + 15))
done
has "no ping or TCP, but the modem still receives data: kept" "$(info)" '"phase":"watch"'
u=915
while [ $u -le 1300 ]; do up $u; FAKE_NOW=$((1800000000 + u)) tick; u=$((u + 15)); done
has "the modem stops receiving anything: removed" "$(info)" '"reason":"lost"'

setup
mkdir -p "$W/sys/wwan0_1/statistics"
grow() { local u=$1; while [ $u -le $2 ]; do echo $((5000 + u)) > "$W/sys/wwan0_1/statistics/rx_bytes"; up $u; FAKE_NOW=$((1800000000 + u)) tick; u=$((u + 15)); done; }
arm 503 1725 >/dev/null
grow 615 840
: > "$W/log"
grow 855 1500
eq "a watched lock with data flowing sends nothing" "$(cat "$W/log")" ""
eq "and stays" "$(cut -d' ' -f9 "$W/etc/lock")" watch

setup
export CURL="$W/none" FAKE_NOICMP=1
arm 503 1725 >/dev/null
eq "no curl and no ping means no baseline" "$(cut -d' ' -f7 "$W/etc/lock")" -
run_to 615 1500
hasnt "a guard that can never see the internet leaves the lock alone" "$(cat "$W/log")" "bands"

setup
export FAKE_DOWN=1
arm 503 1725 >/dev/null
unset FAKE_DOWN
run_to 615 630
export FAKE_DOWN=1
run_to 645 765
has "offline before the lock, but seen working after, still counts" "$(info)" '"reason":"no_service"'

rm -rf "$W"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
