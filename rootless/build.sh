#!/bin/bash
# =============================================================================
#  LSTimeSeconds rootless 构建脚本（在 WSL / Linux 下运行）
#
#    wsl -d Ubuntu-22.04 -- bash /mnt/d/WorkBudy/Bioprotect/LSTimeSeconds-rootless/build.sh
#
#  与 roothide 版的区别：
#    · 安装前缀 = /var/jb（Theos rootless scheme），包架构 iphoneos-arm64；
#    · 链接标准 substrate stub（@rpath/CydiaSubstrate.framework/CydiaSubstrate），
#      不再依赖 @loader_path/.jbroot/... 的 RootHide 路径；
#    · 设置面板由 prefs/ 源码编译（arm64 + arm64e），不再使用 vendor 里的
#      RootHide 转换版二进制（它依赖 libroothide，rootless 下加载不了）。
#
#  最后一步仍然要对两个 arm64e 二进制做 __cfstring isa 认证补丁再 ldid 重签，
#  原因见 docs/06-rootless适配.md 与 roothide 版 docs/02。
# =============================================================================
set -u

export THEOS="$HOME/theos"
export PATH="$THEOS/bin:$PATH"

SRC=/mnt/d/WorkBudy/Bioprotect/LSTimeSeconds-rootless
DST="$HOME/lsts_rootless_build"
TC19="$HOME/tc19/linux/iphone/bin"

die() { echo "!! $*"; exit 1; }
[ -x "$TC19/clang" ] || die "clang 19 工具链不存在（$TC19/clang）"

rm -rf "$DST"; mkdir -p "$DST"
cp -r "$SRC"/. "$DST"/
rm -rf "$DST/.git" "$DST/packages" "$DST/.theos"
# Windows 侧编辑过的文件可能带 CRLF，Theos/ldid 对 CRLF 敏感，统一转 LF
find "$DST" -type f \( -name "*.xm" -o -name "*.m" -o -name "*.h" -o -name "*.plist" -o -name "*.strings" -o -name "*.sh" -o -name "Makefile" -o -name "control" \) -exec sed -i 's/\r$//' {} \; 2>/dev/null

cd "$DST" || die "无法进入 $DST"
echo "=== 清理旧产物 ==="
make clean >/dev/null 2>&1 || true
rm -rf packages .theos

echo "=== 编译（clang 19 + ld64 956，arm64 + arm64e，rootless /var/jb）==="
if ! make package FINALPACKAGE=1 \
    THEOS_PACKAGE_INSTALL_PREFIX=/var/jb \
    TARGET_CC="$TC19/clang" TARGET_CXX="$TC19/clang++" TARGET_LD="$TC19/clang++" \
    TARGET_CODESIGN="$TC19/ldid" 2>&1 | tail -60; then
    die "编译失败"
fi

DEB=$(ls -1t packages/*.deb 2>/dev/null | head -1)
[ -n "$DEB" ] || die "没有生成 deb"
echo "生成 deb: $DEB"

echo
echo "=== 解包，做 arm64e PAC 补丁（__cfstring + __objc_data）==="
rm -rf "$DST/repack"; mkdir -p "$DST/repack"
dpkg-deb -R "$DEB" "$DST/repack" || die "dpkg-deb -R 失败"

patch_arm64e() {
    python3 "$DST/tools/patch_arm64e.py" "$1" || die "arm64e PAC 补丁失败: $1"
}

DLDIR="$DST/repack/var/jb/Library/MobileSubstrate/DynamicLibraries"
BNDLDIR="$DST/repack/var/jb/Library/PreferenceBundles/LSTSPrefs.bundle"
DYLIB="$DLDIR/LSTimeSeconds.dylib"
PREFS="$BNDLDIR/LSTSPrefs"
[ -f "$DYLIB" ] || die "包里没有 LSTimeSeconds.dylib（检查 /var/jb 前缀）"
[ -f "$PREFS" ] || die "包里没有设置面板可执行文件 LSTSPrefs"

patch_arm64e "$DYLIB" || die "动态库 PAC 补丁失败"
patch_arm64e "$PREFS" || die "设置面板 PAC 补丁失败"

echo "=== 重签（ldid）与权限 ==="
"$TC19/ldid" -S "$DYLIB" || die "ldid 签名失败: dylib"
"$TC19/ldid" -S "$PREFS" || die "ldid 签名失败: 设置面板"
chmod 755 "$DYLIB" "$PREFS"
# Windows 侧拷贝过来的文件常带 777，统一成 iOS 上习惯的 755/644
find "$DST/repack/var/jb" -type d -exec chmod 755 {} +
find "$DST/repack/var/jb" -type f ! -path "$PREFS" ! -path "$DYLIB" -exec chmod 644 {} +

echo "=== 打包 ==="
FINAL_DEB="$SRC/com.sini921.lstimeseconds_0.0.7-2_iphoneos-arm64.deb"
rm -f "$FINAL_DEB"
dpkg-deb -b -Zxz "$DST/repack" "$FINAL_DEB" || die "dpkg-deb -b 失败"

echo
echo "=== 产物 ==="
ls -lh "$FINAL_DEB"
dpkg-deb -c "$FINAL_DEB"
