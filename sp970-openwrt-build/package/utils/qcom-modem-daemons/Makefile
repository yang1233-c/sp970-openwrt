# SPDX-License-Identifier: BSD-3-Clause

include $(TOPDIR)/rules.mk

PKG_NAME:=qcom-modem-daemons
PKG_VERSION:=2026.08.13
PKG_RELEASE:=1
PKG_LICENSE:=BSD-3-Clause
PKG_LICENSE_FILES:=LICENSE.qrtr LICENSE.rmtfs LICENSE.tqftpserv
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/qcom-modem-daemons
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=Qualcomm RMTFS and TQFTP services for MSM8916
	DEPENDS:=@TARGET_msm89xx_msm8916 +libzstd
endef

define Package/qcom-modem-daemons/description
 Source-built QRTR, RMTFS and TQFTP userspace services used to start the
 onboard MSM8916 modem. Device firmware and NV data are not included.
endef

define Build/Prepare
	$(call Build/Prepare/Default)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

QMD_CFLAGS:= \
	$(TARGET_CPPFLAGS) $(TARGET_CFLAGS) \
	-D_GNU_SOURCE -ffunction-sections -fdata-sections \
	-I$(PKG_BUILD_DIR)/qrtr/include \
	-I$(PKG_BUILD_DIR)/compat

QMD_LDFLAGS:= \
	$(TARGET_LDFLAGS) -Wl,--gc-sections

define Build/Compile
	$(TARGET_CC) $(QMD_CFLAGS) -fPIC -c \
		$(PKG_BUILD_DIR)/qrtr/logging.c -o $(PKG_BUILD_DIR)/logging.o
	$(TARGET_CC) $(QMD_CFLAGS) -fPIC -c \
		$(PKG_BUILD_DIR)/qrtr/qmi.c -o $(PKG_BUILD_DIR)/qmi.o
	$(TARGET_CC) $(QMD_CFLAGS) -fPIC -c \
		$(PKG_BUILD_DIR)/qrtr/qrtr.c -o $(PKG_BUILD_DIR)/qrtr.o
	$(TARGET_CROSS)gcc-ar rcs $(PKG_BUILD_DIR)/libqrtr.a \
		$(PKG_BUILD_DIR)/logging.o $(PKG_BUILD_DIR)/qmi.o $(PKG_BUILD_DIR)/qrtr.o

	$(TARGET_CC) $(QMD_CFLAGS) -DANDROID \
		$(PKG_BUILD_DIR)/rmtfs/qmi_rmtfs.c \
		$(PKG_BUILD_DIR)/rmtfs/rmtfs.c \
		$(PKG_BUILD_DIR)/rmtfs/rproc.c \
		$(PKG_BUILD_DIR)/rmtfs/sharedmem.c \
		$(PKG_BUILD_DIR)/rmtfs/storage.c \
		$(PKG_BUILD_DIR)/rmtfs/util.c \
		$(PKG_BUILD_DIR)/libqrtr.a \
		-o $(PKG_BUILD_DIR)/rmtfs-daemon \
		$(QMD_LDFLAGS) -lpthread

	$(TARGET_CC) $(QMD_CFLAGS) -DHAVE_ZSTD \
		$(PKG_BUILD_DIR)/tqftpserv/tqftpserv.c \
		$(PKG_BUILD_DIR)/tqftpserv/translate.c \
		$(PKG_BUILD_DIR)/tqftpserv/zstd-decompress.c \
		$(PKG_BUILD_DIR)/libqrtr.a \
		-o $(PKG_BUILD_DIR)/tqftpserv-daemon \
		$(QMD_LDFLAGS) -lzstd
endef

define Package/qcom-modem-daemons/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/rmtfs-daemon $(1)/usr/sbin/rmtfs
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tqftpserv-daemon $(1)/usr/bin/tqftpserv
endef

$(eval $(call BuildPackage,qcom-modem-daemons))
