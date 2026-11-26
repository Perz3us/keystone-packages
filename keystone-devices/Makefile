include $(TOPDIR)/rules.mk

PKG_NAME:=keystone-devices
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=perz3us

include $(INCLUDE_DIR)/package.mk

define Package/keystone-devices
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Data used per device for the Keystone app
  DEPENDS:=+rpcd +keystone-history
  PKGARCH:=all
endef

define Build/Compile
endef

define Package/keystone-devices/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/usr/libexec/rpcd \
		$(1)/usr/share/rpcd/acl.d $(1)/usr/share/keystone-devices
	$(INSTALL_BIN) ./files/keystone-devices $(1)/usr/sbin/keystone-devices
	$(INSTALL_BIN) ./files/keystone-devices.init $(1)/etc/init.d/keystone-devices
	$(INSTALL_BIN) ./files/keystone-devices.rpcd $(1)/usr/libexec/rpcd/keystone.devices
	$(INSTALL_DATA) ./files/keystone-devices.acl.json $(1)/usr/share/rpcd/acl.d/keystone-devices.json
	$(INSTALL_DATA) ./files/common.sh $(1)/usr/share/keystone-devices/common.sh
	echo $(PKG_VERSION) > $(1)/usr/share/keystone-devices/version
endef

define Package/keystone-devices/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/rpcd reload
	/etc/init.d/keystone-devices enable
	/etc/init.d/keystone-devices restart
}
exit 0
endef

define Package/keystone-devices/prerm
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/keystone-devices stop
	/etc/init.d/keystone-devices disable
}
exit 0
endef

$(eval $(call BuildPackage,keystone-devices))
