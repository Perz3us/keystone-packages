# Shared helpers for Keystone router packages. build.sh copies this file into each
# package as /usr/share/<package>/common.sh, so packages install in any order.

KS_5G=${KS_5G:-/tmp/5gmodem}
KS_5G_REBOOT=${KS_5G_REBOOT:-/usr/share/5gmodem/reboot_modem.sh}
KS_SIM_CACHE=${KS_SIM_CACHE:-/etc/keystone/sim}
KS_SIM_CHECKED=${KS_SIM_CHECKED:-/tmp/keystone-sim.checked}
KS_UPTIME=${KS_UPTIME:-/proc/uptime}
UBUS=${UBUS:-ubus}
UCI=${UCI:-uci}
PGREP=${PGREP:-pgrep}
REBOOT=${REBOOT:-reboot}

# Mobile interface first, else the default-route device. VPN and tunnels never count.
ks_wan_dev() {
	$UBUS call network.interface dump 2>/dev/null | awk '
		function out() { if (dev != "") print dev, proto, up, def }
		/^[ \t]*"interface":/ { out(); up = 0; dev = ""; proto = "-"; def = 0; tgt = 0 }
		/"up": true/ { up = 1 }
		/"l3_device":/ { split($0, a, "\""); dev = a[4] }
		/"proto":/ { split($0, a, "\""); proto = a[4] }
		/"target": "0.0.0.0"/ { tgt = 1 }
		/"mask": 0,?$/ { if (tgt) def = 1 }
		END { out() }
	' | awk '
		$3 != 1 { next }
		$2 ~ /^(wireguard|openvpn|vpnc|l2tp|pptp)$/ || $1 ~ /^(tun|wg|tailscale)/ { next }
		$2 ~ /^(qmi|mbim|ncm|modemmanager|3g|wwan|quectel)$/ || $1 ~ /^(wwan|rmnet|qmimux|mhi_net|usb[0-9])/ { if (m == "") m = $1; next }
		$4 == 1 { if (d == "") d = $1 }
		END { print (m != "" ? m : d) }
	'
}

# Billing periods. A billing day past the end of a month falls back to its last day.
_ks_period() {
	awk -v t="$1" -v bd="$2" -v want="$3" '
		function dim(y, m) { return m == 2 ? ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0 ? 29 : 28) : (m == 4 || m == 6 || m == 9 || m == 11 ? 30 : 31) }
		function day(y, m) { return bd > dim(y, m) ? dim(y, m) : bd }
		BEGIN {
			if (bd !~ /^[0-9]+$/ || bd < 1 || bd > 31) bd = 1
			split(t, a, "-"); y = a[1] + 0; m = a[2] + 0; d = a[3] + 0
			if (d < day(y, m)) { m--; if (m < 1) { m = 12; y-- } }
			if (want == "start") { printf "%04d-%02d-%02d\n", y, m, day(y, m); exit }
			ny = y; nm = m + 1; if (nm > 12) { nm = 1; ny++ }
			e = day(ny, nm) - 1
			if (e < 1) { e = dim(y, m); ny = y; nm = m }
			printf "%04d-%02d-%02d\n", ny, nm, e
		}'
}
ks_period_start() { _ks_period "$1" "$2" start; }
ks_period_end() { _ks_period "$1" "$2" end; }

ks_qmodem_section() { $UCI -q show qmodem | sed -n 's/^qmodem\.\([^.=]*\)=modem-device$/\1/p' | head -n 1; }

# Active SIM by ICCID. A failed read keeps the last known SIM, so its usage isn't split in two.
# shortcut: with two modems only the first one's SIM is counted, revisit when multi-WAN is supported
ks_sim_key() {
	local f k= last
	f=$(find "$KS_5G" -name 'metrics_*.json' -mmin -5 2>/dev/null | sort | head -n 1)
	[ -n "$f" ] && k=$(sed -n 's/.*"iccid" *: *"\([^"]*\)".*/\1/p' "$f" | head -n 1 | tr -cd '0-9A-Za-z')
	last=$(cat "$KS_SIM_CACHE" 2>/dev/null)
	# Each QModem read sends an AT command, so ask rarely.
	if [ -z "$k" ] && [ -z "$(find "$KS_SIM_CHECKED" -mmin -5 2>/dev/null)" ] && $UBUS list qmodem >/dev/null 2>&1; then
		: > "$KS_SIM_CHECKED"
		k=$($UBUS call qmodem sim_info "{\"config_section\":\"$(ks_qmodem_section)\"}" 2>/dev/null | awk '
			/"key":/ { split($0, a, "\""); k = toupper(a[4]) }
			/"value":/ { if (k == "ICCID") { split($0, a, "\""); print a[4]; exit } }' | tr -cd '0-9A-Za-z')
	fi
	[ ${#k} -ge 6 ] && [ ${#k} -le 32 ] || k=
	if [ -n "$k" ] && [ "$k" != "$last" ]; then
		mkdir -p "${KS_SIM_CACHE%/*}" && echo "$k" > "$KS_SIM_CACHE"
	fi
	k=${k:-$last}
	echo "${k:-main}"
}

ks_json_str() {
	printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\037\177-\377')"
}

# Copy RAM state to flash at most once an hour, or now when forced.
ks_flush() {
	local tmp=$1 etc=$2 stamp=$3 force=$4 now=${5:-$(date +%s)} last= f
	[ -f "$stamp" ] && read -r last < "$stamp"
	[ "$force" = 1 ] || [ -z "$last" ] || [ $((now - last)) -ge 3600 ] || [ $((now - last)) -lt 0 ] || return 0
	mkdir -p "$etc"
	for f in "$tmp"/*; do
		[ -f "$f" ] || continue
		cmp -s "$f" "$etc/${f##*/}" && continue
		cp "$f" "$etc/${f##*/}.new" && mv "$etc/${f##*/}.new" "$etc/${f##*/}"
	done
	echo "$now" > "$stamp"
}

# Scheduled restarts skip during an upgrade or a phone call, and in the first hour after
# boot: without a clock battery the router can come back just before the restart time.
ks_restart_guarded() {
	local up
	up=$(cut -d. -f1 "$KS_UPTIME" 2>/dev/null)
	[ "${up:-0}" -ge 3600 ] || return 0
	$PGREP -f 'sbin/sysupgrade|lib/upgrade' >/dev/null 2>&1 && return 0
	case $($UBUS call fxs status 2>/dev/null | sed -n 's/.*"state": *"\([^"]*\)".*/\1/p') in
	''|idle|stopped) ;;
	*) return 0 ;;
	esac
	case $1 in
	router) $REBOOT ;;
	modem)
		if [ -x "$KS_5G_REBOOT" ]; then
			"$KS_5G_REBOOT" soft >/dev/null 2>&1
		elif $UBUS list qmodem >/dev/null 2>&1; then
			$UBUS call qmodem do_reboot "{\"config_section\":\"$(ks_qmodem_section)\",\"params\":{\"method\":\"soft\"}}" >/dev/null 2>&1
		fi ;;
	esac
	return 0
}
