## LSTimeSeconds iOS 17 修复版 v0.0.8

修复原版在 **iOS 17 上完全不生效**的问题，并补上 iPhone 原生锁屏没有的**时钟字号缩放**与**上下位置调节**。

实测设备：iPhone 15 Pro / iOS 17.2.1 / RootHide 越狱（`iphoneos-arm64e` 原生包）。

---

### 修复了什么

原版 `LSTimeSeconds.dylib` 反汇编后能对上四个问题，任何一个不修，现象都是"装了完全没反应"：

1. **版本被硬编码**：构造函数只有 `hasPrefix:@"15"` / `hasPrefix:@"16"` 两个分支，iOS 17 两条都不命中，**一个 Hook 都没挂**。
2. **设置通知名拼错**：面板发的是 `com.b4db1r3.ocd/reloadPrefs`，dylib 监听 `com.b4db1r3.lstsprefs/reloadPrefs`。
3. **旧键名把秒数关掉**：早期 `isUsingADO` 默认 false，残留配置让新实现误判为"用户关了秒数"。
4. **宽度/字号基准取错**：文字只按 5 字符排版；字号每秒从"当前值"再乘比例，被系统还原后反复震荡（时钟抽搐）。

相关细节见仓库 `docs/01-逆向与根因.md`。

### 现在能做到

- 锁屏时钟**每秒递增**，格式**自动跟随设备 12/24 小时制**（不再有手动切换项）
- **字号缩放** `0.60 ~ 1.25`（默认 0.88），以壁纸原始字号为绝对基准，不抽搐
- **上下位置调节** `-100 ~ +100 pt`（默认 0），负值上移、正值下移，解除裁剪不截断
- 宽度按当前格式实测后重新计算，**水平自动居中**
- 长按进入壁纸自定义时**静默旁路**，滤镜/字体/景深编辑保持系统原样
- 熄屏暂停刷新省电，亮屏**毫秒级恢复**并立即校准

### 全天候显示（AOD）

**不支持在 AOD 暗屏下持续走秒**，原因是系统层面的双重限制：

- LTPO 面板在 AOD 下的物理刷新率被驱动锁到 **1 Hz**；
- iOS 17 `BacklightServicesHost` 的 Flipbook 机制会短路常规界面重绘，`NSTimer`/`dispatch_source` 每秒都跑了，但更新到不了屏幕。

我们做过 GCD Mach 定时器 + `CATransaction flush` 强制提交帧的实验分支，真机上仍无法稳定穿透，故未作为正式功能发布。完整说明见 `docs/03-全天候显示限制.md`。

---

### 安装

1. 下载 `com.sini921.lstimeseconds_0.0.8-1_iphoneos-arm64e.deb`
2. Sileo / Zebra / Filza 安装 —— **直接安装，不要过 RootHide 转换器**（转换器会重写二进制并破坏 arm64e 指针认证）
3. Respring 一次
4. 设置 → LSTimeSeconds 调整字号与位置

### 附：v0.0.7 回退包

`com.sini921.lstimeseconds_0.0.7-1_iphoneos-arm64e.deb` 是**已在真机验证过的版本**。
它与 0.0.8 的**锁屏引擎完全相同**，唯一区别是设置面板仍使用原作者编译好的二进制；
0.0.8 的面板改由本仓库源码（`LSTRootListController.m`）编译，以便仓库可完整自编译。

若 0.0.8 的面板出现任何异常（打不开、滑块不保存等），装 0.0.7 即可，功能不受影响。

### 自行编译

```bash
wsl -d Ubuntu-22.04 -- bash /path/to/LSTimeSeconds/build.sh
```

需要 Theos + iPhoneOS16.5.sdk + clang 19（L1ghtmann）+ ld64 956 + ldid。
`build.sh` 会在打包后对 **dylib 与设置面板两个 arm64e 二进制**都补 `__cfstring` isa 认证并 `ldid` 重签 ——
两个进程都是 arm64e，漏补任何一个都会一加载就 SIGBUS。

**完整变更**：https://github.com/Chenlin8023/LSTimeSeconds-iOS17/commits/master
