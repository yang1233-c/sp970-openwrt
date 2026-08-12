include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/package.mk

PKG_NAME:=sp970-firmware
PKG_RELEASE:=2
SP970_FIRMWARE_DIR ?= $(TOPDIR)/../local-firmware/sp970

define Package/sp970-firmware/Default
	SECTION:=firmware
	CATEGORY:=Base system
	PKGARCH:=all
endef

define Package/sp970-wcnss-firmware
	$(call Package/sp970-firmware/Default)
	TITLE:=Local SP970 WCNSS/WCN36xx firmware
	DEPENDS:=@TARGET_msm89xx_msm8916
endef

define Package/sp970-modem-firmware
	$(call Package/sp970-firmware/Default)
	TITLE:=Local SP970 MPSS modem firmware
	DEPENDS:=@TARGET_msm89xx_msm8916
endef

define Package/sp970-firmware
	$(call Package/sp970-firmware/Default)
	TITLE:=Complete local SP970 modem and WLAN firmware
	DEPENDS:=@TARGET_msm89xx_msm8916 +sp970-wcnss-firmware +sp970-modem-firmware
endef

define Package/sp970-firmware/description
 Meta package for locally extracted MSM8916 MPSS and WCNSS firmware.
endef

define Build/Prepare
	true
endef

define Build/Compile
	true
endef

define Package/sp970-wcnss-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/wlan/prima
	@if [ -d "$(SP970_FIRMWARE_DIR)" ]; then \
		for f in "$(SP970_FIRMWARE_DIR)"/wcnss.*; do \
			[ -e "$$$$f" ] && $(CP) "$$$$f" $(1)/lib/firmware/; \
		done; \
		if [ -d "$(SP970_FIRMWARE_DIR)/wlan/prima" ]; then \
			$(CP) "$(SP970_FIRMWARE_DIR)/wlan/prima"/* $(1)/lib/firmware/wlan/prima/; \
		fi; \
	else \
		echo "SP970_FIRMWARE_DIR missing; WCNSS payload omitted" >&2; \
	fi
endef

define Package/sp970-modem-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware
	@if [ -d "$(SP970_FIRMWARE_DIR)" ]; then \
		for f in "$(SP970_FIRMWARE_DIR)"/mba.mbn "$(SP970_FIRMWARE_DIR)"/modem.*; do \
			[ -e "$$$$f" ] && $(CP) "$$$$f" $(1)/lib/firmware/; \
		done; \
	else \
		echo "SP970_FIRMWARE_DIR missing; MPSS payload omitted" >&2; \
	fi
endef

define Package/sp970-firmware/install
	true
endef

$(eval $(call BuildPackage,sp970-wcnss-firmware))
$(eval $(call BuildPackage,sp970-modem-firmware))
$(eval $(call BuildPackage,sp970-firmware))

