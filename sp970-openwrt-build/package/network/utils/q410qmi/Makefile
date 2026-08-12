include $(TOPDIR)/rules.mk

PKG_NAME:=q410qmi
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=peterhon168

include $(INCLUDE_DIR)/package.mk

define Package/q410qmi
	SECTION:=net
	CATEGORY:=Network
	TITLE:=Single-owner QMI data path for the SP970 MSM8916 modem
	DEPENDS:=@TARGET_msm89xx_msm8916 +libqmi +qmi-utils +libqrtr-glib +glib2
endef

define Package/q410qmi/description
 Activates the slot-1 Primary GW UIM application and keeps one Raw-IP,
 no-QoS WDS client alive for the SP970 BAM-DMUX data interface.
endef

define Build/Prepare
	$(call Build/Prepare/Default)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

Q410QMI_CPPFLAGS:= \
	-I$(STAGING_DIR)/usr/include/libqmi-glib \
	-I$(STAGING_DIR)/usr/include/libqrtr-glib \
	-I$(STAGING_DIR)/usr/include/glib-2.0 \
	-I$(STAGING_DIR)/usr/lib/glib-2.0/include \
	-I$(STAGING_DIR)/usr/include

Q410QMI_LIBS:= \
	-lqmi-glib -lqrtr-glib -lgio-2.0 -lgobject-2.0 -lglib-2.0

define Build/Compile
	$(TARGET_CC) $(TARGET_CPPFLAGS) $(TARGET_CFLAGS) $(Q410QMI_CPPFLAGS) \
		$(PKG_BUILD_DIR)/q410-qmi-uim-provision.c \
		-o $(PKG_BUILD_DIR)/q410-qmi-uim-provision \
		$(TARGET_LDFLAGS) $(Q410QMI_LIBS)
	$(TARGET_CC) $(TARGET_CPPFLAGS) $(TARGET_CFLAGS) $(Q410QMI_CPPFLAGS) \
		$(PKG_BUILD_DIR)/q410-qmi-wds-connect.c \
		-o $(PKG_BUILD_DIR)/q410-qmi-wds-connect \
		$(TARGET_LDFLAGS) $(Q410QMI_LIBS)
endef

define Package/q410qmi/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/q410-qmi-uim-provision $(1)/usr/sbin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/q410-qmi-wds-connect $(1)/usr/sbin/
endef

$(eval $(call BuildPackage,q410qmi))
