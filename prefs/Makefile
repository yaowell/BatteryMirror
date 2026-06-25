ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = BatteryMirrorPrefs

BatteryMirrorPrefs_FILES = BMPRootListController.m
BatteryMirrorPrefs_FRAMEWORKS = UIKit
BatteryMirrorPrefs_PRIVATE_FRAMEWORKS = Preferences
BatteryMirrorPrefs_INSTALL_PATH = /Library/PreferenceBundles
BatteryMirrorPrefs_CFLAGS = -fobjc-arc
BatteryMirrorPrefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/bundle.mk

after-BatteryMirrorPrefs-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"$(ECHO_END)
	$(ECHO_NOTHING)cp "Resources/BatteryMirrorPrefs.plist" "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/BatteryMirrorPrefs.plist"$(ECHO_END)
