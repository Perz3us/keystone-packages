#!/bin/sh
# Builds the packages without the OpenWrt SDK: they are shell scripts, so this only lays
# out the files and packs them. Needs apk-tools 3 (apk mkpkg), e.g. on Alpine.
# Same layout as each package's Makefile and as build.sh, which CI uses with the SDK.
# shortcut: the file layout lives here, in build.sh and in each Makefile; fold them into
# one list if a package with compiled code ever joins.
#   sh pack.sh [package]   ->   dist/<package>-<version>.apk and dist/<package>_<version>_all.ipk
set -e
# Files must belong to root inside the package: run as root (wsl -u root).
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/dist"
mkdir -p "$OUT"

if [ -n "$1" ]; then dirs=$1; else
	dirs=
	for m in "$HERE"/*/Makefile; do dirs="$dirs $(basename "$(dirname "$m")")"; done
fi

script() {
	# script <package> <post-install|post-upgrade|pre-deinstall>
	printf '#!/bin/sh\n'
	[ "$2" = post-upgrade ] && printf 'export PKG_UPGRADE=1\n'
	[ "$2" = pre-deinstall ] || printf '[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0\n'
	printf '[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0\n. ${IPKG_INSTROOT}/lib/functions.sh\nexport root="${IPKG_INSTROOT}"\nexport pkgname="%s"\n' "$1"
	if [ "$2" = pre-deinstall ]; then
		printf 'default_prerm\n[ -n "$IPKG_INSTROOT" ] || {\n\t/etc/init.d/%s stop\n\t/etc/init.d/%s disable\n}\nexit 0\n' "$1" "$1"
	else
		printf 'add_group_and_user\ndefault_postinst\n[ -n "$IPKG_INSTROOT" ] || {\n\t/etc/init.d/rpcd reload\n\t/etc/init.d/%s enable\n\t/etc/init.d/%s restart\n}\nexit 0\n' "$1" "$1"
	fi
}

for P in $dirs; do
	V=$(sed -n 's/^PKG_VERSION:=//p' "$HERE/$P/Makefile")
	R=$(sed -n 's/^PKG_RELEASE:=//p' "$HERE/$P/Makefile")
	T=$(sed -n 's/^ *TITLE:=//p' "$HERE/$P/Makefile")
	D=$(sed -n 's/^ *DEPENDS:=//p' "$HERE/$P/Makefile" | tr -d '+')
	F="$HERE/$P/files"
	W=$(mktemp -d)
	root="$W/root"
	install -d "$root/usr/sbin" "$root/etc/init.d" "$root/usr/libexec/rpcd" "$root/usr/share/rpcd/acl.d" "$root/usr/share/$P" "$root/lib/apk/packages"
	install -m755 "$F/$P" "$root/usr/sbin/$P"
	install -m755 "$F/$P.init" "$root/etc/init.d/$P"
	install -m755 "$F/$P.rpcd" "$root/usr/libexec/rpcd/keystone.${P#keystone-}"
	install -m644 "$F/$P.acl.json" "$root/usr/share/rpcd/acl.d/$P.json"
	install -m644 "$HERE/common/files/common.sh" "$root/usr/share/$P/common.sh"
	echo "$V" > "$root/usr/share/$P/version"
	conf=
	if [ -f "$F/$P.config" ]; then
		install -d "$root/etc/config"
		install -m600 "$F/$P.config" "$root/etc/config/$P"
		conf="/etc/config/$P"
	fi

	# ipk, for opkg firmware
	ipk="$W/ipk"; mkdir -p "$ipk/c"
	{
		printf 'Package: %s\nVersion: %s\n' "$P" "$V"
		[ -z "$D" ] || printf 'Depends: %s\n' "$(echo $D | sed 's/ /, /g')"
		printf 'Section: utils\nArchitecture: all\nMaintainer: perz3us\nLicense: GPL-3.0-or-later\nDescription: %s\n' "$T"
	} > "$ipk/c/control"
	[ -z "$conf" ] || echo "$conf" > "$ipk/c/conffiles"
	script "$P" post-install > "$ipk/c/postinst"
	script "$P" pre-deinstall > "$ipk/c/prerm"
	chmod 755 "$ipk/c/postinst" "$ipk/c/prerm"
	echo 2.0 > "$ipk/debian-binary"
	tar --numeric-owner -C "$root" --exclude ./lib -czf "$ipk/data.tar.gz" .
	tar --numeric-owner -C "$ipk/c" -czf "$ipk/control.tar.gz" .
	tar --numeric-owner -C "$ipk" -czf "$OUT/${P}_${V}_all.ipk" ./debian-binary ./data.tar.gz ./control.tar.gz

	# apk, for apk firmware (OpenWrt 25.12): the same records OpenWrt's package.mk writes
	( cd "$root" && find . -type f ! -path './lib/apk/*' | sed 's#^\.##' | sort ) > "$root/lib/apk/packages/$P.list"
	if [ -n "$conf" ]; then
		echo "$conf" > "$root/lib/apk/packages/$P.conffiles"
		printf '%s %s\n' "$conf" "$(sha256sum "$root$conf" | cut -d' ' -f1)" > "$root/lib/apk/packages/$P.conffiles_static"
	fi
	for s in post-install post-upgrade pre-deinstall; do script "$P" $s > "$W/$s"; done
	deps="libc $D"
	apk mkpkg \
		--info "name:$P" --info "version:$V-r${R:-1}" --info "description:$T" \
		--info "arch:noarch" --info "license:GPL-3.0-or-later" --info "origin:feeds/base/$P" \
		--info "depends:$deps" \
		--script "post-install:$W/post-install" --script "post-upgrade:$W/post-upgrade" \
		--script "pre-deinstall:$W/pre-deinstall" \
		--files "$root" --output "$OUT/$P-$V.apk"
	rm -rf "$W"
	echo "built $P $V"
done
ls -l "$OUT"
