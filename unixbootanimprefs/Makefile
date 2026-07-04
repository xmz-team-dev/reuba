THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang::15.0
ARCHS = arm64 arm64e

include /var/theos/makefiles/common.mk

BUNDLE_NAME = UnixBootAnimPrefs

UnixBootAnimPrefs_FILES = UBARootListController.m UBACustomSwitchCell.m
UnixBootAnimPrefs_FILES = UBARootListController.m
UnixBootAnimPrefs_FRAMEWORKS = UIKit
UnixBootAnimPrefs_PRIVATE_FRAMEWORKS = Preferences
UnixBootAnimPrefs_INSTALL_PATH = /Library/PreferenceBundles
UnixBootAnimPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
