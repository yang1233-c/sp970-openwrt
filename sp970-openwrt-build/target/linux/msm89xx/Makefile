include $(TOPDIR)/rules.mk

ARCH:=aarch64
BOARD:=msm89xx
BOARDNAME:=Qualcomm MSM8916
FEATURES:=ext4 gpio rtc squashfs usb usbgadget ramdisk fpu emmc
KERNELNAME:=Image
CPU_TYPE:=cortex-a53
SUBTARGETS:=msm8916
KERNEL_PATCHVER:=6.12

define Target/Description
	Qualcomm MSM8916 AArch64 target; SP970 is a board profile under msm8916.
endef

include $(INCLUDE_DIR)/target.mk

$(eval $(call BuildTarget))

