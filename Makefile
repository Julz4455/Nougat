export TARGET = iphone:10.1

INSTALL_TARGET_PROCESSES = Preferences

ifneq ($(RESPRING),0)
		INSTALL_TARGET_PROCESSES += SpringBoard
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Nougat
Nougat_FILES = $(wildcard *.x) $(wildcard *.m)
Nougat_FRAMEWORKS = UIKit QuartzCore
Nougat_PRIVATE_FRAMEWORKS = BackBoardServices FrontBoard
Nougat_LIBRARIES = flipswitch
Nougat_CFLAGS = -fobjc-arc -IHeaders -Wno-deprecated-declarations

BUNDLE_NAME = Nougat-Resources
Nougat-Resources_INSTALL_PATH = /var/mobile/Library/

SUBPROJECTS = nougat

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS)/makefiles/bundle.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
