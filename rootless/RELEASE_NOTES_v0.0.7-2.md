# LSTimeSeconds rootless v0.0.7-2

面向 **iOS 16–17 rootless（`/var/jb`）** 的 LSTimeSeconds，与 RootHide 版功能一致：

- 锁屏时钟实时秒数，自动跟随系统 12/24 小时制；
- 时钟字号缩放（0.60–1.25，基准为壁纸原始字号）；
- 上下位置调节（±100pt），解除裁剪；
- 长按进入壁纸编辑时自动旁路；
- 息屏暂停刷新、亮屏即时恢复（AOD 暗屏不走秒，硬件限制）。

## 安装

- 包架构 `iphoneos-arm64`，安装前缀 `/var/jb`；
- 依赖 `mobilesubstrate`（ElleKit 提供）与 `preferenceloader`；
- RootHide 设备请使用 `0.0.7-1 (iphoneos-arm64e)`，不要装本包。

## 本次修复

- 修正 rootless 版 dylib 的 substrate 依赖与 rpath（`/var/jb/usr/lib`、`/var/jb/Library/Frameworks`）；
- 设置面板改为源码编译，并改为纯代码构建 specifier；
- **修复设置面板闪退**：clang19/ld64 956 编出的 arm64e 类元数据缺少 PAC，
  `__DATA,__objc_data` 的 `isa` / `superclass` 为普通 bind/rebase，
  `libobjc readClass` 认证失败导致 SIGBUS。新增 `tools/patch_arm64e.py` 补齐：
  - `isa`：auth，diversity `0x6AE1`，addrDiv 1，key 2；
  - `superclass`：auth，diversity `0xB5AB`，addrDiv 1，key 2；
  - 同时保留原有 `__cfstring` isa 补丁。

补丁器已用 Xcode 编的原版面板做逐字节回归：处理后 sha256 不变
（`53205ad6…81acf`），与 Apple 链接器输出一致。

## 产物

```
com.sini921.lstimeseconds_0.0.7-2_iphoneos-arm64.deb
sha256 45877157ddfe7df911e5eebe4fe5142e00421493c22c91ef335b73940d229fc5
```
