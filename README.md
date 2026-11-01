# LSTimeSeconds · iOS 17 修复版

把 iPhone 越狱插件 **LSTimeSeconds（锁屏时钟显示秒数）** 修好并适配到
**iOS 17 RootHide（iphoneos-arm64e 原生）**，另外补上 iPhone 原生锁屏没有的
**时钟字号缩放**与**上下位置调节**。

> 实测设备：**iPhone 15 Pro / iOS 17.2.1 / RootHide 越狱**
> 状态：亮屏锁屏下秒数每秒递增、字号与垂直位置可调、长按进入壁纸编辑不再冲突。

**当前版本：v0.0.8**（源码可完整自编译，设置面板也是本仓库源码编出来的）

---

## 一、原版为什么在 iOS 17 上完全不生效

把原版 `LSTimeSeconds.dylib` 反汇编后可以逐条对上四个问题，**只要还有一个没修，现象都是「什么都没发生」**：

| # | 问题 | 证据 / 机理 |
|---|---|---|
| 1 | **系统版本被硬编码** | 构造函数里只有 `hasPrefix:@"15"` 与 `hasPrefix:@"16"` 两个分支。iOS 17.2.1 两条都不命中 → **一个 Hook 都没挂**。这是"装了等于没装"的根因 |
| 2 | **设置面板通知名写错** | `Root.plist` 里 `PostNotification` 写成 `com.b4db1r3.ocd/reloadPrefs`，动态库监听的是 `com.b4db1r3.lstsprefs/reloadPrefs`。改设置永远通知不到 SpringBoard |
| 3 | **旧默认值把秒数关掉** | 早期配置键叫 `isUsingADO`，默认 `false`。磁盘上残留这份配置时，新键不存在、代码回退读旧键 → 秒数开关被判定为关，定时器当场停掉 |
| 4 | **时钟文字宽度按 5 字符排版** | 系统只为 `HH:mm` 预留宽度，追加 `:ss` 成 8 字符后会挤压或截断，需要重算宽度并重新居中 |

修复后的做法（详见 [`docs/01-逆向与根因.md`](docs/01-逆向与根因.md)）：

- **不再判版本**：直接挂 `CoverSheetKit` 的 `CSProminentDisplayViewController` /
  `CSProminentTimeView`，同时保留 `SBFLockScreenDateView` 兜底；
- **视图驱动**：以 `didMoveToWindow` / `viewWillAppear` / `viewIsAppearing` 为准注册活跃时钟，
  进屏幕就起定时器、离屏就注销，不依赖会被 iOS 17 跳过的旧生命周期；
- **四通道写文字**：推进内部 `_date` → `setOverrideString:` → `textLabel` 文本 →
  `_updateTimeString`，任何一条渲染路径都能拿到最新秒数；
- **单次锚定基准**：原机字号在第一帧缓存成"绝对基准"，之后每次都从基准算，杜绝
  "每秒被系统还原一次字号"导致的抽搐抖动。

---

## 二、功能

- **实时秒数**：锁屏时钟每秒递增，格式**自动跟随设备系统 12/24 小时制**（不提供手动切换，减少误配）。
- **字号缩放**：`0.60 ~ 1.25`，默认 `0.88`。基准永远是壁纸原本设定的字号，只做等比缩放。
- **上下位置调节**：`-100 ~ +100` pt，默认 `0` 为系统原位。负值上移、正值下移，
  并解除裁剪（`clipsToBounds = NO`），把时钟挪到灵动岛附近也不会被截断 —— **iPhone 原生锁屏没有这个能力**。
- **自动居中**：宽度按当前格式实测字符串重新计算，水平始终居中。
- **长按不冲突**：检测到海报编辑态（`usesEditingLayout` / `Switcher` / `Gallery`）时插件静默旁路，
  长按自定义壁纸、滤镜、字体挑选全部保持系统原样。
- **省电**：息屏自动挂起刷新，亮屏毫秒级恢复。

### 全天候显示（AOD）说明

**本版本不支持在 AOD 暗屏状态下持续走秒。** 原因不是代码写错了：

- iPhone 进入 AOD 后，ProMotion LTPO 屏幕的物理刷新率被底层驱动锁到 **1 Hz**；
- iOS 17 的 `BacklightServicesHost` / `BLSHAlwaysOnPresentationEngine` 会用
  Flipbook 机制**提前定格画面**并抑制常规界面重绘，普通定时器推进的 UI 更新在暗屏期间
  根本不会被渲染，直到分针满 60 秒触发一次全局刷新。

