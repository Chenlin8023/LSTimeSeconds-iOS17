# LSTimeSeconds · rootless（/var/jb）版

把已修复并验证过的 **LSTimeSeconds 0.0.7-1（RootHide / iphoneos-arm64e）** 迁移到
**rootless（/var/jb，iphoneos-arm64）**，适配 iOS 16–17 的 rootless 越狱环境
（Dopamine 2.x、palera1n rootless、TrollStore + Bootstrap）。

- 功能与 RootHide 版一致：锁屏实时秒数、字号缩放（0.60–1.25）、上下位置调节（±100pt）、
  12/24 小时制自动跟随、壁纸编辑态旁路、息屏后亮屏立即恢复刷新。
- 配置域仍为 `com.b4db1r3.lstsprefs`，从 RootHide 版切换过来无需迁移配置。
- 包内全部落在 `/var/jb/Library/...`，设置面板由本目录源码编译（arm64 + arm64e）。

构建：

```bash
# 在 WSL 里执行，路径换成你的仓库所在目录
bash /mnt/<你的路径>/LSTimeSeconds-iOS17/rootless/build.sh
```

产物：

```
com.sini921.lstimeseconds_0.0.7-4_iphoneos-arm64.deb
```

详细差异、静态验证结果与真机验证清单见
[`docs/06-rootless适配.md`](docs/06-rootless适配.md)。

> 状态：**真机已验证**（iOS 16.0.3 rootless：熄屏再亮屏秒数恢复、设置面板正常）。
> 0.0.7-4 是最小改动版：只去掉熄屏状态判断和多余的停表，不引入 block 自愈逻辑。
> 设置面板与类元数据 PAC 由 `tools/patch_arm64e.py` 处理。
