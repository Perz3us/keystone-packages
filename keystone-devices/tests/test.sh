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
+%s) echo "${FAKE_NOW:-1800000000}" ;;
+%F) echo "${FAKE_DAY:-2026-11-20}" ;;
esac
X
cat > "$W/bin/uci" <<'X'
#!/bin/sh
eval last=\${$#}
case "$*" in
*" get "*) v=$(sed -n "s/^$last=//p" "$FAKE_UCIDB" 2>/dev/null); [ -n "$v" ] && echo "$v" || exit 1 ;;
esac
X
# nft: "list table" fails until the table is made; sets print from files the test writes
cat > "$W/bin/nft" <<'X'
#!/bin/sh
echo "nft $*" >> "$FAKE_LOG"
case "$*" in
"list table inet keystone_devices") [ -e "$FAKE_NFT_TABLE" ] ;;
"-f -") cat >> "$FAKE_LOG"; [ -n "$FAKE_NFT_BROKEN" ] && exit 1; : > "$FAKE_NFT_TABLE" ;;
"list set inet keystone_devices "*) cat "$FAKE_NFT_DIR/${5:-x}" 2>/dev/null ;;
*) exit 0 ;;
esac
X
cat > "$W/bin/iptables" <<'X'
#!/bin/sh
echo "iptables $*" >> "$FAKE_LOG"
case "$*" in
*"-nvxL KS_DEVICES"*) cat "$FAKE_IPT" 2>/dev/null ;;
*"-C FORWARD -j KS_DEVICES"*) [ -e "$FAKE_IPT_JUMP" ]; exit ;;
*"-I FORWARD 1 -j KS_DEVICES"*) : > "$FAKE_IPT_JUMP" ;;
*"-C KS_DEVICES"*) grep -qxF -- "$*" "$FAKE_IPT_RULES" 2>/dev/null; exit ;;
*"-A KS_DEVICES"*) echo "$*" | sed 's/-A KS_DEVICES/-C KS_DEVICES/' >> "$FAKE_IPT_RULES" ;;
esac
exit 0
X
cat > "$W/bin/nlbw" <<'X'
#!/bin/sh
echo "nlbw $*" >> "$FAKE_LOG"
cat "$FAKE_NLBW"
X
cat > "$W/bin/pidof" <<'X'
#!/bin/sh
[ -n "$FAKE_NLBW_RUNNING" ] && echo 123
X
cat > "$W/bin/ip" <<'X'
#!/bin/sh
cat "$FAKE_NEIGH" 2>/dev/null
X
chmod +x "$W/bin/"*

setup() {
	rm -rf "${W:?}/tmp" "${W:?}/etc" "${W:?}/nft"
	mkdir -p "$W/tmp" "$W/etc" "$W/nft"
	: > "$W/log"; : > "$W/ucidb"; : > "$W/neigh"; rm -f "$W/ipt" "$W/ipt_jump" "$W/ipt_rules" "$W/nfttable"
	printf '1 AA:BB:CC:00:00:01 192.168.1.2 tv *\n1 aa:bb:cc:00:00:02 192.168.1.3 pc *\n' > "$W/leases"
	export KS_TMP="$W/tmp" KS_ETC="$W/etc" DATE="$W/bin/date" UCI="$W/bin/uci" NFT="$W/bin/nft" IPT="$W/bin/iptables"
	export NLBW="$W/bin/nlbw" PIDOF="$W/bin/pidof" IP="$W/bin/ip" KS_LEASES="$W/leases" FAKE_LOG="$W/log" FAKE_UCIDB="$W/ucidb"
	export FAKE_NFT_TABLE="$W/nfttable" FAKE_NFT_DIR="$W/nft" FAKE_IPT="$W/ipt" FAKE_IPT_JUMP="$W/ipt_jump" FAKE_IPT_RULES="$W/ipt_rules"
	export FAKE_NLBW="$W/nlbw.json" FAKE_NEIGH="$W/neigh" KS_FW4=1
	export KS_COMMON="$HERE/../common/files/common.sh" KS_VERSION_FILE="$W/version" KS_5G="$W/g5" KS_SIM_CACHE="$W/sim" KS_SIM_CHECKED="$W/sim.checked"
	export UBUS=false FAKE_NOW=1800000000 FAKE_DAY=2026-11-20
	unset FAKE_NLBW_RUNNING FAKE_NFT_BROKEN KS_OFFLOAD
	echo 0.1.0 > "$W/version"
}

