#!/bin/sh

HERE=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d) || exit 1
FAIL=0
PASS=0

ok() { PASS=$((PASS+1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
has() { case $2 in *"$3"*) ok "$1" ;; *) bad "$1 (no '$3' in '$2')" ;; esac; }

mkdir -p "$W/bin"
cat > "$W/bin/date" <<'X'
#!/bin/sh
case "$1" in
+%s) echo "$FAKE_NOW" ;;
+%F) echo "${FAKE_DAY:-2026-11-20}" ;;
esac
X
cat > "$W/bin/uci" <<'X'
#!/bin/sh
eval last=\${$#}
case "$*" in
*commit*) echo "commit" >> "$FAKE_LOG" ;;
*" set "*|"set "*) k=${last%%=*}; grep -v "^$k=" "$FAKE_UCIDB" > "$FAKE_UCIDB.n" 2>/dev/null; echo "$last" >> "$FAKE_UCIDB.n"; mv "$FAKE_UCIDB.n" "$FAKE_UCIDB" ;;
*" get "*) v=$(sed -n "s/^$last=//p" "$FAKE_UCIDB" 2>/dev/null); [ -n "$v" ] && echo "$v" || exit 1 ;;
*" show "*) cat "$FAKE_UCIDB" ;;
esac
X
cat > "$W/bin/ping" <<'X'
#!/bin/sh
echo "ping $*" >> "$FAKE_LOG"
case "$*" in *-I*) [ -z "$FAKE_DOWN" ] ;; *) [ -z "$FAKE_DOWN" ] || [ -n "$FAKE_FAILOVER" ] ;; esac || exit 1
echo "64 bytes from 8.8.8.8: seq=0 ttl=117 time=23.4 ms"
X
cat > "$W/bin/curl" <<'X'
#!/bin/sh
echo "${FAKE_TCP:-0.000000}"
exit 0
X
cat > "$W/bin/ubus" <<'X'
#!/bin/sh
case "$*" in
*"network.interface dump"*) cat "$FAKE_DUMP" ;;
*"keystone.history info"*) cat "$FAKE_HIST" 2>/dev/null ;;
*) exit 1 ;;
esac
X
cat > "$W/bin/ip" <<'X'
#!/bin/sh
cat "$FAKE_NEIGH" 2>/dev/null
X
chmod +x "$W/bin/"*
cat > "$W/dump.json" <<'X'
{
	"interface": [
		{
			"interface": "wwan",
			"up": true,
			"l3_device": "wwan0_1",
			"proto": "qmi",
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

setup() {
	rm -rf "${W:?}/tmp" "${W:?}/etc" "${W:?}/proc"
	mkdir -p "$W/tmp" "$W/etc" "$W/proc"
	: > "$W/ucidb"; : > "$W/log"
	echo "500.00 400.00" > "$W/proc/uptime"
	echo "boot-a" > "$W/proc/boot_id"
	export KS_TMP="$W/tmp" KS_ETC="$W/etc" DATE="$W/bin/date" UCI="$W/bin/uci" FAKE_UCIDB="$W/ucidb" FAKE_LOG="$W/log"
	export KS_UPTIME="$W/proc/uptime" KS_BOOT_ID="$W/proc/boot_id" KS_MIN_TIME=1704067200
	export KS_SIM_CACHE="$W/sim" KS_SIM_CHECKED="$W/sim.checked" KS_COMMON="$HERE/../common/files/common.sh" KS_VERSION_FILE="$W/version"
	export FAKE_NOW=1800000000
	export UBUS="$W/bin/ubus" PING="$W/bin/ping" CURL="$W/bin/curl" IP="$W/bin/ip" FAKE_DUMP="$W/dump.json"
	export FAKE_HIST="$W/hist.json" FAKE_NEIGH="$W/neigh" KS_LEASES="$W/leases" KS_HIST="$W/kh" KS_SYS="$W/sys"
	rm -f "${W:?}/hist.json" "${W:?}/neigh" "${W:?}/leases" "${W:?}/kh/points"
	mkdir -p "$W/kh" "$W/sys/wwan0"
	echo 5 > "$W/sys/wwan0/ifindex"
	unset FAKE_DOWN FAKE_FAILOVER FAKE_TCP FAKE_DAY
	unset KS_MAX_EVENTS
	echo 0.1.0 > "$W/version"
}

lib() { KS_ALERTS_LIB=1; . "$HERE/files/keystone-alerts"; unset KS_ALERTS_LIB; }
rpc() { sh "$HERE/files/keystone-alerts.rpcd" "$@"; }
# bulk <n> <detail>: write n events straight into the store
bulk() { awk -v n="$1" -v d="$2" 'BEGIN { for (i = 1; i <= n; i++) printf "%d\tdevice\t1800000000\t-\t1\tboot-a\t500\t%s\n", i, d }' > "$W/tmp/events"; echo $(($1 + 1)) > "$W/tmp/next_id"; }
ids() { cut -f1 "$W/tmp/events" | tr '\n' ' ' | sed 's/ $//'; }

setup; lib
eq "ids rise" "$(ev_add internet - '{}'; ev_add device - '{}'; ev_add data - '{}')" "1
2
3"
rpc call clear >/dev/null
eq "ids survive clear" "$(ev_add internet - '{}')" 4

setup; export KS_MAX_EVENTS=5; lib
for i in 1 2 3 4 5 6 7; do ev_add device - '{}' >/dev/null; done
ev_trim
eq "trim count" "$(ids)" "3 4 5 6 7"

setup; unset KS_MAX_EVENTS; lib
FAKE_NOW=$((1800000000 - 31 * 86400)) ev_add device - '{}' >/dev/null
ev_add device - '{}' >/dev/null
ev_trim
eq "trim age" "$(ids)" "2"

setup; lib
FAKE_NOW=1000 ev_add internet - '{}' >/dev/null
ev_trim
eq "trim age keeps unset-clock events" "$(ids)" "1"

setup; lib
ev_add internet - '{"drops":1}' >/dev/null
ev_end 1 1800000060
eq "ev_end" "$(cut -f4 "$W/tmp/events")" 1800000060

setup; export KS_MAX_EVENTS=1000; lib
bulk 250 '{"mac":"aa"}'
OUT=$(echo '{"since":0}' | rpc call events)
eq "events paging first page" "$(printf '%s' "$OUT" | grep -o '"id":' | wc -l | tr -d ' ')" 100
has "events paging newest" "$OUT" '"newest":250'
OUT=$(echo '{"since":200}' | rpc call events)
eq "events paging last page" "$(printf '%s' "$OUT" | grep -o '"id":' | wc -l | tr -d ' ')" 50
has "events not trimmed" "$OUT" '"trimmed":false'

setup; lib
bulk 60 '{}'
sed -i '1,49d' "$W/tmp/events"
has "events trimmed" "$(echo '{"since":10}' | rpc call events)" '"trimmed":true'
has "events since oldest-1 not trimmed" "$(echo '{"since":49}' | rpc call events)" '"trimmed":false'
has "events since 0 not trimmed" "$(echo '{"since":0}' | rpc call events)" '"trimmed":false'

setup; lib
FAKE_NOW=1000 ev_add internet - '{}' >/dev/null
OUT=$(echo '{"since":0}' | rpc call events)
has "events approx" "$OUT" '"approx":true'
has "events end null" "$OUT" '"end":null'

setup
OUT=$(rpc call info)
has "info defaults internet buzz" "$OUT" '"internet":{"mode":"buzz"}'
has "info defaults signal log" "$OUT" '"signal":{"mode":"log","rsrp_below":-110}'
has "info defaults data" "$OUT" '"data":{"mode":"buzz","warn_pct":80,"fairuse_pct":90}'
has "info empty newest" "$OUT" '"newest":0'

setup
OUT=$(echo '{"internet":{"mode":"loud"}}' | rpc call set)
has "set bad mode" "$OUT" error
OUT=$(echo '{"signal":{"mode":"buzz","rsrp_below":-200}}' | rpc call set)
has "set bad rsrp" "$OUT" error
OUT=$(echo '{"internet":{"mode":"off"},"signal":{"mode":"buzz","rsrp_below":-112}}' | rpc call set)
has "set saves" "$(rpc call info)" '"internet":{"mode":"off"}'
has "set saves threshold" "$(rpc call info)" '"signal":{"mode":"buzz","rsrp_below":-112}'

setup; export KS_MAX_EVENTS=5000; lib
bulk 1200 '{"mac":"aa:bb:cc:dd:ee:ff","ip":"192.168.100.200","name":"some-long-device-name"}'
sh "$HERE/files/keystone-alerts" flush
SZ=$(wc -c < "$W/etc/events" | tr -d ' ')
[ "$SZ" -le 100000 ] && [ "$SZ" -gt 90000 ] && ok "flush size ($SZ)" || bad "flush size ($SZ)"
eq "flush keeps next_id" "$(cat "$W/etc/next_id")" 1201

# at <seconds>: move wall clock and uptime together, then tick
at() { echo "$((1000 + $1)).00 1.00" > "$W/proc/uptime"; FAKE_NOW=$((1800000000 + $1)); sh "$HERE/files/keystone-alerts" tick; }
# clock <uptime> <wall clock>: move them apart, then tick
clock() { echo "$1.00 1.00" > "$W/proc/uptime"; FAKE_NOW=$2; sh "$HERE/files/keystone-alerts" tick; }
ev() { awk -F '\t' -v t="$1" -v f="$2" '$2 == t { print $f }' "$W/tmp/events" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
opt() { echo "keystone-alerts.$1=$2" >> "$W/ucidb"; }
# powercut: RAM state is gone, flash stays
powercut() { mv "$W/tmp" "$W/lost.$PASS.$FAIL"; mkdir "$W/tmp"; echo boot-b > "$W/proc/boot_id"; }

# internet
setup; at 0
export FAKE_DOWN=1
at 30; at 60
eq "two failures are not an outage" "$(ev internet 1)" ""
at 90
eq "down after 3, from the first failure" "$(ev internet 3)" 1800000030
eq "outage open" "$(ev internet 4)" -
unset FAKE_DOWN
at 120
eq "one success is not up yet" "$(ev internet 4)" -
at 150
eq "up after 2, from the first success" "$(ev internet 4)" 1800000120
export FAKE_DOWN=1; at 180; at 210; at 240
eq "drop within 2 min merges" "$(ev internet 1)" 1
eq "merged outage reopens" "$(ev internet 4)" -
eq "merged drops counted" "$(ev internet 8)" '{"drops":2}'
unset FAKE_DOWN; at 270; at 300
export FAKE_DOWN=1; at 450; at 480; at 510
eq "later drop is a new outage" "$(ev internet 1)" "1 2"

setup; at 0; export FAKE_DOWN=1 FAKE_FAILOVER=1
at 30; at 60; at 90; at 120
eq "failover line counts as up" "$(ev internet 1)" ""
setup; at 0; export FAKE_DOWN=1 FAKE_TCP=0.050000
at 30; at 60; at 90; at 120
eq "blocked ping falls back to tcp" "$(ev internet 1)" ""
setup; export FAKE_DOWN=1
at 0; at 30; at 60; at 90
eq "never seen up: no outage" "$(ev internet 1)" ""
setup; : > "$W/tmp/ever_up"; export FAKE_DOWN=1
for s in -990 -960 -930 -900 -870; do at $s; done
eq "boot grace" "$(ev internet 1)" ""
for s in -600 -570 -540; do at $s; done
eq "outage that starts at boot" "$(ev internet 1)" 1
setup; opt internet.mode off; at 0; export FAKE_DOWN=1; at 30; at 60; at 90
eq "mode off logs nothing" "$(ev internet 1)" ""
setup; at 0; export FAKE_DOWN=1; at 30; at 60; at 90; opt internet.mode off; at 120
eq "switching off closes the open outage" "$(ev internet 4)" 1800000120

setup; at 0; sh "$HERE/files/keystone-alerts" flush; export FAKE_DOWN=1; at 30; at 60; at 90
eq "an outage reaches flash at once" "$(cut -f2 "$W/etc/events" 2>/dev/null)" internet
unset FAKE_DOWN; at 120; at 150
eq "and so does its end" "$(cut -f4 "$W/etc/events")" 1800000120

# signal
sig() { echo "$((1800000000 + $1)) $2 10 20 1 1 B3" >> "$W/kh/points"; at "$1"; }
setup; sig 0 -111; sig 240 -111
eq "low for 4 min is nothing" "$(ev signal 1)" ""
sig 300 -111
eq "low for 5 min" "$(ev signal 8)" '{"rsrp":-111,"threshold":-110}'
sig 420 -108; sig 800 -108
eq "just above is not recovered" "$(ev signal 4)" -
sig 900 -106; sig 1100 -106
eq "recovered too briefly" "$(ev signal 4)" -
sig 1200 -106
eq "recovered" "$(ev signal 4)" 1800001200
setup; sig 0 -111; sig 200 -100; sig 300 -111; sig 500 -111
eq "low must be continuous" "$(ev signal 1)" ""
setup; sig 0 -; sig 300 -; sig 600 -
eq "no reading" "$(ev signal 1)" ""
setup; sig 0 -111; at 400; at 800
eq "stale reading ignored" "$(ev signal 1)" ""

# devices
setup
printf '1 AA:bb:cc:00:00:01 192.168.1.2 tv *\n' > "$W/leases"
printf '192.168.1.3 dev br-lan lladdr aa:bb:cc:00:00:02 REACHABLE\n10.0.0.1 dev wwan0_1 lladdr aa:bb:cc:00:00:99 REACHABLE\n' > "$W/neigh"
at 0
eq "first run is the baseline" "$(ev device 1)" ""
printf '1 aa:bb:cc:00:00:03 192.168.1.4 my"pc *\n' >> "$W/leases"
at 30; at 60
eq "new device once" "$(ev device 8)" '{"mac":"aa:bb:cc:00:00:03","ip":"192.168.1.4","name":"my\"pc"}'
printf '1 aa:bb:cc:00:00:04 192.168.1.5 * *\n' >> "$W/leases"; at 90
has "no hostname" "$(ev device 8)" '"ip":"192.168.1.5","name":""}'
printf '192.168.1.9 dev br-lan lladdr aa:bb:cc:00:00:05 FAILED\n' >> "$W/neigh"; at 120
eq "failed neighbour ignored" "$(ev device 1)" "1 2"
eq "wan neighbour ignored" "$(grep -c 00:99 "$W/tmp/known_macs")" 0
printf '1 aa:bb:cc:00:00:03 192.168.1.4 pc *\n' > "$W/leases"; at 150
eq "returning device is not new" "$(ev device 1)" "1 2"
setup; : > "$W/leases"; at 0
for i in 1 2 3 4 5 6 7 8 9; do echo "1 aa:bb:cc:00:01:0$i 192.168.1.$i x *"; done > "$W/leases"; at 30
eq "at most 5 new devices at once" "$(ev device 1)" "1 2 3 4 5"
eq "the rest are remembered quietly" "$(wc -l < "$W/tmp/known_macs" | tr -d ' ')" 9
setup; opt device.mode off; : > "$W/leases"; at 0; printf '1 aa:bb:cc:00:00:03 192.168.1.4 x *\n' > "$W/leases"; at 30
eq "device off still learns" "$(ev device 1)-$(cat "$W/tmp/known_macs")" "-aa:bb:cc:00:00:03"

# data
hist() { printf '{"version":"1","active_sim":"main","plans":[{"sim":"old","plan":"capped","allowance_gb":1,"billing_day":1,"period_start":"2026-11-01","period_end":"2026-11-30","down":9000000000,"up":0},{"sim":"main","plan":"%s","allowance_gb":%s,"billing_day":1,"period_start":"2026-11-01","period_end":"2026-11-30","down":%s,"up":0}]}\n' "$1" "$2" "$3" > "$W/hist.json"; }
setup; export FAKE_DAY=2026-11-29; hist capped 10 8100000000; at 0; at 400; at 800
eq "warn once" "$(ev data 8)" '{"sim":"main","level":"warn","pct":81,"runs_out":""}'
hist capped 10 10100000000; at 1200; at 1600
has "then full" "$(ev data 8)" '"level":"full","pct":101'
eq "full once" "$(ev data 1)" "1 2"
hist capped 20 18500000000; at 2000
eq "bigger allowance warns again" "$(ev data 1)" "1 2 3"
setup; export FAKE_DAY=2026-11-29; hist capped 10 12000000000; at 0; at 400
eq "already full: no extra warn" "$(ev data 1)" 1
setup; export FAKE_DAY=2026-11-29; hist fairuse 100 91000000000; at 0
has "fair use" "$(ev data 8)" '"level":"fairuse","pct":91'
setup; export FAKE_DAY=2026-11-29; hist fairuse 100 89000000000; at 0
eq "fair use below" "$(ev data 1)" ""
setup; export FAKE_DAY=2026-11-29; hist unlimited 0 999000000000; at 0
eq "unlimited" "$(ev data 1)" ""
setup; export FAKE_DAY=2026-11-05; hist capped 10 4000000000; at 0
eq "pace" "$(ev data 8)" '{"sim":"main","level":"pace","pct":40,"runs_out":"2026-11-13"}'
setup; export FAKE_DAY=2026-11-02; hist capped 10 2000000000; at 0
eq "pace waits for day 3" "$(ev data 1)" ""
setup; export FAKE_DAY=2026-11-15; hist capped 10 4000000000; at 0
eq "on pace" "$(ev data 1)" ""
setup; export FAKE_DAY=2026-11-29; hist capped 10 8100000000; awk '{ gsub(/,/, ",\n"); gsub(/":/, "\": "); print }' "$W/hist.json" > "$W/h2"; mv "$W/h2" "$W/hist.json"; at 0
eq "pretty-printed reply" "$(ev data 1)" 1
setup; opt data.warn_pct abc; export FAKE_DAY=2026-11-29; hist capped 10 8100000000; at 0
eq "bad setting falls back" "$(ev data 1)" 1
has "info json stays valid" "$(rpc call info)" '"warn_pct":80'
setup; export FAKE_DAY=2026-11-29; hist capped 10 9900000000; clock 900 1000
eq "data waits for the clock" "$(ev data 1)" ""
setup; at 0
eq "no keystone-history reply" "$(ev data 1)" ""

# restarts
setup; at 0
eq "first run is not a restart" "$(ev restart 1)" ""
echo boot-b > "$W/proc/boot_id"; at 30; at 60
eq "router restart" "$(ev restart 8)" '{"what":"router"}'
setup; at 0; echo 9 > "$W/sys/wwan0/ifindex"; at 30; at 60
eq "modem restart" "$(ev restart 8)" '{"what":"modem"}'
setup; at 0; echo 9 > "$W/sys/wwan0/ifindex"; powercut; at 30
eq "router restart is not also a modem restart" "$(ev restart 8)" '{"what":"router"}'

# clock
setup; : > "$W/leases"; export FAKE_DOWN=1; clock 500 1790000000
printf '1 aa:bb:cc:00:00:03 192.168.1.4 x *\n' > "$W/leases"; clock 530 1790000030
eq "offline since boot: time is approximate" "$(ev device 3)-$(ev device 5)" "1790000030-0"
unset FAKE_DOWN; clock 560 1800000060
eq "clock jump corrects earlier events" "$(ev device 3)-$(ev device 5)" "1800000030-1"
setup; : > "$W/leases"; at 0; printf '1 aa:bb:cc:00:00:03 192.168.1.4 x *\n' > "$W/leases"; at 30; at 200
eq "online two minutes: clock trusted" "$(ev device 5)" 1
setup; at 0; export FAKE_DOWN=1; at 30; at 60; at 90; unset FAKE_DOWN; at 120; at 150
clock 1180 1800005180
eq "jump moves start and end" "$(ev internet 3) $(ev internet 4)" "1800005030 1800005120"

# power loss
setup; at 0; export FAKE_DOWN=1; at 30; at 60; at 90; sh "$HERE/files/keystone-alerts" flush
powercut
sh "$HERE/files/keystone-alerts" restore
eq "ids jump after a restore" "$(cat "$W/tmp/next_id")" 1002
unset FAKE_DOWN; at 3000; at 3030
eq "outage through a reboot closes when back" "$(ev internet 4)" 1800003000
sh "$HERE/files/keystone-alerts" restore
eq "restore does nothing while running" "$(cat "$W/tmp/next_id")" 1003
eq "run state never reaches flash" "$(ls "$W/etc" | grep -c run)" 0

# key and feed
sha() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
N=00112233445566778899aabbccddeeff
# feed <since> <key> [nonce]: ask the way the app does
feed() { echo "{\"since\":$1,\"nonce\":\"${3:-$N}\",\"proof\":\"$(sha "$2:q:${3:-$N}:$1:$2")\"}" | rpc call feed; }
# body <reply>: the signed part, unescaped
body() { printf '%s' "$1" | sed 's/^{"body":"//; s/","sig":"[0-9a-f]*"}$//; s/\\"/"/g; s/\\\\/\\/g'; }
setup; at 0
eq "no key yet: feed says nothing" "$(feed 0 "")" "{}"
eq "no key yet: no id" "$(rpc call info | sed -n 's/.*"key_id":"\([^"]*\)".*/\1/p')" ""
K=$(rpc call pair | sed -n 's/.*"key":"\([0-9a-f]*\)".*/\1/p')
eq "key is 32 hex" "${#K}" 32
eq "pairing again gives the same key" "$(rpc call pair | sed -n 's/.*"key":"\([0-9a-f]*\)".*/\1/p')" "$K"
eq "key is private" "$(ls -l "$W/etc/key" | cut -c1-10)" "-rw-------"
has "info names the key without showing it" "$(rpc call info)" "\"key_id\":\"$(sha "$K" | cut -c1-8)\""
case $(rpc call info) in *"$K"*) bad "info leaks the key" ;; *) ok "info leaks the key" ;; esac
printf '1 aa:bb:cc:00:00:03 192.168.1.4 my"p\\c *\n' > "$W/leases"; at 30
hist capped 10 8100000000; FAKE_DAY=2026-11-29
echo "1800000030 -97 10 20 1 1 B3" > "$W/kh/points"
OUT=$(feed 0 "$K"); B=$(body "$OUT")
has "feed has events" "$B" '"name":"my\"p\\c"'
has "feed has settings" "$B" '"internet":{"mode":"buzz"}'
has "feed has newest" "$B" '"newest":1'
has "feed has state" "$B" '"online":true,"rsrp":-97,"sinr":10,"band":"B3","bands":null,"plan":'
has "feed has the active plan" "$B" '"plan":{"sim":"main","plan":"capped","allowance_gb":10'
eq "feed signature" "$(printf '%s' "$OUT" | sed 's/.*"sig":"//; s/"}$//')" "$(sha "$K:a:$N:$B:$K")"
eq "feed is one line" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" 1
echo "1800000030 -97 10 20 1 1 B3_(1800_MHz)_@20_MHz B3+B1+B1" > "$W/kh/points"
has "feed has the bands in use" "$(body "$(feed 0 "$K")")" '"rsrp":-97,"sinr":10,"band":"B3 (1800 MHz) @20 MHz","bands":["B3","B1","B1"],"plan":'
echo "1800000030 -97.00 12.50 20 - - - -" > "$W/kh/points"
has "dashes read as null" "$(body "$(feed 0 "$K")")" '"rsrp":-97,"sinr":12,"band":null,"bands":null,"plan":'
printf '%s\n' '1800000030 -97 99 20 1 1 B3"\x B"3+B\1' > "$W/kh/points"
B=$(body "$(feed 0 "$K")")
has "odd bands are cleaned" "$B" '"sinr":null,"band":"B3x","bands":["B3","B1"]'
eq "wrong key" "$(feed 0 00000000000000000000000000000000)" "{}"
eq "proof is for this question only" "$(echo "{\"since\":1,\"nonce\":\"$N\",\"proof\":\"$(sha "$K:q:$N:0:$K")\"}" | rpc call feed)" "{}"
eq "short nonce" "$(feed 0 "$K" abcd)" "{}"
eq "nonce with shell in it" "$(echo '{"since":0,"nonce":"$(reboot)aaaaaaaaaaaaaaaaaaaaaaa","proof":"x"}' | rpc call feed)" "{}"
eq "no arguments" "$(echo '{}' | rpc call feed)" "{}"
eq "garbage" "$(echo 'x' | rpc call feed)" "{}"
eq "huge since" "$(feed 99999999999999999999 "$K")" "{}"
echo "1799990000 -97 10 20 1 1 B3" > "$W/kh/points"; mv "$W/hist.json" "$W/hist.old"
has "old reading, no plan" "$(body "$(feed 0 "$K")")" '"rsrp":null,"sinr":null,"band":null,"bands":null,"plan":null'
export FAKE_DOWN=1; at 60; at 90; at 120
has "feed while down" "$(body "$(feed 0 "$K")")" '"online":false'
sh "$HERE/files/keystone-alerts" flush
powercut; sh "$HERE/files/keystone-alerts" restore
[ -e "$W/tmp/key" ] && bad "key copied to ram" || ok "key stays out of ram"
has "still down after a power cut" "$(body "$(feed 0 "$K")")" '"online":false'
mv "$W/tmp/run/net" "$W/net.old"
has "before the first check: state unknown" "$(body "$(feed 0 "$K")")" '"online":null'
rpc call reset_key >/dev/null
K2=$(rpc call pair | sed -n 's/.*"key":"\([0-9a-f]*\)".*/\1/p')
[ "$K" != "$K2" ] && [ "${#K2}" = 32 ] && ok "reset makes a new key" || bad "reset makes a new key"
eq "old key stops working" "$(feed 0 "$K")" "{}"
case $(feed 0 "$K2") in *'"body"'*) ok "new key works" ;; *) bad "new key works" ;; esac
grep -A6 '"unauthenticated"' "$HERE/files/keystone-alerts.acl.json" | grep -q '"keystone.alerts": \[ "feed" \]' && ok "no-login access is feed only" || bad "no-login access is feed only"
eq "no other no-login method" "$(grep -c '"feed"' "$HERE/files/keystone-alerts.acl.json")" 1
unset FAKE_DAY

for f in keystone-alerts keystone-alerts.rpcd keystone-alerts.init; do
	sh -n "$HERE/files/$f" && ok "syntax $f" || bad "syntax $f"
done

rm -rf "${W:?}"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
