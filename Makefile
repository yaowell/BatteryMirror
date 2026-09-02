TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BatteryMirror
SUBPROJECTS += prefs

BatteryMirror_FILES = Tweak.xm
BatteryMirror_FRAMEWORKS = UIKit Foundation
BatteryMirror_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "sbreload"
