include $(TOPDIR)/rules.mk

PKG_NAME:=keystone-cellguard
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=perz3us

include $(INCLUDE_DIR)/package.mk

define Package/keystone-cellguard
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Removes a cell lock that leaves the router offline, for the Keystone app
  DEPENDS:=+rpcd +keystone-history
  PKGARCH:=all
endef

define Build/Compile
endef

define Package/keystone-cellguard/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/usr/libexec/rpcd \
		$(1)/usr/share/rpcd/acl.d $(1)/usr/share/keystone-cellguard
	$(INSTALL_BIN) ./files/keystone-cellguard $(1)/usr/sbin/keystone-cellguard
	$(INSTALL_BIN) ./files/keystone-cellguard.init $(1)/etc/init.d/keystone-cellguard
	$(INSTALL_BIN) ./files/keystone-cellguard.rpcd $(1)/usr/libexec/rpcd/keystone.cellguard
	$(INSTALL_DATA) ./files/keystone-cellguard.acl.json $(1)/usr/share/rpcd/acl.d/keystone-cellguard.json
	$(INSTALL_DATA) ./files/common.sh $(1)/usr/share/$(PKG_NAME)/common.sh
	echo $(PKG_VERSION) > $(1)/usr/share/keystone-cellguard/version
endef

define Package/keystone-cellguard/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/rpcd reload
	/etc/init.d/keystone-cellguard enable
	/etc/init.d/keystone-cellguard restart
}
exit 0
endef

define Package/keystone-cellguard/prerm
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/keystone-cellguard stop
	/etc/init.d/keystone-cellguard disable
}
exit 0
endef

$(eval $(call BuildPackage,keystone-cellguard))
