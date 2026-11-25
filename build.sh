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
	sed -i "/CONFIG_PACKAGE_$P[= ]/d" .config
	echo "CONFIG_PACKAGE_$P=m" >> .config
	make defconfig >/dev/null
	make package/$P/clean >/dev/null 2>&1 || true
	make package/$P/compile -j4 || make package/$P/compile V=s
	find bin -name "$P*.apk" -exec cp {} /src/dist/$P-$V.apk \;

	IPK=/tmp/ipk; rm -rf $IPK; mkdir -p $IPK/c $IPK/d
	F=/src/$P/files
	install -d $IPK/d/usr/sbin $IPK/d/etc/init.d $IPK/d/etc/config $IPK/d/usr/libexec/rpcd $IPK/d/usr/share/rpcd/acl.d $IPK/d/usr/share/$P
	install -m755 $F/$P $IPK/d/usr/sbin/$P
	install -m755 $F/$P.init $IPK/d/etc/init.d/$P
	install -m600 $F/$P.config $IPK/d/etc/config/$P
	install -m755 $F/$P.rpcd $IPK/d/usr/libexec/rpcd/keystone.${P#keystone-}
	install -m644 $F/$P.acl.json $IPK/d/usr/share/rpcd/acl.d/$P.json
	echo $V > $IPK/d/usr/share/$P/version
	cat > $IPK/c/control <<EOC
Package: $P
Version: $V
Depends: rpcd
Section: utils
Architecture: all
Maintainer: perz3us
License: GPL-3.0-or-later
Description: $T
EOC
	echo /etc/config/$P > $IPK/c/conffiles
	printf '#!/bin/sh\n[ -n "$IPKG_INSTROOT" ] || {\n\t/etc/init.d/rpcd reload\n\t/etc/init.d/%s enable\n\t/etc/init.d/%s restart\n}\nexit 0\n' $P $P > $IPK/c/postinst
	printf '#!/bin/sh\n[ -n "$IPKG_INSTROOT" ] || {\n\t/etc/init.d/%s stop\n\t/etc/init.d/%s disable\n}\nexit 0\n' $P $P > $IPK/c/prerm
	chmod 755 $IPK/c/postinst $IPK/c/prerm
	echo 2.0 > $IPK/debian-binary
	tar --numeric-owner --owner=0 --group=0 -C $IPK/d -czf $IPK/data.tar.gz .
	tar --numeric-owner --owner=0 --group=0 -C $IPK/c -czf $IPK/control.tar.gz .
	tar --numeric-owner --owner=0 --group=0 -C $IPK -czf /src/dist/${P}_${V}_all.ipk ./debian-binary ./data.tar.gz ./control.tar.gz
done
ls -la /src/dist
