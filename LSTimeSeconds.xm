#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <math.h>

static NSString *const kPrefDomain = @"com.b4db1r3.lstsprefs";
static NSString *const kNotifyReload = @"com.b4db1r3.lstsprefs/reloadPrefs";

// Preferences
static BOOL pref_enabled = YES;
static CGFloat pref_fontScale = 0.88f; // Default 88% scale for 8 characters
static CGFloat pref_yOffset = 0.0f;    // Vertical offset (points)
static BOOL pref_aodOptimize = YES;

static NSTimer *g_secondsTimer = nil;
static NSHashTable *g_activeTimeViews = nil;
static NSHashTable *g_activeDateViews = nil;
static BOOL g_isScreenOff = NO;

static const char *kOriginalFontSizeKey = "kOriginalFontSizeKey";
static const char *kOriginalYOffsetKey = "kOriginalYOffsetKey";

// Diagnostic Logger
static void writeLog(const char *format, ...) {
    va_list args;
    va_start(args, format);
    char buf[1024];
    vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);
    
    NSLog(@"[LSTimeSeconds] %s", buf);
    FILE *f = fopen("/var/mobile/Library/LSTimeSeconds.log", "a");
    if (!f) f = fopen("/tmp/LSTimeSeconds.log", "a");
    if (f) {
        time_t now = time(NULL);
        char tbuf[64];
        strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", localtime(&now));
        fprintf(f, "[%s] %s\n", tbuf, buf);
        fclose(f);
    }
}

// Check if view is currently in Poster Edit/Customization Mode (long-press gallery)
static BOOL isEditingPoster(UIView *view) {
    if (!view) return NO;
    UIView *cur = view;
    while (cur) {
        if ([cur respondsToSelector:@selector(usesEditingLayout)]) {
            if ([(id)cur performSelector:@selector(usesEditingLayout)]) {
                return YES;
            }
        }
        NSString *cls = NSStringFromClass([cur class]);
        if ([cls containsString:@"Editing"] || [cls containsString:@"Switcher"] || [cls containsString:@"Gallery"]) {
            return YES;
        }
        cur = cur.superview;
    }
    return NO;
}

// Preference Reader (reads cfprefsd with synchronize, plus direct file fallback)
static id readPref(NSString *key) {
    CFPreferencesAppSynchronize((CFStringRef)kPrefDomain);
    CFPropertyListRef val = CFPreferencesCopyAppValue((CFStringRef)key, (CFStringRef)kPrefDomain);
    if (val != NULL) {
        return (__bridge_transfer id)val;
    }
    
    NSArray *paths = @[
        @"/var/mobile/Library/Preferences/com.b4db1r3.lstsprefs.plist",
        @"/var/jb/var/mobile/Library/Preferences/com.b4db1r3.lstsprefs.plist",
        @"/.jbroot/var/mobile/Library/Preferences/com.b4db1r3.lstsprefs.plist"
    ];
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d && [d objectForKey:key] != nil) {
            return [d objectForKey:key];
        }
    }
    return nil;
}

static id getIvarSafe(id obj, const char *name) {
    if (!obj) return nil;
    @try {
        NSString *key = [NSString stringWithUTF8String:name];
        id val = [obj valueForKey:key];
        if (val) return val;
    } @catch (NSException *e) {}
    
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (ivar) {
        return object_getIvar(obj, ivar);
    }
    return nil;
}

static void startTimerIfNeeded(void);
static void stopTimer(void);
static void updateAllActiveViews(void);

