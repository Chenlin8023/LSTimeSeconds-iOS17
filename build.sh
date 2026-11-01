#!/bin/bash
# =============================================================================
#  LSTimeSeconds 构建脚本（在 WSL / Linux 下运行）
#
#    wsl -d Ubuntu-22.04 -- bash /mnt/d/WorkBudy/Bioprotect/LSTimeSeconds-github/build.sh
#
#  为什么会话最后一步要「补丁 + 重签」：
#    SpringBoard（以及 Preferences）是 arm64e 进程。clang 19（L1ghtmann Linux 工具链）
#    给 arm64e 编 CFSTR 常量时，__cfstring 的 isa 记的是普通 UNSIGNED 重定位，
#    ld64 据此在 chained fixups 里写成「无 PAC 的普通 bind」。arm64e 进程里
#    objc_msgSend 碰到常量字符串接收者要做指针认证 → 未签名即 SIGBUS（安全模式）。
#    Xcode 编的原版这里是 auth bind：diversity=0x6AE1, addrDiv=1, key=2。
#    所以链接后必须把 isa 槽逐个改写成同形的 auth bind24，再 ldid 重签。
#    注意：动态库与设置面板可执行文件两个都要补，Preferences 同样是 arm64e。
# =============================================================================
set -u

export THEOS="$HOME/theos"
export PATH="$THEOS/bin:$PATH"

SRC=/mnt/d/WorkBudy/Bioprotect/LSTimeSeconds-github
DST="$HOME/lsts_github_build"
TC19="$HOME/tc19/linux/iphone/bin"

die() { echo "!! $*"; exit 1; }
[ -x "$TC19/clang" ] || die "clang 19 工具链不存在（$TC19/clang）"

rm -rf "$DST"; mkdir -p "$DST"
cp -r "$SRC"/. "$DST"/
# Windows 侧编辑过的文件可能带 CRLF，Theos/ldid 对 CRLF 敏感，统一转 LF
find "$DST" -type f \( -name "*.xm" -o -name "*.m" -o -name "*.h" -o -name "*.plist" -o -name "*.strings" -o -name "*.sh" -o -name "Makefile" -o -name "control" \) -exec sed -i 's/\r$//' {} \; 2>/dev/null

cd "$DST" || die "无法进入 $DST"
echo "=== 清理旧产物 ==="
make clean >/dev/null 2>&1 || true
rm -rf packages .theos

echo "=== 编译（clang 19 + ld64 956，arm64 + arm64e）==="
if ! make package FINALPACKAGE=1 \
    TARGET_CC="$TC19/clang" TARGET_CXX="$TC19/clang++" TARGET_LD="$TC19/clang++" \
    TARGET_CODESIGN="$TC19/ldid" 2>&1 | tail -50; then
    die "编译失败"
fi

DEB=$(ls -1t packages/*.deb 2>/dev/null | head -1)
[ -n "$DEB" ] || die "没有生成 deb"
echo "生成 deb: $DEB"

echo
echo "=== 解包，做 isa 认证补丁 ==="
rm -rf "$DST/repack"; mkdir -p "$DST/repack"
dpkg-deb -R "$DEB" "$DST/repack" || die "dpkg-deb -R 失败"

patch_isa() {
python3 - "$1" <<'PYEOF'
import struct, sys

p = sys.argv[1]
d = bytearray(open(p, 'rb').read())
if struct.unpack_from('>I', d, 0)[0] != 0xcafebabe:
    print('  跳过（不是 FAT）:', p)
    sys.exit(0)
nfat = struct.unpack_from('>I', d, 4)[0]
patched = skipped = 0
for i in range(nfat):
    ct, sub, off, sz, al = struct.unpack_from('>IIIII', d, 8 + i * 20)
    if ct != 0x0100000c or sub != 0x80000002:
        continue  # 只动 arm64e 切片（arm64 格式无认证概念）
    ncmds = struct.unpack_from('<I', d, off + 16)[0]
    q = off + 32
    for _ in range(ncmds):
        cmd, csz = struct.unpack_from('<II', d, q)
        if cmd == 0x19:  # LC_SEGMENT_64
            seg = bytes(d[q+8:q+24]).rstrip(b'\0').decode()
            if seg == '__DATA_CONST':
                nsects = struct.unpack_from('<I', d, q + 64)[0]
                so = q + 72
                for j in range(nsects):
                    b = so + j * 80
                    sn = bytes(d[b:b+16]).rstrip(b'\0').decode()
                    if sn != '__cfstring':
                        continue
                    fsize = struct.unpack_from('<Q', d, b + 40)[0]
                    foff = struct.unpack_from('<I', d, b + 48)[0]
                    for s in range(fsize // 32):
                        eo = off + foff + s * 32
                        raw = struct.unpack_from('<Q', d, eo)[0]
                        bind = (raw >> 62) & 1
                        auth = (raw >> 63) & 1
                        if not bind or auth:
                            skipped += 1
                            continue
                        ordinal = raw & 0xFFFFFF
                        nxt = (raw >> 51) & 0x7FF
                        newv = ((ordinal & 0xFFFFFF)
                                | (0x6AE1 << 32) | (1 << 48) | (2 << 49)
                                | (nxt << 51) | (1 << 62) | (1 << 63))
                        struct.pack_into('<Q', d, eo, newv)
                        patched += 1
        q += csz
open(p, 'wb').write(bytes(d))
print('  %s：isa 改写 %d 条，跳过 %d 条' % (p.split('/')[-1], patched, skipped))
PYEOF
}

DLDIR="$DST/repack/Library/MobileSubstrate/DynamicLibraries"
BNDLDIR="$DST/repack/Library/PreferenceBundles/LSTSPrefs.bundle"
DYLIB="$DLDIR/LSTimeSeconds.dylib"
PREFS="$BNDLDIR/LSTSPrefs"
[ -f "$DYLIB" ] || die "包里没有 LSTimeSeconds.dylib"
[ -f "$PREFS" ] || die "包里没有设置面板可执行文件 LSTSPrefs"

patch_isa "$DYLIB" || die "动态库 isa 补丁失败"
patch_isa "$PREFS" || die "设置面板 isa 补丁失败"

echo "=== 重签（ldid）与权限 ==="
"$TC19/ldid" -S "$DYLIB" || die "ldid 签名失败: dylib"
"$TC19/ldid" -S "$PREFS" || die "ldid 签名失败: prefs"
chmod 755 "$DYLIB" "$PREFS"
chmod 644 "$DLDIR/LSTimeSeconds.plist"
chmod 644 "$BNDLDIR/Root.plist" "$BNDLDIR/Info.plist"
chmod -R 755 "$BNDLDIR"/*.lproj 2>/dev/null || true

echo "=== 打包 ==="
FINAL_DEB="$SRC/com.sini921.lstimeseconds_0.0.8-1_iphoneos-arm64e.deb"
rm -f "$FINAL_DEB"
dpkg-deb -b -Zxz "$DST/repack" "$FINAL_DEB" || die "dpkg-deb -b 失败"

echo
echo "=== 产物 ==="
ls -lh "$FINAL_DEB"
dpkg-deb -c "$FINAL_DEB"
