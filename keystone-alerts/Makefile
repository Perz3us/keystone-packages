
include $(TOPDIR)/rules.mk

PKG_NAME:=keystone-alerts
PKG_VERSION:=0.1.1
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=perz3us

include $(INCLUDE_DIR)/package.mk

define Package/keystone-alerts
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Connection alerts and outage log for the Keystone app
  DEPENDS:=+rpcd +keystone-history
  PKGARCH:=all
endef

define Package/keystone-alerts/conffiles
/etc/config/keystone-alerts
endef

define Build/Compile
endef

define Package/keystone-alerts/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/config $(1)/usr/libexec/rpcd \
		$(1)/usr/share/rpcd/acl.d $(1)/usr/share/keystone-alerts
	$(INSTALL_BIN) ./files/keystone-alerts $(1)/usr/sbin/keystone-alerts
	$(INSTALL_BIN) ./files/keystone-alerts.init $(1)/etc/init.d/keystone-alerts
	$(INSTALL_CONF) ./files/keystone-alerts.config $(1)/etc/config/keystone-alerts
	$(INSTALL_BIN) ./files/keystone-alerts.rpcd $(1)/usr/libexec/rpcd/keystone.alerts
	$(INSTALL_DATA) ./files/keystone-alerts.acl.json $(1)/usr/share/rpcd/acl.d/keystone-alerts.json
	$(INSTALL_DATA) ./files/common.sh $(1)/usr/share/$(PKG_NAME)/common.sh
	echo $(PKG_VERSION) > $(1)/usr/share/keystone-alerts/version
endef

define Package/keystone-alerts/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/rpcd reload
	/etc/init.d/keystone-alerts enable
	/etc/init.d/keystone-alerts restart
}
exit 0
endef

define Package/keystone-alerts/prerm
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/keystone-alerts stop
	/etc/init.d/keystone-alerts disable
}
exit 0
endef

$(eval $(call BuildPackage,keystone-alerts))