static void loadPrefs(void) {
    id valEnabled = readPref(@"isEnable");
    pref_enabled = (valEnabled != nil) ? [valEnabled boolValue] : YES;
    
    id valScale = readPref(@"fontScale");
    if (valScale) {
        pref_fontScale = [valScale floatValue];
        if (pref_fontScale < 0.5f || pref_fontScale > 1.5f) {
            pref_fontScale = 0.88f;
        }
    } else {
        pref_fontScale = 0.88f;
    }
    
    id valY = readPref(@"yOffset");
    if (valY) {
        pref_yOffset = [valY floatValue];
        if (pref_yOffset < -150.0f || pref_yOffset > 150.0f) {
            pref_yOffset = 0.0f;
        }
    } else {
        pref_yOffset = 0.0f;
    }
    
    id valAOD = readPref(@"aodOptimize");
    pref_aodOptimize = valAOD ? [valAOD boolValue] : YES;
    
    writeLog("loadPrefs: enabled=%d, scale=%.2f, yOffset=%.1f, aodOpt=%d",
             pref_enabled, pref_fontScale, pref_yOffset, pref_aodOptimize);
}

// Automatically follows device system settings (24h vs 12h) and appends seconds
static NSString *getEffectiveDateFormat(void) {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setLocale:[NSLocale currentLocale]];
    [df setDateStyle:NSDateFormatterNoStyle];
    [df setTimeStyle:NSDateFormatterShortStyle];
    NSString *sysFormat = df.dateFormat;
    if ([sysFormat containsString:@"H"] || [sysFormat containsString:@"k"]) {
        return @"HH:mm:ss";
    } else if ([sysFormat containsString:@"a"]) {
        return @"h:mm:ss a";
    } else {
        return @"hh:mm:ss";
    }
}

// Update single CSProminentTimeView instance
static void updateTimeViewInstance(UIView *timeView) {
    if (!timeView || !pref_enabled) return;
    if (isEditingPoster(timeView)) return; // Never interfere during poster customization
    
    NSString *format = getEffectiveDateFormat();
    if (!format) return;
    
    NSDateFormatter *tf = nil;
    if ([(UIView *)timeView respondsToSelector:@selector(timeFormatter)]) {
        tf = [(id)timeView valueForKey:@"timeFormatter"];
    }
    if (!tf) {
        tf = (NSDateFormatter *)getIvarSafe(timeView, "_timeFormatter");
    }
    
    NSDate *now = [NSDate date];
    NSString *timeStr = nil;
    if (tf) {
        [tf setDateFormat:format];
        timeStr = [tf stringFromDate:now];
    } else {
        NSDateFormatter *fallback = [[NSDateFormatter alloc] init];
        [fallback setDateFormat:format];
        timeStr = [fallback stringFromDate:now];
    }
    
    if (timeStr) {
        // 1. Advance the internal _date ivar to NOW so internal methods never format stale time
        Ivar dateIvar = class_getInstanceVariable(object_getClass(timeView), "_date");
        if (dateIvar) {
            object_setIvar(timeView, dateIvar, now);
        }
        
        // 2. setOverrideString (highest priority text override on posters)
        if ([(UIView *)timeView respondsToSelector:@selector(setOverrideString:)]) {
            [(id)timeView performSelector:@selector(setOverrideString:) withObject:timeStr];
        }
        
        // 3. update textLabel directly
        UIView *label = nil;
        if ([(UIView *)timeView respondsToSelector:@selector(textLabel)]) {
            label = [(id)timeView valueForKey:@"textLabel"];
        }
        if (!label) {
            label = (UIView *)getIvarSafe(timeView, "_textLabel");
        }
        if (label) {
            if ([label respondsToSelector:@selector(setString:)]) {
                [(id)label performSelector:@selector(setString:) withObject:timeStr];
            } else if ([label respondsToSelector:@selector(setText:)]) {
                [(UILabel *)label setText:timeStr];
            }
        }
        
        // 4. _updateTimeString
        if ([(UIView *)timeView respondsToSelector:@selector(_updateTimeString:)]) {
            [(id)timeView performSelector:@selector(_updateTimeString:) withObject:timeStr];
        } else if ([(UIView *)timeView respondsToSelector:@selector(_updateTimeString)]) {
            [(id)timeView performSelector:@selector(_updateTimeString)];
        }
    }
    
    [timeView setNeedsLayout];
}