sample() { sh "$HERE/files/keystone-devices" sample; }
rpc() { sh "$HERE/files/keystone-devices.rpcd" "$@"; }
# nftset <set> "<ip> <bytes>"...: what the kernel set holds now
nftset() { s=$1; shift; printf 'table inet keystone_devices {\n\tset %s {\n\t\telements = { ' "$s" > "$W/nft/$s"; sep=; for e in "$@"; do set -- $e; printf '%s%s counter packets 1 bytes %s' "$sep" "$1" "$2" >> "$W/nft/$s"; sep=', '; done; printf ' }\n\t}\n}\n' >> "$W/nft/$s"; }
period() { cat "$W/tmp/period.$1" 2>/dev/null | sort; }

# nftables
setup
sample
has "nft table made" "$(cat "$W/log")" "nft -f -"
eq "backend nft" "$(cat "$W/tmp/backend")" nft
nftset down4 "192.168.1.2 100" "192.168.1.3 5"
nftset up4 "192.168.1.2 10"
sample
eq "first counts" "$(period 2026-11-01)" "aa:bb:cc:00:00:01 100 10
aa:bb:cc:00:00:02 5 0"
nftset down4 "192.168.1.2 250" "192.168.1.3 5"
sample
eq "only the new bytes are added" "$(period 2026-11-01 | head -n 1)" "aa:bb:cc:00:00:01 250 10"
nftset down4 "192.168.1.2 40" "192.168.1.3 5"
sample
eq "counters that start over still count" "$(period 2026-11-01 | head -n 1)" "aa:bb:cc:00:00:01 290 10"
rm "$W/nfttable"; : > "$W/log"
sample
has "table that vanished is made again" "$(cat "$W/log")" "nft -f -"
nftset down4 "192.168.1.9 7"
sample
eq "unknown address is not counted" "$(grep -c 192.168.1.9 "$W/tmp/period.2026-11-01")" 0
printf '192.168.1.9 dev br-lan lladdr aa:bb:cc:00:00:09 STALE\nfd00::9 dev br-lan lladdr aa:bb:cc:00:00:09 REACHABLE\n' > "$W/neigh"
nftset down4 "192.168.1.9 17"
nftset down6 "fd00::9 3"
sample
has "neighbour table names it, v4 and v6, from then on" "$(period 2026-11-01)" "aa:bb:cc:00:00:09 13 0"

# addresses that come and go
setup; sample; nftset down4 "192.168.1.2 100"; sample
printf '1 aa:bb:cc:00:00:02 192.168.1.3 pc *
' > "$W/leases"
nftset down4 "192.168.1.2 150"; sample
printf '1 AA:BB:CC:00:00:01 192.168.1.2 tv *
' > "$W/leases"
nftset down4 "192.168.1.2 170"; sample
eq "a device that left and came back is not counted twice" "$(period 2026-11-01 | head -n 1)" "aa:bb:cc:00:00:01 120 0"
setup; printf '192.168.1.2 dev br-lan lladdr aa:bb:cc:00:00:01 REACHABLE
fd00::2 dev br-lan lladdr aa:bb:cc:00:00:01 REACHABLE
' > "$W/neigh"; : > "$W/leases"
sample; nftset down4 "192.168.1.2 100"; nftset down6 "fd00::2 50"; sample
printf '192.168.1.2 dev br-lan lladdr aa:bb:cc:00:00:01 REACHABLE
fd00::2 dev br-lan lladdr aa:bb:cc:00:00:01 FAILED
' > "$W/neigh"
nftset down4 "192.168.1.2 110"; sample
eq "losing one address does not recount the others" "$(period 2026-11-01)" "aa:bb:cc:00:00:01 160 0"
setup; sample; nftset down4 "192.168.1.2 100"; sample
printf '1 aa:bb:cc:00:00:07 192.168.1.2 new *
' > "$W/leases"
nftset down4 "192.168.1.2 130"; sample
has "an address taken over credits only new traffic" "$(period 2026-11-01)" "aa:bb:cc:00:00:07 30 0"
setup; : > "$W/nfttable"; nftset down4 "192.168.1.2 900"; sample
eq "a table that was already counting starts from now" "$(period 2026-11-01)" ""
nftset down4 "192.168.1.2 950"; sample
eq "then counts what is new" "$(period 2026-11-01)" "aa:bb:cc:00:00:01 50 0"
setup; sample
has "addresses are forgotten after a week" "$(cat "$W/log")" "timeout 7d"

