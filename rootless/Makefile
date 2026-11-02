ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

# ---------------------------------------------------------------------------
# 动态库：注入 SpringBoard，负责锁屏时钟的秒数显示 / 字号缩放 / 垂直位移
# ---------------------------------------------------------------------------
TWEAK_NAME = LSTimeSeconds
LSTimeSeconds_FILES = LSTimeSeconds.xm
LSTimeSeconds_FRAMEWORKS = UIKit Foundation CoreFoundation
# rootless 链接标准 substrate stub（install-name @rpath/CydiaSubstrate.framework/CydiaSubstrate，
# ElleKit 在 /var/jb 下提供该框架）；补上 /var/jb 的 rpath 供 dyld 解析。
LSTimeSeconds_LDFLAGS = -lsubstrate -Wl,-rpath,/var/jb/Library/Frameworks -Wl,-rpath,/var/jb/usr/lib
LSTimeSeconds_CFLAGS = -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable
LSTimeSeconds_OBJCCFLAGS = -fno-modules

# ---------------------------------------------------------------------------
# 设置面板（PreferenceBundle）：由 prefs/ 源码编译，单独打进同一个 deb。
# 不再使用 RootHide 转换过的 vendor 二进制（它依赖 libroothide，rootless 下加载不了）。
# ---------------------------------------------------------------------------
BUNDLE_NAME = LSTSPrefs
LSTSPrefs_FILES = prefs/LSTRootListController.m
LSTSPrefs_INSTALL_PATH = /Library/PreferenceBundles
LSTSPrefs_FRAMEWORKS = UIKit Foundation
LSTSPrefs_PRIVATE_FRAMEWORKS = Preferences
LSTSPrefs_CFLAGS = -fobjc-arc -Wall

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
