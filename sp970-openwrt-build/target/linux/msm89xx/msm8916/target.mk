ARCH:=aarch64
CPU_TYPE:=cortex-a53

define Target/Description
	Qualcomm MSM8916 (SP970_MB_V02) AArch64 subtarget.
endef

DEFAULT_PACKAGES += kmod-mmc kmod-usb2 kmod-usb-net-rndis kmod-usb-net-cdc-ncm \
	kmod-usb-net-qmi-wwan kmod-usb-serial-option kmod-usb-wdm \
	dropbear
