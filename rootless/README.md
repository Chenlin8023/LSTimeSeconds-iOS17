# LSTimeSeconds · rootless（/var/jb）版

把已修复并验证过的 **LSTimeSeconds 0.0.7-1（RootHide / iphoneos-arm64e）** 迁移到
**rootless（/var/jb，iphoneos-arm64）**，适配 iOS 16–17 的 rootless 越狱环境
（Dopamine 2.x、palera1n rootless、TrollStore + Bootstrap）。

- 功能与 RootHide 版一致：锁屏实时秒数、字号缩放（0.60–1.25）、上下位置调节（±100pt）、
  12/24 小时制自动跟随、壁纸编辑态旁路、息屏暂停刷新。
- 配置域仍为 `com.b4db1r3.lstsprefs`，从 RootHide 版切换过来无需迁移配置。
- 包内全部落在 `/var/jb/Library/...`，设置面板由本目录源码编译（arm64 + arm64e）。

构建：

```bash
wsl -d Ubuntu-22.04 -- bash /mnt/d/WorkBudy/Bioprotect/LSTimeSeconds-rootless/build.sh
```

产物：

```
com.sini921.lstimeseconds_0.0.7-2_iphoneos-arm64.deb
```

详细差异、静态验证结果与真机验证清单见
[`docs/06-rootless适配.md`](docs/06-rootless适配.md)。

> 状态：**已通过全部静态检查；锁屏功能已在设备上验证，设置面板待复验**。
> 设置面板闪退已定位为 clang19 产物 `__DATA,__objc_data` 的 isa/superclass
> 缺少 PAC 认证（readClass SIGBUS），现由 `tools/patch_arm64e.py` 补齐；
> 面板 specifier 也改为纯代码创建。按版本策略，验证通过前不进入
> `https://chenlin8023.github.io/` 越狱源。
