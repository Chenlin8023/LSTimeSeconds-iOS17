# 06 · rootless（/var/jb）适配说明

本目录是 `0.0.7-1`（RootHide / iphoneos-arm64e 原生版）的 **rootless 分支构建**，
面向 **iOS 16–17 的 rootless 越狱环境**（Dopamine 2.x、palera1n rootless、
TrollStore + Bootstrap 等，统一使用 `/var/jb` 前缀、`iphoneos-arm64` 架构）。

> 版本号沿用 `0.0.7-1`，与 RootHide 版功能、配置键、界面完全一致；
> 两个包 `Package` 名相同、`Architecture` 不同，APT/Sileo 会按设备环境自动选择。

## 一、与 RootHide 版的关键差异

| 项目 | RootHide 版（已验证） | rootless 版（本目录） |
|---|---|---|
| 安装前缀 | 空（`/Library/...`） | `/var/jb` |
| 包架构 | `iphoneos-arm64e` | `iphoneos-arm64` |
| substrate 链接 | `@loader_path/.jbroot/usr/lib/libsubstrate.dylib` | `@rpath/CydiaSubstrate.framework/CydiaSubstrate` + rpath `/var/jb/usr/lib`、`/var/jb/Library/Frameworks` |
| 设置面板 | vendor 里 RootHide 转换过的原版二进制 | `prefs/` 源码编译（arm64 + arm64e） |
| 包内路径 | `Library/MobileSubstrate/...` | `var/jb/Library/MobileSubstrate/...` |

配置域、通知名、过滤规则都没有变：

- 配置域：`com.b4db1r3.lstsprefs`
- 刷新通知：`com.b4db1r3.lstsprefs/reloadPrefs`
- 注入进程：`com.apple.springboard`
- 配置回退读取路径已包含 `/var/jb/var/mobile/Library/Preferences/...`

## 二、为什么面板必须重新编译

RootHide 版的 `vendor/LSTSPrefs.bundle/LSTSPrefs` 依赖
`@loader_path/.jbroot/usr/lib/libroothide.dylib`，并且只通过 `jbroot()` 解析
`/usr/bin/killall`。这个依赖在 rootless 下不存在，直接复用会让 Preferences 进程
加载面板失败。

本目录改为 `prefs/LSTRootListController.m` 源码编译：

- **`specifiers` 全部用代码创建，不读 `Root.plist` / `Root.strings`**；
- respring 优先执行 `/var/jb/usr/bin/killall -9 SpringBoard`，并保留 `/usr/bin/killall` 兜底；
- 开关 / 滑块仍写入 `com.b4db1r3.lstsprefs`，与动态库使用同一份配置；
- `Root.plist` 保留在包内仅作参考，面板已不再依赖它。

### 面板闪退的真实根因：arm64e 类指针缺少 PAC（不是路径问题）

设备侧 `Preferences-*.ips` 的崩溃栈：

```
EXC_BAD_ACCESS (SIGBUS)
libobjc: readClass -> map_images -> dyld dlopen
-> NSBundle principalClass -> PSListController lazyLoadBundle -> 点击设置项
```

崩溃发生在 **dlopen 映射 ObjC 元数据**阶段，根本没走到 `specifiers`。
对比 Xcode 编的原版面板（`vendor`）与 VolumeManager 面板后确认：

| `__DATA,__objc_data` 字段 | Xcode 产物 | clang19 / ld64 956 产物 |
|---|---|---|
| class/metaclass `isa` | auth rebase/bind，div `0x6AE1`, key 2 | **普通 bind/rebase，无 PAC** |
| `superclass` | auth bind，div `0xB5AB`, key 2 | **普通 bind，无 PAC** |
| `cache` / `data` | plain bind / rebase | plain bind / rebase（一致） |
| `__objc_classlist` / `selrefs` / `classrefs` | plain | plain（一致） |

`readClass` 会按 arm64e ABI 对 isa/superclass 做指针认证，遇到未签名的指针就
`SIGBUS`。之前只补了 `__cfstring` 的 isa，漏了类元数据，所以面板在
`lazyLoadBundle` 加载阶段就崩了；动态库没有定义 ObjC 类，因此锁屏功能一直正常。

修复：`tools/patch_arm64e.py` 除了 `__cfstring`，还会把每个 `class_t` 的
`isa`（div `0x6AE1`）与 `superclass`（div `0xB5AB`）改写为 auth 指针。
**验证方法**：用该脚本处理 Xcode 编的原版面板，改写 12 条后文件 sha256
完全不变（`53205ad6…81acf`），证明补丁编码与 Apple 链接器逐字节一致。

