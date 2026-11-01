ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

# 原生 roothide 包：安装前缀为空（layout 不带 /var/jb），
# RootHide 下直接安装即可，不经转换器，arm64e 的 PAC 认证不被破坏。
THEOS_PACKAGE_INSTALL_PREFIX =

# ---------------------------------------------------------------------------
# 动态库：注入 SpringBoard，负责锁屏时钟的秒数显示 / 字号缩放 / 垂直位移
# ---------------------------------------------------------------------------
TWEAK_NAME = LSTimeSeconds
LSTimeSeconds_FILES = LSTimeSeconds.xm
LSTimeSeconds_FRAMEWORKS = UIKit Foundation CoreFoundation
# 链接 roothide 版 substrate stub：
#   install-name = @loader_path/.jbroot/usr/lib/libsubstrate.dylib
# （不用 @rpath/CydiaSubstrate，那是 rootless 形态，转换器会改写）
LSTimeSeconds_LDFLAGS = -L$(THEOS_PROJECT_DIR) -lsubstrate_roothide
LSTimeSeconds_CFLAGS = -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable
LSTimeSeconds_OBJCCFLAGS = -fno-modules

# ---------------------------------------------------------------------------
# 设置面板（PreferenceBundle）：
#   不使用 Theos bundle target —— 面板可执行文件来自 vendor/LSTSPrefs.bundle，
#   与真机验证过的稳定版完全一致（原因见 build.sh 顶部注释与 docs/05）。
#   experimental/ 下有本项目自建控制器的源码，真机进入设置会闪退，暂未启用。
# ---------------------------------------------------------------------------

include $(THEOS_MAKE_PATH)/tweak.mk
