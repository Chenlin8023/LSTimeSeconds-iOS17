# LSTimeSeconds rootless v0.0.7-5

在 0.0.7-4（iOS 16 熄屏唤醒冻结修复）基础上的低风险优化，**不改变刷新与停表逻辑**：

- **日志轮转**：`/var/mobile/Library/LSTimeSeconds.log` 超过 256KB 时改名为 `.1`
  （覆盖上一份备份），避免长期使用无限增长；最多每分钟检查一次。
- **秒针对齐**：首次创建的 1Hz 计时器对齐到下一个整秒（+10ms 余量），
  避免计时器相位与系统时钟错开导致秒数跳动不匀。
- 其他行为与 0.0.7-4 完全一致：不再依据熄屏布尔值跳过刷新，熄屏/唤醒不再停表。

## 验证

- iOS 16.0.3 rootless 真机：锁屏秒数、熄屏再亮屏、设置面板均正常。
- 静态检查：arm64 + arm64e，`pointer_format=12`，`__cfstring` 与
  `__objc_data` 类指针均已补 PAC，签名正常。

## 产物

```
com.sini921.lstimeseconds_0.0.7-5_iphoneos-arm64.deb
sha256 2006fa89d1911a8942efbc09ff4791e3e8b4427b48aabdc7fd23863e476ebb56
```