此外面板的 `specifiers` 仍保持纯代码创建，不依赖 `Root.plist`（RootHide
路径随机化下更稳，文案按 `NSLocale` 内联）。

## 三、构建

```bash
wsl -d Ubuntu-22.04 -- bash /mnt/d/WorkBudy/Bioprotect/LSTimeSeconds-rootless/build.sh
```

流程：`make package`（rootless scheme，前缀 `/var/jb`）→ 解包 → 对
`LSTimeSeconds.dylib` 与 `LSTSPrefs` **两个** arm64e 二进制做
`tools/patch_arm64e.py` 补丁（`__cfstring` isa 与 `__objc_data` 的
isa/superclass 认证）→ `ldid -S` 重签 → 统一权限 → 重新打包。

产物：

```
com.sini921.lstimeseconds_0.0.7-2_iphoneos-arm64.deb
```

## 四、静态验证结果

构建脚本每次都会输出以下断言值（本次构建）：

| 检查项 | 结果 |
|---|---|
| dylib 切片 | arm64 + arm64e |
| 面板切片 | arm64 + arm64e |
| dylib 依赖 | `@rpath/CydiaSubstrate.framework/CydiaSubstrate`（无 jbroot / libroothide） |
| 面板依赖 | 全部系统框架，install_name `/var/jb/Library/PreferenceBundles/LSTSPrefs.bundle/LSTSPrefs` |
| arm64e pointer_format | 12（两个二进制都是） |
| `__cfstring` isa | dylib auth=30 / plain=0；面板 auth=43 / plain=0 |
| `__objc_data` 类指针 | 面板 isa=`auth_bind/rebase div=0x6AE1`、superclass=`auth_bind div=0xB5AB`（与 Xcode 产物一致） |
| 签名 | 两个二进制都有 LC_CODE_SIGNATURE，`ldid` 可读 |
| 包信息 | `Architecture: iphoneos-arm64`、`Depends: mobilesubstrate, preferenceloader` |
| 包内路径 | 全部位于 `/var/jb/Library/...` |

## 五、安装与真机验证

1. 用 Sileo / Zebra / Filza 安装 deb（rootless 环境**不要**过任何 RootHide 转换器）；
2. `Respring` 一次；
3. 点亮锁屏，确认秒数每秒递增；
4. 打开「设置 → LSTimeSeconds」，确认不闪退，能改字号 / 上下位置，能点「注销」；
5. 长按锁屏进入壁纸编辑，确认插件不干扰；
6. 日志：`/var/mobile/Library/LSTimeSeconds.log`（写不进时退到 `/tmp/LSTimeSeconds.log`），
   正常应看到：

```
>>> LSTimeSeconds ctor initialized in process SpringBoard (PID xxxx) <<<
loadPrefs: enabled=1, scale=0.88, yOffset=0.0, aodOpt=1
CSProminentDisplayViewController viewDidLoad
CSProminentTimeView didMoveToWindow: ON SCREEN
```

### 在 RootHide（隐根）设备上测试本 rootless 包

如果设备是 RootHide，需要先用 patcher 把本 deb 转成 roothide 包再安装：

1. 卸载旧版，重新用 patcher 转换**新构建**的 deb（面板已改为纯代码 specifier，转或不转都能用）；
2. 安装后 Respring；
3. 锁屏秒数正常、设置面板能打开即通过。

> 日常在 RootHide 上使用，仍建议装原生 roothide 版 `0.0.7-1 (iphoneos-arm64e)`，
> 那份经过真机长期验证；本 rootless 包主要用于 iOS 16/17 rootless 环境。

### 若面板闪退

1. 用 Filza 确认 `/var/jb/Library/PreferenceBundles/LSTSPrefs.bundle/LSTSPrefs` 权限 755；
2. 抓 Preferences 进程的 `.ips`（「设置 → 隐私与安全性 → 分析与改进 → 分析数据」）；
3. 回退：在 Sileo 中卸载本包（rootless 版与 RootHide 版包名相同，不要同时装两个环境）。

## 六、版本策略

与主仓库一致：**只把真机验证通过的构建放进越狱源**。
本 rootless 包在通过 iOS 16/17 真机验证前，仅作为测试包，不更新 `https://chenlin8023.github.io/` 的索引。
