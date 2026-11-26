#!/bin/sh
set -e
SDK=$(ls -d /cache/openwrt-sdk-*/ | head -1)
cd "$SDK"
[ -d feeds/base ] || { ./scripts/feeds update base >/dev/null && ./scripts/feeds install rpcd >/dev/null; }
[ -f .config ] || make defconfig >/dev/null
mkdir -p /src/dist
rm -f /src/dist/*.apk /src/dist/*.ipk

if [ -n "$1" ]; then dirs=$1; else
	dirs=
	for m in /src/*/Makefile; do dirs="$dirs $(basename "$(dirname "$m")")"; done
fi

for P in $dirs; do
	V=$(sed -n 's/^PKG_VERSION:=//p' /src/$P/Makefile)
	T=$(sed -n "s/^ *TITLE:=//p" /src/$P/Makefile)
	rm -rf package/$P
	mkdir -p package/$P
	cp -r /src/$P/Makefile /src/$P/files package/$P/
	cp /src/common/files/common.sh package/$P/files/
	sed -i "/CONFIG_PACKAGE_$P[= ]/d" .config
	echo "CONFIG_PACKAGE_$P=m" >> .config
	make defconfig >/dev/null
	make package/$P/clean >/dev/null 2>&1 || true
	make package/$P/compile -j4 || make package/$P/compile V=s
	find bin -name "$P*.apk" -exec cp {} /src/dist/$P-$V.apk \;

	IPK=/tmp/ipk; rm -rf $IPK; mkdir -p $IPK/c $IPK/d
	F=/src/$P/files
	install -d $IPK/d/usr/share/$P
	if [ -f $F/$P ]; then install -d $IPK/d/usr/sbin; install -m755 $F/$P $IPK/d/usr/sbin/$P; fi
	if [ -f $F/$P.init ]; then install -d $IPK/d/etc/init.d; install -m755 $F/$P.init $IPK/d/etc/init.d/$P; fi
	if [ -f $F/$P.config ]; then install -d $IPK/d/etc/config; install -m600 $F/$P.config $IPK/d/etc/config/$P; fi
	if [ -f $F/$P.rpcd ]; then install -d $IPK/d/usr/libexec/rpcd; install -m755 $F/$P.rpcd $IPK/d/usr/libexec/rpcd/keystone.${P#keystone-}; fi
	if [ -f $F/$P.acl.json ]; then install -d $IPK/d/usr/share/rpcd/acl.d; install -m644 $F/$P.acl.json $IPK/d/usr/share/rpcd/acl.d/$P.json; fi
	if [ -f $F/$P.fw ]; then install -m755 $F/$P.fw $IPK/d/usr/share/$P/$P.fw; fi
	install -m644 /src/common/files/common.sh $IPK/d/usr/share/$P/common.sh
	echo $V > $IPK/d/usr/share/$P/version
	D=$(sed -n 's/^ *DEPENDS:=//p' /src/$P/Makefile | tr -d '+' | sed 's/^ *//; s/ *$//; s/  */, /g')
	cat > $IPK/c/control <<EOC
Package: $P
Version: $V
Depends: $D
Section: utils
Architecture: all
Maintainer: perz3us
License: GPL-3.0-or-later
Description: $T
EOC
	[ -n "$D" ] || sed -i '/^Depends: $/d' $IPK/c/control
	if [ -f $F/$P.init ]; then
		[ -f $F/$P.config ] && echo /etc/config/$P > $IPK/c/conffiles
		printf '#!/bin/sh
[ -n "$IPKG_INSTROOT" ] || {
	/etc/init.d/rpcd reload
	/etc/init.d/%s enable
	/etc/init.d/%s restart
}
exit 0
' $P $P > $IPK/c/postinst
		printf '#!/bin/sh
[ -n "$IPKG_INSTROOT" ] || {
	/etc/init.d/%s stop
	/etc/init.d/%s disable
}
exit 0
' $P $P > $IPK/c/prerm
		chmod 755 $IPK/c/postinst $IPK/c/prerm
	fi
	echo 2.0 > $IPK/debian-binary
	tar --numeric-owner --owner=0 --group=0 -C $IPK/d -czf $IPK/data.tar.gz .
	tar --numeric-owner --owner=0 --group=0 -C $IPK/c -czf $IPK/control.tar.gz .
	tar --numeric-owner --owner=0 --group=0 -C $IPK -czf /src/dist/${P}_${V}_all.ipk ./debian-binary ./data.tar.gz ./control.tar.gz
done
ls -la /src/dist
