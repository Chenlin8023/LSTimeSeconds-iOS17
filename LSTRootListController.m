// LSTRootListController.m
// LSTimeSeconds 设置面板 —— 从零实现，不依赖原作者编译好的 PreferenceBundle 二进制。
//
// 只做两件事：
//   1) 用 Preferences 框架的标准机制加载 Root.plist（开关 / 滑块由 PSListController 自动读写
//      com.b4db1r3.lstsprefs，并存进同一份 plist，动态库读的就是同一份配置）；
//   2) 提供 Root.plist 里 PSButtonCell 的 respring 动作。

#import "LSTRootListController.h"
#import <spawn.h>
#import <unistd.h>

extern char **environ;

@implementation LSTRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// Root.plist 的 PSButtonCell 通过 action = respring 派发到这里
- (void)respring {
    pid_t pid = 0;
    const char *argv[] = { "killall", "-9", "SpringBoard", NULL };
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)argv, environ);
}

@end
