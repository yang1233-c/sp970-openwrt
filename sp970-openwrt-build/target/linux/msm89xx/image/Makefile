include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk

define Device/sp970
	DEVICE_VENDOR := A
	DEVICE_MODEL := SP970_MB_V02
	DEVICE_DTS := msm8916-gexing-sp970
	DEVICE_DTS_DIR := $(DTS_DIR)/qcom
	DEVICE_PACKAGES := kmod-wcn36xx kmod-usb-net-rndis kmod-usb-net-cdc-ncm
	KERNEL := kernel-bin | gzip
	SUPPORTED_DEVICES := handsome,openstick
endef
TARGET_DEVICES += sp970

# Preserved-GPT system/userdata images are deliberately not emitted here.
# A later image rule may add a factory-neutral payload after RAM validation.

$(eval $(call BuildImage))