# billing period
setup; echo "keystone-history.sim_main.billing_day=15" > "$W/ucidb"
sample; nftset down4 "192.168.1.2 100"; sample
eq "billing day picks the period" "$(ls "$W/tmp" | grep period)" "period.2026-11-15"
FAKE_DAY=2026-12-15; nftset down4 "192.168.1.2 130"; sample
eq "new period starts at nothing" "$(period 2026-12-15)" "aa:bb:cc:00:00:01 30 0"
eq "old period kept" "$(period 2026-11-15)" "aa:bb:cc:00:00:01 100 0"
for d in 2027-01-15 2027-02-15; do FAKE_DAY=$d; sample; touch "$W/tmp/period.$d"; done
eq "three periods kept" "$(ls "$W/tmp" | grep -c period)" 3
[ -e "$W/tmp/period.2026-11-15" ] && bad "oldest removed" || ok "oldest removed"

# iptables (fw3)
setup; export KS_FW4=
sample
eq "backend iptables" "$(cat "$W/tmp/backend")" iptables
has "jump added" "$(cat "$W/log")" "-I FORWARD 1 -j KS_DEVICES"
has "rule per address" "$(cat "$W/ipt_rules")" "-d 192.168.1.2"
: > "$W/log"; sample
case $(cat "$W/log") in *"-A KS_DEVICES"*) bad "rules not added twice" ;; *) ok "rules not added twice" ;; esac
cat > "$W/ipt" <<'X'
Chain KS_DEVICES (1 references)
    pkts      bytes target     prot opt in     out     source               destination
      10     1000 RETURN     all  --  *      *       0.0.0.0/0            192.168.1.2
       2       50 RETURN     all  --  *      *       192.168.1.2          0.0.0.0/0
X
sample
eq "iptables counts" "$(period 2026-11-01 | head -n 1)" "aa:bb:cc:00:00:01 1000 50"

# nlbwmon
setup; export FAKE_NLBW_RUNNING=1
printf '{"columns":["mac","ip","conns","rx_bytes","rx_pkts","tx_bytes","tx_pkts"],"data":[["AA:BB:CC:00:00:01","192.168.1.2",3,500,5,40,4],["aa:bb:cc:00:00:02","192.168.1.3",1,0,0,7,1]]}' > "$W/nlbw.json"
sample
eq "backend nlbwmon" "$(cat "$W/tmp/backend")" nlbwmon
eq "nlbwmon counts" "$(period 2026-11-01)" "aa:bb:cc:00:00:01 500 40
aa:bb:cc:00:00:02 0 7"
case $(cat "$W/log") in *"nft -f"*|*iptables*) bad "no rules with nlbwmon" ;; *) ok "no rules with nlbwmon" ;; esac
rm -f "$W/tmp/run/raw"; sample
eq "a restart does not add the month again" "$(period 2026-11-01 | head -n 1)" "aa:bb:cc:00:00:01 500 40"
cp "$W/tmp/period.2026-11-01" "$W/etc/"; rm -rf "$W/tmp"; mkdir -p "$W/tmp"
cp "$W/etc/period.2026-11-01" "$W/tmp/"; sample
eq "nor does a reboot" "$(period 2026-11-01 | head -n 1)" "aa:bb:cc:00:00:01 500 40"
printf '{"columns":["mac","ip","conns","rx_bytes","rx_pkts","tx_bytes","tx_pkts"],"data":[["AA:BB:CC:00:00:01","192.168.1.2",3,600,5,40,4]]}' > "$W/nlbw.json"
sample
eq "then counts what is new" "$(period 2026-11-01 | head -n 1)" "aa:bb:cc:00:00:01 600 40"

