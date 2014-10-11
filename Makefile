SDKVERSION = 7.0
ARCHS = armv7 armv7s arm64

include theos/makefiles/common.mk
TWEAK_NAME = DictationPasscode
DictationPasscode_FILES = Tweak.xm
DictationPasscode_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