// Update single SBFLockScreenDateView instance
static void updateDateViewInstance(UIView *dateView) {
    if (!dateView || !pref_enabled) return;
    if (isEditingPoster(dateView)) return;
    
    UIView *label = nil;
    if ([(UIView *)dateView respondsToSelector:@selector(timeLabel)]) {
        label = [(id)dateView valueForKey:@"timeLabel"];
    }
    if (!label) {
        label = (UIView *)getIvarSafe(dateView, "_timeLabel");
    }
    if (!label) return;
    
    NSString *format = getEffectiveDateFormat();
    if (!format) return;
    
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:format];
    NSString *str = [df stringFromDate:[NSDate date]];
    
    if ([label respondsToSelector:@selector(setText:)]) {
        [(UILabel *)label setText:str];
    } else if ([label respondsToSelector:@selector(setString:)]) {
        [(id)label performSelector:@selector(setString:) withObject:str];
    }
    [dateView setNeedsLayout];
}

static void updateAllActiveViews(void) {
    if (g_activeTimeViews) {
        for (UIView *tv in [g_activeTimeViews allObjects]) {
            if (!isEditingPoster(tv)) {
                updateTimeViewInstance(tv);
            }
        }
    }
    if (g_activeDateViews) {
        for (UIView *dv in [g_activeDateViews allObjects]) {
            if (!isEditingPoster(dv)) {
                updateDateViewInstance(dv);
            }
        }
    }
}

static void timerTick(void) {
    if (g_isScreenOff && pref_aodOptimize) {
        return;
    }
    if (!pref_enabled) {
        stopTimer();
        return;
    }
    updateAllActiveViews();
}

static void startTimerIfNeeded(void) {
    if (!pref_enabled) return;
    if (g_secondsTimer && [g_secondsTimer isValid]) {
        return;
    }
    g_secondsTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        timerTick();
    }];
    if (g_secondsTimer) {
        [[NSRunLoop mainRunLoop] addTimer:g_secondsTimer forMode:NSRunLoopCommonModes];
        writeLog("startTimerIfNeeded: Timer running");
    }
}

static void stopTimer(void) {
    if (g_secondsTimer) {
        [g_secondsTimer invalidate];
        g_secondsTimer = nil;
        writeLog("stopTimer: Timer stopped");
    }
}

static void registerActiveTimeView(UIView *tv) {
    if (!g_activeTimeViews) {
        g_activeTimeViews = [NSHashTable weakObjectsHashTable];
    }
    if (tv && ![g_activeTimeViews containsObject:tv]) {
        [g_activeTimeViews addObject:tv];
        writeLog("registerActiveTimeView: count=%lu", (unsigned long)[g_activeTimeViews count]);
    }
    if (pref_enabled) {
        startTimerIfNeeded();
    }
}

static void unregisterActiveTimeView(UIView *tv) {
    if (g_activeTimeViews && tv) {
        [g_activeTimeViews removeObject:tv];
    }
    if ([g_activeTimeViews count] == 0 && [g_activeDateViews count] == 0) {
        if (pref_aodOptimize) {
            stopTimer();
        }
    }
}

static void registerActiveDateView(UIView *dv) {
    if (!g_activeDateViews) {
        g_activeDateViews = [NSHashTable weakObjectsHashTable];
    }
    if (dv && ![g_activeDateViews containsObject:dv]) {
        [g_activeDateViews addObject:dv];
    }
    if (pref_enabled) {
        startTimerIfNeeded();
    }
}

static void unregisterActiveDateView(UIView *dv) {
    if (g_activeDateViews && dv) {
        [g_activeDateViews removeObject:dv];
    }
    if ([g_activeTimeViews count] == 0 && [g_activeDateViews count] == 0) {
        if (pref_aodOptimize) {
            stopTimer();
        }
    }
}

