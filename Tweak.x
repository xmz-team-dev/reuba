#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <dlfcn.h>

@interface BKDisplayBootUIRenderOverlay : NSObject
@property (nonatomic, readonly) CALayer *contentLayer;
@end

#define PREF_PATH @"/var/jb/var/mobile/Library/Preferences/com.lf.unixbootanim.plist"

static CATextLayer *g_logLayer = nil;
static NSMutableArray<NSAttributedString *> *g_logLines = nil;
static dispatch_source_t g_timer = nil;
static BOOL g_initialized = NO;
static NSArray *g_logPaths = nil;
static NSMutableDictionary *g_fileStates = nil;
static NSUInteger g_maxLines = 80;

// 设置变量
static BOOL g_tweakEnabled = YES;
static BOOL g_enableColors = YES;
static BOOL g_logGradient = YES;
static BOOL g_smoothScroll = YES; // 新增：滚动效果开关
static CGFloat g_fontSize = 8.0;
static CGFloat g_logOpacity = 1.0;
static CGFloat g_logoOpacity = 1.0;

static CGColorRef g_colorWhite = NULL;
static CGColorRef g_colorRed = NULL;
static CGColorRef g_colorGreen = NULL;
static CGColorRef g_colorCyan = NULL;
static CGColorRef g_colorOpaqueBlack = NULL;
static CGColorRef g_colorTransparent = NULL;
static CTFontRef g_ctFont = NULL;

static void loadPreferences() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
    if (prefs) {
        g_tweakEnabled = prefs[@"Enabled"] ? [prefs[@"Enabled"] boolValue] : YES;
        g_enableColors = prefs[@"EnableColors"] ? [prefs[@"EnableColors"] boolValue] : YES;
        g_logGradient  = prefs[@"LogGradient"] ? [prefs[@"LogGradient"] boolValue] : YES;
        g_smoothScroll = prefs[@"SmoothScroll"] ? [prefs[@"SmoothScroll"] boolValue] : YES;
        g_fontSize     = prefs[@"FontSize"] ? [prefs[@"FontSize"] floatValue] : 8.0;
        g_logOpacity   = prefs[@"LogOpacity"] ? [prefs[@"LogOpacity"] floatValue] : 1.0;
        g_logoOpacity  = prefs[@"LogoOpacity"] ? [prefs[@"LogoOpacity"] floatValue] : 1.0;
    }
}

static void initializeDrawingAttributes() {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat white[] = {1.0, 1.0, 1.0, 1.0};
    CGFloat red[]   = {1.0, 0.3, 0.3, 1.0};
    CGFloat green[] = {0.3, 1.0, 0.3, 1.0};
    CGFloat cyan[]  = {0.3, 0.8, 1.0, 1.0};
    CGFloat black[] = {0.0, 0.0, 0.0, 1.0};
    CGFloat trans[] = {0.0, 0.0, 0.0, 0.0};
    
    g_colorWhite = CGColorCreate(colorSpace, white);
    g_colorRed   = CGColorCreate(colorSpace, red);
    g_colorGreen = CGColorCreate(colorSpace, green);
    g_colorCyan  = CGColorCreate(colorSpace, cyan);
    g_colorOpaqueBlack = CGColorCreate(colorSpace, black);
    g_colorTransparent = CGColorCreate(colorSpace, trans);
    CGColorSpaceRelease(colorSpace);
    
    g_ctFont = CTFontCreateWithName(CFSTR("Menlo"), g_fontSize, NULL);
}

static CGColorRef getColorForLogLine(NSString *line) {
    if (!g_enableColors) return g_colorWhite;
    NSString *lowerLine = [line lowercaseString];
    
    if ([lowerLine containsString:@"error"] || [lowerLine containsString:@"failed"] || 
        [lowerLine containsString:@"missingvalue"] || [lowerLine containsString:@"invalid"]) {
        return g_colorRed;
    } else if ([lowerLine containsString:@"starting up"] || [lowerLine containsString:@"completed"] || 
               [lowerLine containsString:@"loaded"]) {
        return g_colorGreen;
    } else if ([lowerLine containsString:@"trusted"] || [lowerLine containsString:@"done"] || 
               [lowerLine containsString:@"pinged configd"]) {
        return g_colorCyan;
    }
    return g_colorWhite;
}