因此 AOD 暗屏下插件会主动暂停刷新（省电且避免无效唤醒），**点亮屏幕瞬间立即接上真实秒数**。
我们做过一个用 GCD Mach 定时器 + `CATransaction flush` 强行提交帧的实验分支，在真机上
仍无法稳定穿透该限制，故未作为正式功能发布。

---

## 三、安装

从 [Releases](../../releases) 下载 `release` 里的 deb，用 Sileo / Zebra / Filza 安装，
然后 **Respring 一次**。

> ⚠️ 本包是 **RootHide 原生包**（`iphoneos-arm64e`，安装前缀为空）。
> **直接安装，不要过 RootHide 转换器** —— 转换器会重写二进制并破坏 arm64e 的指针认证。

包内容：

```
Library/
├── MobileSubstrate/DynamicLibraries/
│   ├── LSTimeSeconds.dylib      # 注入 com.apple.springboard
│   └── LSTimeSeconds.plist      # 过滤器
├── PreferenceBundles/
│   └── LSTSPrefs.bundle/        # 设置面板（本仓库源码编译）
└── PreferenceLoader/Preferences/
    └── LSTSPrefs.plist          # 设置入口
```

设置项写在 `com.b4db1r3.lstsprefs`（沿用原版域名，便于从旧版平滑升级）：

| 键 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `isEnable` | bool | true | 启用插件与秒数显示 |
| `fontScale` | float | 0.88 | 字号缩放比例 |
| `yOffset` | float | 0.0 | 垂直偏移（pt） |

> 想彻底回到原生：卸载后执行
> `killall -9 SpringBoard`，或删掉
> `/var/mobile/Library/Preferences/com.b4db1r3.lstsprefs.plist`。

---

## 四、自行编译

需要 Theos + iOS SDK，以及一个能给 arm64e 出正确 chained fixups 的工具链。
本项目在 **clang 19（L1ghtmann Linux 工具链）+ ld64 956 + ldid(Procursus)** 下验证通过。

```bash
# Windows 侧用 WSL 跑
wsl -d Ubuntu-22.04 -- bash /path/to/LSTimeSeconds/build.sh
```

`build.sh` 做的事：`make package` → 解包 → **给两个 arm64e 二进制的 `__cfstring` isa
补认证** → `ldid` 重签 → `dpkg-deb -b -Zxz` 重打包。

### 为什么必须补 isa 再重签

SpringBoard 与 Preferences 都是 **arm64e** 进程。clang 19 给 arm64e 编 `CFSTR` 常量时，
`__cfstring` 的 isa 记的是普通 `ARM64_RELOC_UNSIGNED`，ld64 据此在 chained fixups 里写成
"无 PAC 的普通 bind"。arm64e 进程里 `objc_msgSend` 遇到常量字符串接收者要做指针认证，
未签名即 **SIGBUS → 安全模式**。

Xcode 编的原版这里是 `auth bind`：`diversity=0x6AE1, addrDiv=1, key=2`。
`build.sh` 把每个 isa 槽按同样参数改写，再重签。**动态库和设置面板可执行文件两个都要补**
（两个进程都是 arm64e）。细节见 [`docs/02-构建与安装.md`](docs/02-构建与安装.md)。

---

## 五、目录

```
.
├── LSTimeSeconds.xm            # 动态库主逻辑（Hook / 定时器 / 排版）
├── LSTimeSeconds.plist         # MobileLoader 过滤器（仅 springboard）
├── LSTRootListController.h/.m  # 设置面板控制器（自建，非第三方二进制）
├── Makefile                    # tweak + bundle 两个 target
├── control                     # Debian 包信息
├── build.sh                    # WSL 一键构建（含 arm64e isa 补丁）
├── libsubstrate_roothide.tbd   # roothide 版 substrate stub
├── layout/                     # 打进包的静态资源（面板 UI 与本地化）
└── docs/
    ├── 01-逆向与根因.md
    ├── 02-构建与安装.md
    └── 03-全天候显示限制.md
```

## 六、致谢与许可

- 原插件 **LSTimeSeconds** 作者：**b4db1r3 & SINI**，本仓库沿用其配置域名与包名，
  便于旧版本平滑升级；设置面板 UI（`Root.plist` / 本地化 / 图标）继承自其设计。
- 本仓库的修复代码、重建的设置面板控制器、构建脚本以 **MIT** 发布，见 [LICENSE](LICENSE)。

遇到问题请附上 `Filza` 里的 `/var/mobile/Library/LSTimeSeconds.log`（插件诊断日志）
与设备型号 / 系统版本提 issue。
