// LSTRootListController.m
// LSTimeSeconds 设置面板 —— 从零实现，不依赖原作者编译好的 PreferenceBundle 二进制。
//
// 关键点：specifier 全部用代码创建，**不读 Root.plist / Root.strings**。
// RootHide 转换器会把 /var/jb 包重写成 /Library（jbroot 虚拟路径），而自建面板没有
// libroothide 的路径重定向。若走 loadSpecifiersFromPlistName:，在 RootHide 的
// Preferences 进程里解析不到 bundle 资源，初始化时拿不到 specifier 就会闪退
// （0.0.8 的闪退也是这一类）。纯代码 specifier 不碰文件，rootless 与转换后的
// RootHide 都能用。

#import "LSTRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <spawn.h>
#import <unistd.h>

extern char **environ;

static NSString *const kPrefDomain = @"com.b4db1r3.lstsprefs";
static NSString *const kNotifyReload = @"com.b4db1r3.lstsprefs/reloadPrefs";

// 面板文案内联，避免 NSLocalizedString 再去读 bundle 资源
static NSString *L(NSString *zh, NSString *en) {
    NSString *lang = [[NSLocale preferredLanguages] firstObject] ?: @"en";
    return [lang hasPrefix:@"zh"] ? zh : en;
}

@implementation LSTRootListController

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }

    NSMutableArray *specs = [NSMutableArray array];

    // ---- 基础功能 ----
    PSSpecifier *general = [PSSpecifier groupSpecifierWithName:L(@"基础功能", @"General")];
    [general setProperty:L(@"开启后锁屏时钟将显示秒数并每秒实时刷新；时间格式默认跟随设备系统 12/24 小时制设置。",
                           @"Enables seconds display on lockscreen. Format automatically follows device system 12/24 hour settings.")
                 forKey:@"footerText"];
    [specs addObject:general];

    PSSpecifier *enable = [PSSpecifier preferenceSpecifierNamed:L(@"启用插件与秒数显示", @"Enable Tweak & Seconds")
                                                        target:self
                                                           set:@selector(setPreferenceValue:specifier:)
                                                           get:@selector(readPreferenceValue:)
                                                        detail:nil
                                                          cell:PSSwitchCell
                                                          edit:nil];
    [enable setProperty:kPrefDomain forKey:@"defaults"];
    [enable setProperty:@"isEnable" forKey:@"key"];
    [enable setProperty:@YES forKey:@"default"];
    [enable setProperty:kNotifyReload forKey:@"PostNotification"];
    [specs addObject:enable];

    // ---- 时钟大小与位置 ----
    PSSpecifier *layout = [PSSpecifier groupSpecifierWithName:L(@"时钟大小与位置调节", @"Clock Size & Position")];
    [layout setProperty:L(@"大小缩放以设备原机字号为基准（推荐 0.88）。\n上下位置调节可向上（负值）或向下（正值）移动时钟。",
                          @"Scale is based on original poster font size (0.88 recommended).\nVertical Position lets you move the clock up (negative) or down (positive).")
                forKey:@"footerText"];
    [specs addObject:layout];

    PSSpecifier *scale = [PSSpecifier preferenceSpecifierNamed:L(@"时钟大小缩放", @"Clock Size Scale")
                                                       target:self
                                                          set:@selector(setPreferenceValue:specifier:)
                                                          get:@selector(readPreferenceValue:)
                                                       detail:nil
                                                         cell:PSSliderCell
                                                         edit:nil];
    [scale setProperty:kPrefDomain forKey:@"defaults"];
    [scale setProperty:@"fontScale" forKey:@"key"];
    [scale setProperty:@(0.88) forKey:@"default"];
    [scale setProperty:@(0.60) forKey:@"min"];
    [scale setProperty:@(1.25) forKey:@"max"];
    [scale setProperty:@YES forKey:@"showValue"];
    [scale setProperty:@YES forKey:@"isContinuous"];
    [scale setProperty:kNotifyReload forKey:@"PostNotification"];
    [specs addObject:scale];

    PSSpecifier *yOffset = [PSSpecifier preferenceSpecifierNamed:L(@"上下位置调节", @"Vertical Position Offset")
                                                         target:self
                                                            set:@selector(setPreferenceValue:specifier:)
                                                            get:@selector(readPreferenceValue:)
                                                         detail:nil
                                                           cell:PSSliderCell
                                                           edit:nil];
    [yOffset setProperty:kPrefDomain forKey:@"defaults"];
    [yOffset setProperty:@"yOffset" forKey:@"key"];
    [yOffset setProperty:@(0.0) forKey:@"default"];
    [yOffset setProperty:@(-100.0) forKey:@"min"];
    [yOffset setProperty:@(100.0) forKey:@"max"];
    [yOffset setProperty:@YES forKey:@"showValue"];
    [yOffset setProperty:@YES forKey:@"isContinuous"];
    [yOffset setProperty:kNotifyReload forKey:@"PostNotification"];
    [specs addObject:yOffset];

    // ---- AOD 说明 ----
    PSSpecifier *aod = [PSSpecifier groupSpecifierWithName:L(@"全天候显示 (AOD) 说明", @"Always-On Display (AOD) Notice")];
    [aod setProperty:L(@"【不支持全天候显示 (AOD)】\n由于 iOS 全天候显示硬件机制会将屏幕刷新率锁定为 1Hz，且底层 BacklightServices 渲染框架会拦截常规高频界面重绘，本插件不支持在 AOD 暗屏状态下持续走秒。\n\n熄屏或进入 AOD 时自动停止刷新以省电；一旦点亮屏幕，毫秒级恢复实时秒数。",
                      @"[Always-On Display (AOD) Not Supported]\nDue to the hardware locking AOD refresh rate to 1Hz and throttling regular UI updates, real-time seconds are not updated during AOD dim mode.\n\nTimer automatically pauses when the screen dims/sleeps, and resumes immediately when the screen wakes up.")
                forKey:@"footerText"];
    [specs addObject:aod];

    // ---- 快捷操作 ----
    PSSpecifier *actions = [PSSpecifier groupSpecifierWithName:L(@"快捷操作", @"Actions")];
    [specs addObject:actions];

    PSSpecifier *respring = [PSSpecifier preferenceSpecifierNamed:L(@"注销 SpringBoard 生效", @"Respring SpringBoard")
                                                          target:self
                                                             set:NULL
                                                             get:NULL
                                                          detail:nil
                                                            cell:PSButtonCell
                                                            edit:nil];
    // PSButtonCell 在不同 iOS 版本上分别读 action 或 buttonAction，两个都设置
    respring.buttonAction = @selector(respring);
    [respring setProperty:@"respring" forKey:@"action"];
    [specs addObject:respring];

    PSSpecifier *credits = [PSSpecifier groupSpecifierWithName:@""];
    [credits setProperty:L(@"LSTimeSeconds iOS 16/17 标准稳定版\nrootless（/var/jb）arm64 + arm64e 适配",
                           @"LSTimeSeconds iOS 16/17 Stable Edition\nRootless (/var/jb) arm64 + arm64e")
                  forKey:@"footerText"];
    [specs addObject:credits];

    _specifiers = specs;
    return _specifiers;
}

// Root.plist 的 PSButtonCell 通过 action = respring 派发到这里。
// rootless 的 killall 在 /var/jb/usr/bin；保留 /usr/bin 兜底，方便同一份源码在 rootful 下调试。
- (void)respring {
    const char *candidates[] = { "/var/jb/usr/bin/killall", "/usr/bin/killall" };
    for (unsigned int i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        if (access(candidates[i], X_OK) != 0) continue;
        pid_t pid = 0;
        const char *argv[] = { candidates[i], "-9", "SpringBoard", NULL };
        if (posix_spawn(&pid, candidates[i], NULL, NULL, (char *const *)argv, environ) == 0) {
            return;
        }
    }
}

@end
