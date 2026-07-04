# 指定无根越狱环境变量
THEOS_PACKAGE_SCHEME = rootless

TARGET := iphone:clang::15.0
INSTALL_TARGET_PROCESSES = SpringBoard backboardd
ARCHS = arm64 arm64e

include /var/theos/makefiles/common.mk

TWEAK_NAME = UnixBootAnim

UnixBootAnim_FILES = Tweak.x
UnixBootAnim_CFLAGS = -fobjc-arc
UnixBootAnim_FRAMEWORKS = Foundation QuartzCore CoreGraphics OSLog CoreText

include $(THEOS_MAKE_PATH)/tweak.mk


SUBPROJECTS += unixbootanimprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
