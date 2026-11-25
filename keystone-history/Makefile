
include $(TOPDIR)/rules.mk

PKG_NAME:=keystone-history
PKG_VERSION:=0.2.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=perz3us

include $(INCLUDE_DIR)/package.mk

define Package/keystone-history
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Signal, ping and traffic history for the Keystone app
  DEPENDS:=+rpcd
  PKGARCH:=all
endef

define Package/keystone-history/conffiles
/etc/config/keystone-history
endef

define Build/Compile
endef

define Package/keystone-history/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/config $(1)/usr/libexec/rpcd \
		$(1)/usr/share/rpcd/acl.d $(1)/usr/share/keystone-history
	$(INSTALL_BIN) ./files/keystone-history $(1)/usr/sbin/keystone-history
	$(INSTALL_BIN) ./files/keystone-history.init $(1)/etc/init.d/keystone-history
	$(INSTALL_CONF) ./files/keystone-history.config $(1)/etc/config/keystone-history
	$(INSTALL_BIN) ./files/keystone-history.rpcd $(1)/usr/libexec/rpcd/keystone.history
	$(INSTALL_DATA) ./files/keystone-history.acl.json $(1)/usr/share/rpcd/acl.d/keystone-history.json
	echo $(PKG_VERSION) > $(1)/usr/share/keystone-history/version
endef

define Package/keystone-history/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/rpcd reload
	/etc/init.d/keystone-history enable
	/etc/init.d/keystone-history restart
}
exit 0
endef

define Package/keystone-history/prerm
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/keystone-history stop
	/etc/init.d/keystone-history disable
}
exit 0
endef

$(eval $(call BuildPackage,keystone-history))
