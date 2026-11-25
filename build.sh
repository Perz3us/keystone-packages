#!/bin/sh
set -e
SDK=$(ls -d /cache/openwrt-sdk-*/ | head -1)
cd "$SDK"
[ -d feeds/base ] || { ./scripts/feeds update base >/dev/null && ./scripts/feeds install rpcd >/dev/null; }
rm -rf package/keystone-helper
mkdir -p package/keystone-helper
cp -r /src/Makefile /src/files package/keystone-helper/
[ -f .config ] || make defconfig >/dev/null
sed -i '/CONFIG_PACKAGE_keystone-helper[= ]/d' .config
echo 'CONFIG_PACKAGE_keystone-helper=m' >> .config
make defconfig >/dev/null
make package/keystone-helper/clean >/dev/null 2>&1 || true
make package/keystone-helper/compile -j4 || make package/keystone-helper/compile V=s
V=$(sed -n 's/^PKG_VERSION:=//p' /src/Makefile)
mkdir -p /src/dist
rm -f /src/dist/*.apk /src/dist/*.ipk
find bin -name 'keystone-helper*.apk' -exec cp {} /src/dist/keystone-helper-$V.apk \;
IPK=/tmp/ipk; rm -rf $IPK; mkdir -p $IPK/c $IPK/d/usr/sbin $IPK/d/etc/init.d $IPK/d/etc/config $IPK/d/usr/libexec/rpcd $IPK/d/usr/share/rpcd/acl.d $IPK/d/usr/share/keystone-helper
F=/src/files
install -m755 $F/keystone-collect $IPK/d/usr/sbin/keystone-collect
install -m755 $F/keystone-helper.init $IPK/d/etc/init.d/keystone-helper
install -m600 $F/keystone.config $IPK/d/etc/config/keystone
install -m755 $F/keystone.rpcd $IPK/d/usr/libexec/rpcd/keystone
install -m644 $F/keystone.acl.json $IPK/d/usr/share/rpcd/acl.d/keystone-helper.json
echo $V > $IPK/d/usr/share/keystone-helper/version
cat > $IPK/c/control <<EOC
Package: keystone-helper
Version: $V
Depends: rpcd
Section: utils
Architecture: all
Maintainer: perz3us
License: GPL-3.0-or-later
Description: Signal, ping and traffic history for the Keystone app
EOC
echo /etc/config/keystone > $IPK/c/conffiles
printf '#!/bin/sh\n[ -n "$IPKG_INSTROOT" ] || {\n\t/etc/init.d/rpcd reload\n\t/etc/init.d/keystone-helper enable\n\t/etc/init.d/keystone-helper restart\n}\nexit 0\n' > $IPK/c/postinst
printf '#!/bin/sh\n[ -n "$IPKG_INSTROOT" ] || {\n\t/etc/init.d/keystone-helper stop\n\t/etc/init.d/keystone-helper disable\n}\nexit 0\n' > $IPK/c/prerm
chmod 755 $IPK/c/postinst $IPK/c/prerm
echo 2.0 > $IPK/debian-binary
tar --numeric-owner --owner=0 --group=0 -C $IPK/d -czf $IPK/data.tar.gz .
tar --numeric-owner --owner=0 --group=0 -C $IPK/c -czf $IPK/control.tar.gz .
tar --numeric-owner --owner=0 --group=0 -C $IPK -czf /src/dist/keystone-helper_${V}_all.ipk ./debian-binary ./data.tar.gz ./control.tar.gz
ls -la /src/dist