static void onReloadNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    writeLog("onReloadNotification received!");
    loadPrefs();
    if (pref_enabled) {
        startTimerIfNeeded();
        if (g_activeTimeViews) {
            for (UIView *tv in [g_activeTimeViews allObjects]) {
                if (!isEditingPoster(tv)) {
                    updateTimeViewInstance(tv);
                    [tv setNeedsLayout];
                }
            }
        }
        if (g_activeDateViews) {
            for (UIView *dv in [g_activeDateViews allObjects]) {
                if (!isEditingPoster(dv)) {
                    updateDateViewInstance(dv);
                    [dv setNeedsLayout];
                }
            }
        }
    } else {
        stopTimer();
    }
}

static void onScreenBlanked(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    g_isScreenOff = YES;
    writeLog("onScreenBlanked: screen off");
    if (pref_aodOptimize) {
        stopTimer();
    }
}

static void onScreenUnblanked(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    g_isScreenOff = NO;
    writeLog("onScreenUnblanked: screen awake");
    if (pref_enabled) {
        startTimerIfNeeded();
        updateAllActiveViews();
    }
}

%hook CSProminentDisplayViewController

- (void)viewDidLoad {
    %orig;
    writeLog("CSProminentDisplayViewController viewDidLoad");
    UIView *dispView = ((UIViewController *)self).view;
    if (dispView && !isEditingPoster(dispView)) {
        UIView *tv = (UIView *)getIvarSafe(dispView, "_timeView");
        if (tv) {
            registerActiveTimeView(tv);
            updateTimeViewInstance(tv);
        }
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    writeLog("CSProminentDisplayViewController viewWillAppear");
    g_isScreenOff = NO;
    UIView *dispView = ((UIViewController *)self).view;
    if (dispView && !isEditingPoster(dispView)) {
        UIView *tv = (UIView *)getIvarSafe(dispView, "_timeView");
        if (tv) {
            registerActiveTimeView(tv);
            updateTimeViewInstance(tv);
        }
    }
    if (pref_enabled) {
        startTimerIfNeeded();
    }
}

- (void)viewIsAppearing:(BOOL)animated {
    %orig;
    g_isScreenOff = NO;
    UIView *dispView = ((UIViewController *)self).view;
    if (dispView && !isEditingPoster(dispView)) {
        UIView *tv = (UIView *)getIvarSafe(dispView, "_timeView");
        if (tv) {
            registerActiveTimeView(tv);
            updateTimeViewInstance(tv);
        }
    }
    if (pref_enabled) {
        startTimerIfNeeded();
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    g_isScreenOff = NO;
    UIView *dispView = ((UIViewController *)self).view;
    if (dispView && !isEditingPoster(dispView)) {
        UIView *tv = (UIView *)getIvarSafe(dispView, "_timeView");
        if (tv) {
            registerActiveTimeView(tv);
            updateTimeViewInstance(tv);
        }
    }
    if (pref_enabled) {
        startTimerIfNeeded();
    }
}

%end

%hook CSProminentTimeView

- (void)didMoveToWindow {
    %orig;
    UIView *vSelf = (UIView *)self;
    if (vSelf.window != nil) {
        if (!isEditingPoster(vSelf)) {
            writeLog("CSProminentTimeView didMoveToWindow: ON SCREEN");
            g_isScreenOff = NO;
            registerActiveTimeView(vSelf);
            updateTimeViewInstance(vSelf);
        } else {
            writeLog("CSProminentTimeView didMoveToWindow: in EDIT mode, ignoring");
        }
    } else {
        unregisterActiveTimeView(vSelf);
    }
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    %orig;
    if (newWindow == nil) {
        unregisterActiveTimeView((UIView *)self);
    }
}

- (void)dealloc {
    unregisterActiveTimeView((UIView *)self);
    %orig;
}

- (void)setDate:(NSDate *)date {
    if (pref_enabled && !isEditingPoster((UIView *)self)) {
        NSDateFormatter *tf = nil;
        if ([(UIView *)self respondsToSelector:@selector(timeFormatter)]) {
            tf = [(id)self valueForKey:@"timeFormatter"];
        }
        if (!tf) {
            tf = (NSDateFormatter *)getIvarSafe(self, "_timeFormatter");
        }
        NSString *fmt = getEffectiveDateFormat();
        if (tf && fmt) {
            [tf setDateFormat:fmt];
        }
    }
    %orig;
}

- (void)layoutSubviews {
    %orig;
    
    if (!pref_enabled) return;
    if (isEditingPoster((UIView *)self)) return; // DO NOT scale or shift in poster editing
    
    UIView *vSelf = (UIView *)self;
    vSelf.clipsToBounds = NO; // Ensure vertical shifts do not get clipped
    
    UIView *label = nil;
    if ([(UIView *)vSelf respondsToSelector:@selector(textLabel)]) {
        label = [(id)vSelf valueForKey:@"textLabel"];
    }
    if (!label) {
        label = (UIView *)getIvarSafe(vSelf, "_textLabel");
    }
    if (!label) {
        for (UIView *sub in vSelf.subviews) {
            if ([sub isKindOfClass:NSClassFromString(@"_UIAnimatingLabel")] || [sub isKindOfClass:[UILabel class]]) {
                label = sub;
                break;
            }
        }
    }
    if (!label) return;
    
    // 1. Get untouched baseline font from view
    UIFont *baseFont = nil;
    if ([(UIView *)vSelf respondsToSelector:@selector(baseFont)]) {
        baseFont = [(id)vSelf valueForKey:@"baseFont"];
    }
    if (!baseFont && [(UIView *)vSelf respondsToSelector:@selector(primaryFont)]) {
        baseFont = [(id)vSelf valueForKey:@"primaryFont"];
    }
    if (!baseFont) {
        baseFont = (UIFont *)getIvarSafe(vSelf, "_baseFont");
    }
    if (!baseFont && [label respondsToSelector:@selector(font)]) {
        baseFont = [(id)label valueForKey:@"font"];
    }
    if (!baseFont) return;
    
    // 2. Cache unscaled original font size and original Y position ONCE to prevent oscillation
    NSNumber *origSizeNum = objc_getAssociatedObject(vSelf, kOriginalFontSizeKey);
    if (!origSizeNum || [origSizeNum doubleValue] <= 10.0) {
        origSizeNum = @(baseFont.pointSize);
        objc_setAssociatedObject(vSelf, kOriginalFontSizeKey, origSizeNum, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat originalPointSize = [origSizeNum doubleValue];
    
    NSNumber *origYNum = objc_getAssociatedObject(vSelf, kOriginalYOffsetKey);
    if (!origYNum) {
        origYNum = @(label.frame.origin.y);
        objc_setAssociatedObject(vSelf, kOriginalYOffsetKey, origYNum, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat originalY = [origYNum doubleValue];
    
    // 3. Compute target size strictly from originalPointSize
    CGFloat scale = pref_fontScale;
    if (scale < 0.5f || scale > 1.5f) {
        scale = 0.88f;
    }
    CGFloat targetPointSize = originalPointSize * scale;
    
    // 4. Update font on label only if it differs by more than 0.5 pt
    UIFont *curLabelFont = [label respondsToSelector:@selector(font)] ? [(id)label valueForKey:@"font"] : nil;
    UIFont *effectiveFont = baseFont;
    if (fabs((double)scale - 1.0) > 0.01) {
        effectiveFont = [baseFont fontWithSize:targetPointSize];
        if (effectiveFont && (!curLabelFont || fabs(curLabelFont.pointSize - targetPointSize) > 0.5)) {
            if ([label respondsToSelector:@selector(setFont:)]) {
                [(id)label performSelector:@selector(setFont:) withObject:effectiveFont];
            }
        }
    }
    
    // 5. Calculate required width for clock display with seconds
    NSString *format = getEffectiveDateFormat();
    if (!format) format = @"HH:mm:ss";
    
    NSDateFormatter *measurer = [[NSDateFormatter alloc] init];
    [measurer setDateFormat:format];
    NSString *sample = [measurer stringFromDate:[NSDate date]];
    if (!sample || sample.length < 5) sample = @"88:88:88";
    
    CGSize strSize = [sample sizeWithAttributes:@{NSFontAttributeName: effectiveFont}];
    CGFloat neededWidth = ceil(strSize.width) + 16.0;
    
    CGRect bounds = vSelf.bounds;
    if (neededWidth > bounds.size.width) {
        neededWidth = bounds.size.width;
    }
    
    CGRect frame = label.frame;
    frame.size.width = neededWidth;
    frame.origin.x = (bounds.size.width - neededWidth) / 2.0; // Horizontal center
    frame.origin.y = originalY + pref_yOffset;               // Vertical position adjustment
    label.frame = frame;
}

%end

%hook SBBacklightController

- (void)backlight:(id)arg1 didCompleteUpdateToState:(long long)state forEvent:(long long)event {
    %orig;
    writeLog("SBBacklightController state=%lld event=%lld", state, event);
    // In SpringBoard: state 2 = Blanked (screen off / AOD dim), state != 2 (0, etc.) = Active / Screen Awake!
    if (state == 2) {
        g_isScreenOff = YES;
        if (pref_aodOptimize) {
            stopTimer();
        }
    } else {
        g_isScreenOff = NO;
        if (pref_enabled) {
            startTimerIfNeeded();
            updateAllActiveViews();
        }
    }
}

%end

%hook SBFLockScreenDateView

- (void)didMoveToWindow {
    %orig;
    UIView *vSelf = (UIView *)self;
    if (vSelf.window != nil) {
        if (!isEditingPoster(vSelf)) {
            writeLog("SBFLockScreenDateView didMoveToWindow: ON SCREEN");
            g_isScreenOff = NO;
            registerActiveDateView(vSelf);
            updateDateViewInstance(vSelf);
        }
    } else {
        unregisterActiveDateView(vSelf);
    }
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    %orig;
    if (newWindow == nil) {
        unregisterActiveDateView((UIView *)self);
    }
}

- (void)dealloc {
    unregisterActiveDateView((UIView *)self);
    %orig;
}

- (void)layoutSubviews {
    %orig;
    if (!pref_enabled) return;
    if (isEditingPoster((UIView *)self)) return;
    
    UIView *vSelf = (UIView *)self;
    vSelf.clipsToBounds = NO;
    
    UIView *label = nil;
    if ([(UIView *)vSelf respondsToSelector:@selector(timeLabel)]) {
        label = [(id)vSelf valueForKey:@"timeLabel"];
    }
    if (!label) {
        label = (UIView *)getIvarSafe(vSelf, "_timeLabel");
    }
    if (!label) return;
    
    // Vertical offset
    NSNumber *origYNum = objc_getAssociatedObject(vSelf, kOriginalYOffsetKey);
    if (!origYNum) {
        origYNum = @(label.frame.origin.y);
        objc_setAssociatedObject(vSelf, kOriginalYOffsetKey, origYNum, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat originalY = [origYNum doubleValue];
    
    CGRect frame = label.frame;
    frame.origin.y = originalY + pref_yOffset;
    label.frame = frame;
    
    registerActiveDateView(vSelf);
}

%end

%ctor {
    @autoreleasepool {
        writeLog(">>> LSTimeSeconds ctor initialized in process %s (PID %d) <<<", getprogname(), getpid());
        loadPrefs();
        
        // Settings reload notification
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)onReloadNotification,
            (CFStringRef)kNotifyReload,
            NULL,
            CFNotificationSuspensionBehaviorCoalesce
        );
        
        // System screen state notifications
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)onScreenBlanked,
            CFSTR("com.apple.springboard.hasBlankedScreen"),
            NULL,
            CFNotificationSuspensionBehaviorCoalesce
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)onScreenUnblanked,
            CFSTR("com.apple.springboard.lockstate"),
            NULL,
            CFNotificationSuspensionBehaviorCoalesce
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)onScreenUnblanked,
            CFSTR("com.apple.iokit.hid.displayStatus"),
            NULL,
            CFNotificationSuspensionBehaviorCoalesce
        );
        
        %init;
        writeLog(">>> LSTimeSeconds %init finished <<<");
    }
}
