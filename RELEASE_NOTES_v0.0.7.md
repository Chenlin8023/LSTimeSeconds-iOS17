## LSTimeSeconds iOS 17 修复版 v0.0.7（稳定版）

**推荐通过越狱源安装**（可自动收到更新）：

```
https://chenlin8023.github.io/
```

> 落地页：<https://chenlin8023.github.io/>

也可直接下载本页附件安装。实测设备：iPhone 15 Pro / iOS 17.2.1 / RootHide（`iphoneos-arm64e` 原生包）。

---

### 功能

- **锁屏实时秒数**：每秒递增，格式**自动跟随设备 12/24 小时制**（无手动切换项）
- **字号缩放** `0.60 ~ 1.25`（默认 0.88），以壁纸原始字号为绝对基准，不抖动
- **上下位置调节** `-100 ~ +100 pt`（默认 0），负值上移、正值下移，解除裁剪不截断
- 宽度按当前格式实测后重算，**水平自动居中**
- 长按进入壁纸自定义时**静默旁路**，滤镜 / 字体 / 景深编辑保持系统原样
- 熄屏暂停刷新省电，亮屏**毫秒级恢复**并立即校准
- 设置面板：启用开关 + 字号滑块 + 位置滑块 + 注销按钮

### 修复的原版问题

原版在 iOS 17 上"装了完全没反应"，是四个问题叠加：

1. `%ctor` 里只有 `hasPrefix("15")` / `hasPrefix("16")` 两个分支，iOS 17 一个 Hook 都没挂；
2. 面板的 PostNotification 写成 `com.b4db1r3.ocd/...`，与 dylib 监听的名字不符；
3. 旧键 `isUsingADO` 默认 false，残留配置让新实现误判"用户关了秒数"；
4. 字号每秒从"当前值"再乘比例，被系统还原后反复震荡（时钟抽搐）。

详见仓库 `docs/01-逆向与根因.md`。

### 关于 v0.0.8（已撤回）

v0.0.8 把设置面板换成了本仓库自建的 `PSListController` 子类，锁屏秒数正常，
但**进入「设置 → LSTimeSeconds」会闪退**。该版本已删除，源码已回退到
`vendor/LSTSPrefs.bundle`（与本次发布的面板二进制 sha256 逐字节一致）。
已经装过 0.0.8 的，请安装本版本覆盖，或在 Sileo 里选择 `0.0.7-1`。

### 全天候显示（AOD）

**不支持 AOD 暗屏走秒**：LTPO 在 AOD 下锁 1 Hz，且 `BacklightServicesHost` 的
Flipbook 会短路常规界面重绘。熄屏自动暂停，亮屏立即恢复。
完整说明见 `docs/03-全天候显示限制.md`。

### 安装

```bash
# 方式一：加源
#   Sileo → 软件源 → + → https://chenlin8023.github.io/ → 搜索 LSTimeSeconds

# 方式二：直接装 deb（RootHide 原生包，不要过转换器）
```

装完 **Respring** 一次。

**完整变更**：https://github.com/Chenlin8023/LSTimeSeconds-iOS17/commits/master
