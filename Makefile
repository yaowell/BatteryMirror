TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := roothide
INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BatteryMirrorLite

BatteryMirrorLite_FILES = Tweak.xm
BatteryMirrorLite_FRAMEWORKS = UIKit Foundation
BatteryMirrorLite_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "sbreload"
