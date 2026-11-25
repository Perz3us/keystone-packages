
include $(TOPDIR)/rules.mk

PKG_NAME:=keystone-helper
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=perz3us

include $(INCLUDE_DIR)/package.mk

define Package/keystone-helper
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Signal, ping and traffic history for the Keystone app
  DEPENDS:=+rpcd
  PKGARCH:=all
endef

define Package/keystone-helper/conffiles
/etc/config/keystone
endef

define Build/Compile
endef

define Package/keystone-helper/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/config $(1)/usr/libexec/rpcd \
		$(1)/usr/share/rpcd/acl.d $(1)/usr/share/keystone-helper
	$(INSTALL_BIN) ./files/keystone-collect $(1)/usr/sbin/keystone-collect
	$(INSTALL_BIN) ./files/keystone-helper.init $(1)/etc/init.d/keystone-helper
	$(INSTALL_CONF) ./files/keystone.config $(1)/etc/config/keystone
	$(INSTALL_BIN) ./files/keystone.rpcd $(1)/usr/libexec/rpcd/keystone
	$(INSTALL_DATA) ./files/keystone.acl.json $(1)/usr/share/rpcd/acl.d/keystone-helper.json
	echo $(PKG_VERSION) > $(1)/usr/share/keystone-helper/version
endef

define Package/keystone-helper/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/rpcd reload
	/etc/init.d/keystone-helper enable
	/etc/init.d/keystone-helper restart
}
exit 0
endef

define Package/keystone-helper/prerm
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/keystone-helper stop
	/etc/init.d/keystone-helper disable
}
exit 0
endef

$(eval $(call BuildPackage,keystone-helper))