static NSAttributedString* createAttributedString(NSString *text) {
    CGColorRef textColor = getColorForLogLine(text);
    NSDictionary *attributes = @{
        (__bridge id)kCTFontAttributeName: (__bridge id)g_ctFont,
        (__bridge id)kCTForegroundColorAttributeName: (__bridge id)textColor
    };
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

static NSArray<NSAttributedString *> *fetchNewLogs(void) {
    if (!g_fileStates) g_fileStates = [NSMutableDictionary dictionary];
    if (!g_logPaths) {
        g_logPaths = @[

            @"/var/logs/usermanagerd.log.0",
            @"/rootfs/var/logs/usermanagerd.log.0",
            @"/var/logs/lockdownd.log",
            @"/rootfs/var/logs/lockdownd.log",
            @"/var/logs/syslog",
            @"/rootfs/var/logs/syslog",
            @"/var/logs/backboardd.log",
            @"/rootfs/var/logs/backboardd.log",

        ];
    }
    
    NSMutableArray *newLines = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    for (NSString *path in g_logPaths) {
        if (![fm fileExistsAtPath:path]) continue;
        
        NSError *err = nil;
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:&err];
        if (err) continue;
        unsigned long long fileSize = [attrs fileSize];
        
        NSMutableDictionary *state = g_fileStates[path];
        if (!state) {
            state = [NSMutableDictionary dictionary];
            g_fileStates[path] = state;
        }
        
        NSNumber *lastOffsetNum = state[@"offset"];
        unsigned long long lastOffset = lastOffsetNum ? [lastOffsetNum unsignedLongLongValue] : 0;
        
        if (fileSize == lastOffset) continue;
        if (fileSize < lastOffset) { lastOffset = 0; }
        
        NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
        if (!fh) continue;
        [fh seekToFileOffset:lastOffset];
        NSData *newData = [fh readDataToEndOfFile];
        [fh closeFile];
        
        if (newData.length == 0) continue;
        state[@"offset"] = @(fileSize);
        
        NSString *text = [[NSString alloc] initWithData:newData encoding:NSUTF8StringEncoding];
        if (!text) continue;
        
        NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString *line in lines) {
            if (line.length > 0) {
                NSString *formattedText = [NSString stringWithFormat:@"[%@] %@\n", [path lastPathComponent], line];
                [newLines addObject:createAttributedString(formattedText)];
            }
        }
    }
    return newLines.count > 0 ? newLines : nil;
}

// 修改后的滚动逻辑（此函数现在直接在后台线程执行）
static void appendLinesAndScroll(NSArray<NSAttributedString *> *lines) {
    if (lines.count == 0 || !g_logLayer) return;
    
    NSUInteger count = lines.count;
    
    // 如果关闭了平滑滚动，或者需要瞬间显示，直接一次性提交
    if (!g_smoothScroll) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            for (NSAttributedString *attrLine in lines) {
                if (g_logLines.count >= g_maxLines) [g_logLines removeObjectAtIndex:0];
                [g_logLines addObject:attrLine];
            }
            NSMutableAttributedString *fullDisplayString = [[NSMutableAttributedString alloc] init];
            for (NSAttributedString *attrLine in g_logLines) {
                [fullDisplayString appendAttributedString:attrLine];
            }
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            g_logLayer.string = fullDisplayString;
            [CATransaction commit];
        });
        return;
    }
    
    // 如果开启了平滑滚动，后台分批休眠，并在主线程同步更新
    NSUInteger index = 0;
    while (index < count) {
        NSUInteger batchSize = 1;
        
        // 动态决定批次大小
        __block CGFloat fillRatio = 0.0;
        dispatch_sync(dispatch_get_main_queue(), ^{
            fillRatio = (CGFloat)g_logLines.count / g_maxLines;
        });
        
        if (fillRatio < 0.2) {
            if (arc4random_uniform(10) < 3) batchSize = (arc4random_uniform(3) + 2);
        } else if (fillRatio < 0.8) {
            if (arc4random_uniform(10) < 2) batchSize = 2;
        } else {
            if (arc4random_uniform(10) < 5) batchSize = (arc4random_uniform(3) + 3);
        }
        
        if (batchSize > count - index) batchSize = count - index;
        
        // 严格在主线程操作数据源和 UI
        dispatch_sync(dispatch_get_main_queue(), ^{
            for (NSUInteger i = 0; i < batchSize; i++) {
                if (g_logLines.count >= g_maxLines) {
                    [g_logLines removeObjectAtIndex:0];
                }
                [g_logLines addObject:lines[index + i]];
            }
            
            NSMutableAttributedString *fullDisplayString = [[NSMutableAttributedString alloc] init];
            for (NSAttributedString *attrLine in g_logLines) {
                [fullDisplayString appendAttributedString:attrLine];
            }
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            g_logLayer.string = fullDisplayString;
            [CATransaction commit];
        });
        
        index += batchSize;
        
        // 在后台线程休眠，不阻塞主线程刷新
        if (batchSize > 1 && index < count) {
            usleep(15000); // 批次大时稍微多休眠一下，效果更好 (15ms)
        } else {
            usleep(5000);  // 默认小休眠 (5ms)
        }
    }
}