setup; export FAKE_NLBW_RUNNING=1
printf '{"columns":["mac","ip","conns","rx_bytes","rx_pkts","tx_bytes","tx_pkts"],"data":[["00:00:00:00:00:00","0.0.0.0",3,900,5,90,4],["aa:bb:cc:00:00:01","192.168.1.2",1,10,0,7,1]]}' > "$W/nlbw.json"
sample
eq "nlbwmon traffic with no device is left out" "$(period 2026-11-01)" "aa:bb:cc:00:00:01 10 7"

# nothing works
setup; export FAKE_NFT_BROKEN=1
sample
eq "backend none" "$(cat "$W/tmp/backend")" none

# limits and storage
setup
i=1; while [ $i -le 600 ]; do echo "1 aa:bb:cc:00:$(printf '%02x:%02x' $((i / 256)) $((i % 256))) 10.0.$((i / 250)).$((i % 250)) x *"; i=$((i + 1)); done > "$W/leases"
sample
eq "tracks at most 512 devices" "$(wc -l < "$W/tmp/macs" | tr -d ' ')" 512
setup; sample; nftset down4 "192.168.1.2 100"; sample
sh "$HERE/files/keystone-devices" flush
eq "flushed to flash" "$(cat "$W/etc/period.2026-11-01")" "aa:bb:cc:00:00:01 100 0"
[ -e "$W/etc/raw" ] && bad "raw counters stay in ram" || ok "raw counters stay in ram"

# stopping
setup; sample; nftset down4 "192.168.1.2 100"; : > "$W/log"
sh "$HERE/files/keystone-devices" stop
eq "stop counts the last minute" "$(cat "$W/etc/period.2026-11-01")" "aa:bb:cc:00:00:01 100 0"
has "stop removes the nft table" "$(cat "$W/log")" "nft delete table inet keystone_devices"
setup; export KS_FW4=; sample; : > "$W/log"
sh "$HERE/files/keystone-devices" stop
has "stop removes the iptables jump" "$(cat "$W/log")" "-D FORWARD -j KS_DEVICES"
has "stop removes the iptables chain" "$(cat "$W/log")" "-X KS_DEVICES"

# ubus
setup; sample; nftset down4 "192.168.1.2 100" "192.168.1.3 20"; nftset up4 "192.168.1.3 2"; sample
OUT=$(rpc call info)
has "info backend" "$OUT" '"backend":"nft"'
has "info periods" "$OUT" '"periods":["2026-11-01"]'
has "info offload" "$OUT" '"offload":false'
export KS_OFFLOAD=1
has "offload noticed" "$(rpc call info)" '"offload":true'
OUT=$(echo '{}' | rpc call usage)
eq "usage now" "$OUT" '{"period_start":"2026-11-01","period_end":"2026-11-30","devices":[{"mac":"aa:bb:cc:00:00:01","down":100,"up":0},{"mac":"aa:bb:cc:00:00:02","down":20,"up":2}]}'
eq "usage of a period not kept" "$(echo '{"period":"2020-01-01"}' | rpc call usage)" '{"period_start":"2020-01-01","period_end":"","devices":[]}'
eq "usage refuses odd input" "$(echo '{"period":"../../etc/passwd"}' | rpc call usage)" '{"error":"period must be YYYY-MM-DD"}'
has "list" "$(rpc list)" '"usage"'

for f in keystone-devices keystone-devices.rpcd keystone-devices.init; do
	sh -n "$HERE/files/$f" && ok "syntax $f" || bad "syntax $f"
done

rm -rf "${W:?}"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
