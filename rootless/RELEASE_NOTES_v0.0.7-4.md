# LSTimeSeconds rootless v0.0.7-4

面向 **iOS 16–17 rootless（`/var/jb`）** 的 LSTimeSeconds。功能与 RootHide 版一致：

- 锁屏时钟实时秒数，自动跟随系统 12/24 小时制；
- 时钟字号缩放（0.60–1.25，基准为壁纸原始字号）；
- 上下位置调节（±100pt），解除裁剪；
- 长按进入壁纸编辑时自动旁路；
- 熄屏后亮屏立即恢复刷新（AOD 暗屏不走秒，硬件限制）。

## 本次修复（相对 0.0.7-2）

- **修复 iOS 16 熄屏再亮屏后秒数冻结**：
  - `timerTick` 不再依据 `g_isScreenOff` 跳过刷新；iOS 16 的 backlight/锁屏通知会乱序，
    `state=2` 可能晚于唤醒通知到达，旧逻辑会把状态永久卡在 YES；
  - 熄屏、背光 `state=2`、视图注销都不再停止计时器，避免“停了没人重启”。
- 保持 0.0.7-2 的通知线程模型与计时器创建方式不变，仅做上述最小改动。
- 设置面板与 arm64e 类元数据 PAC 继续由 `tools/patch_arm64e.py` 处理。

> 0.0.7-3 曾尝试“通知回调统一切主线程 + 每秒自愈”，在 iOS 16.0.3 触发安全模式：
> `runOnMain(^{...})` 的全局 block 被 ARC retain，而 clang19/ld64 给 block isa
> 生成的是无 PAC 的 plain bind，`objc_msgSend(block, "retain")` 认证失败 → SIGBUS。
> 该方案已撤回，0.0.7-4 不再引入 block 字面量。

## 验证

- iOS 16.0.3 rootless 真机：亮屏秒数正常，熄屏再亮屏恢复，设置面板正常；
- 静态检查：arm64 + arm64e，`pointer_format=12`，`__cfstring` 与
  `__objc_data` 类指针均已补 PAC，签名正常。

## 产物

```
com.sini921.lstimeseconds_0.0.7-4_iphoneos-arm64.deb
sha256 42b90875155d39d1caf2b6ca4e764cd2e4d5a3a5edf6f4659db534f44b9a577f
```