// 定时任务回调
static void fetchAndUpdateLogs(void) {
    if (!g_tweakEnabled) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *newLines = fetchNewLogs();
        if (newLines.count > 0) {
            // 注意这里：不再切回主线程，让 appendLinesAndScroll 自己在后台控制节奏
            appendLinesAndScroll(newLines);
        }
    });
}

static void setupLogLayer(CALayer *contentLayer) {
    if (!contentLayer || g_initialized) return;
    
    loadPreferences();
    if (!g_tweakEnabled) return;
    
    initializeDrawingAttributes();
    
    for (CALayer *sublayer in contentLayer.sublayers) {
        if (sublayer != g_logLayer) {
            sublayer.opacity = g_logoOpacity;
        }
    }
    
    CGFloat lineHeight = g_fontSize * 1.2;
    g_maxLines = (NSUInteger)(contentLayer.bounds.size.height / lineHeight);
    if (g_maxLines < 20) g_maxLines = 20;
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    g_logLayer = [CATextLayer layer];
    g_logLayer.frame = contentLayer.bounds;
    g_logLayer.anchorPoint = CGPointMake(0, 0);
    g_logLayer.position = CGPointMake(0, 0);
    g_logLayer.alignmentMode = kCAAlignmentLeft;
    g_logLayer.wrapped = YES;
    g_logLayer.contentsScale = 3.0;
    g_logLayer.zPosition = 1000;
    
    g_logLayer.opacity = g_logOpacity;
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat bgComponents[] = {0.0, 0.0, 0.0, 0.6}; 
    CGColorRef bgColor = CGColorCreate(colorSpace, bgComponents);
    g_logLayer.backgroundColor = bgColor;
    CGColorRelease(bgColor);
    CGColorSpaceRelease(colorSpace);
    
    if (g_logGradient) {
        CAGradientLayer *maskLayer = [CAGradientLayer layer];
        maskLayer.frame = g_logLayer.bounds;
        maskLayer.colors = @[
            (__bridge id)g_colorTransparent, 
            (__bridge id)g_colorOpaqueBlack
        ];
        maskLayer.locations = @[@0.0, @0.25];
        g_logLayer.mask = maskLayer;
    }
    
    [contentLayer addSublayer:g_logLayer];
    
    g_logLines = [NSMutableArray array];
    g_fileStates = [NSMutableDictionary dictionary];
    g_logLayer.string = [[NSAttributedString alloc] initWithString:@""];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *logs = fetchNewLogs();
        if (logs.count > 0) {
            appendLinesAndScroll(logs);
        }
    });
    
    g_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(g_timer, dispatch_walltime(NULL, 0), 0.1 * NSEC_PER_SEC, 0.01 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(g_timer, ^{
        fetchAndUpdateLogs();
    });
    dispatch_resume(g_timer);
    
    g_initialized = YES;
    [CATransaction commit];
}

%group BootUIHook
%hook BKDisplayBootUIRenderOverlay

- (void)_presentWithAnimationSettings:(id)arg1 {
    %orig;
    CALayer *contentLayer = self.contentLayer;
    if (!contentLayer) return;
    
    if (!g_initialized) {
        setupLogLayer(contentLayer);
    } else {
        if (g_logLayer && ![contentLayer.sublayers containsObject:g_logLayer] && g_tweakEnabled) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [contentLayer addSublayer:g_logLayer];
            
            for (CALayer *sublayer in contentLayer.sublayers) {
                if (sublayer != g_logLayer) {
                    sublayer.opacity = g_logoOpacity;
                }
            }
            [CATransaction commit];
        }
    }
}

%end
%end

%ctor {
    if ([[[NSProcessInfo processInfo] processName] isEqualToString:@"backboardd"]) {
        dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
        %init(BootUIHook);
    }
}
