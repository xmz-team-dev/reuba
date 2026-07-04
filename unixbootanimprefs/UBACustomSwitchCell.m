#import "UBACustomSwitchCell.h"

// 常量：默认图片名称（如果未在 plist 中指定）
static NSString * const kDefaultDisabledIcon = @"disabled_icon";
static NSString * const kDefaultEnabledIcon = @"enabled_icon";

@interface UBACustomSwitchCell ()

// 容器与卡片
@property (nonatomic, strong) UIStackView *containerStackView;
@property (nonatomic, strong) UIStackView *disabledCard;
@property (nonatomic, strong) UIStackView *enabledCard;

// 子控件
@property (nonatomic, strong) UIImageView *disabledIcon;
@property (nonatomic, strong) UILabel *disabledLabel;
@property (nonatomic, strong) UIButton *disabledCheckmark;

@property (nonatomic, strong) UIImageView *enabledIcon;
@property (nonatomic, strong) UILabel *enabledLabel;
@property (nonatomic, strong) UIButton *enabledCheckmark;

// 状态
@property (nonatomic, assign) BOOL isPluginEnabled;
@property (nonatomic, strong) UIImpactFeedbackGenerator *feedbackGenerator;

// 从 specifier 读取的属性
@property (nonatomic, copy) NSString *defaultsPath;
@property (nonatomic, copy) NSString *prefKey;
@property (nonatomic, copy) NSString *postNotificationName;
@property (nonatomic, copy) NSString *disabledIconName;
@property (nonatomic, copy) NSString *enabledIconName;

@end

@implementation UBACustomSwitchCell

#pragma mark - 初始化
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        // 从 specifier 读取配置
        NSString *defaultsID = specifier.properties[@"defaults"];
        if (defaultsID) {
            self.defaultsPath = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", defaultsID];
        }
        self.prefKey = specifier.properties[@"key"];
        self.postNotificationName = specifier.properties[@"PostNotification"];
        
        // 图标名称：如果 plist 中指定了则使用，否则使用默认
        self.disabledIconName = specifier.properties[@"disabledIcon"] ?: kDefaultDisabledIcon;
        self.enabledIconName = specifier.properties[@"enabledIcon"] ?: kDefaultEnabledIcon;

        // 触觉反馈
        if (@available(iOS 10.0, *)) {
            self.feedbackGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [self.feedbackGenerator prepare];
        }

        [self setupViews];
        [self setupConstraints];

        // 加载状态
        [self loadStateAndUpdate:NO];
    }
    return self;
}

#pragma mark - 视图构建
- (void)setupViews {
    // 水平容器
    self.containerStackView = [[UIStackView alloc] init];
    self.containerStackView.axis = UILayoutConstraintAxisHorizontal;
    self.containerStackView.distribution = UIStackViewDistributionFillEqually;
    self.containerStackView.spacing = 16;
    self.containerStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.containerStackView];

    // 创建两张卡片
    self.disabledCard = [self createCardWithTag:0 title:@"Disabled"];
    self.enabledCard  = [self createCardWithTag:1 title:@"Enabled"];

    [self.containerStackView addArrangedSubview:self.disabledCard];
    [self.containerStackView addArrangedSubview:self.enabledCard];
}

- (UIStackView *)createCardWithTag:(NSInteger)tag title:(NSString *)title {
    UIStackView *card = [[UIStackView alloc] init];
    card.axis = UILayoutConstraintAxisVertical;
    card.alignment = UIStackViewAlignmentCenter;
    card.distribution = UIStackViewDistributionEqualSpacing;
    card.spacing = 8;
    card.tag = tag;
    card.userInteractionEnabled = YES;
    card.layoutMargins = UIEdgeInsetsMake(18, 0, 18, 0);
    card.isLayoutMarginsRelativeArrangement = YES;

    // 样式
    if (@available(iOS 13.0, *)) {
        card.backgroundColor = [UIColor secondarySystemBackgroundColor];
    } else {
        card.backgroundColor = [UIColor colorWithWhite:0.93 alpha:1.0];
    }
    card.layer.cornerRadius = 14;
    card.layer.masksToBounds = YES;

    // 点击手势
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cardTapped:)];
    [card addGestureRecognizer:tap];

    // 图标（从 bundle 加载本地图片）
    UIImageView *icon = [[UIImageView alloc] init];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon.widthAnchor constraintEqualToConstant:44].active = YES;
    [icon.heightAnchor constraintEqualToConstant:44].active = YES;
    if (tag == 0) {
        icon.image = [self imageForDisabled];
        self.disabledIcon = icon;
    } else {
        icon.image = [self imageForEnabled];
        self.enabledIcon = icon;
    }
    [card addArrangedSubview:icon];

    // 标签
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;
    if (@available(iOS 13.0, *)) {
        label.textColor = [UIColor labelColor];
    } else {
        label.textColor = [UIColor blackColor];
    }
    [card addArrangedSubview:label];
    if (tag == 0) self.disabledLabel = label;
    else self.enabledLabel = label;

    // 对勾按钮（指示器）
    UIButton *checkmark = [UIButton buttonWithType:UIButtonTypeCustom];
    checkmark.userInteractionEnabled = NO;
    checkmark.translatesAutoresizingMaskIntoConstraints = NO;
    [checkmark.widthAnchor constraintEqualToConstant:22].active = YES;
    [checkmark.heightAnchor constraintEqualToConstant:22].active = YES;

    // 设置图片（降级方案）
    [checkmark setImage:[self normalCircleImage] forState:UIControlStateNormal];
    [checkmark setImage:[self filledCheckmarkImage] forState:UIControlStateSelected];
    checkmark.tintColor = [UIColor systemGrayColor];

    [card addArrangedSubview:checkmark];
    if (tag == 0) self.disabledCheckmark = checkmark;
    else self.enabledCheckmark = checkmark;

    return card;
}

#pragma mark - 约束
- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        [self.containerStackView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.containerStackView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.containerStackView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [self.containerStackView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10]
    ]];
}

#pragma mark - 图片加载（从 bundle 优先，降级为 SF Symbols 或绘制）
- (UIImage *)imageForDisabled {
    UIImage *img = [self bundleImageNamed:self.disabledIconName];
    if (img) return img;
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:@"iphone"];
    }
    return [self drawPlaceholderIconWithText:@"✕"];
}

- (UIImage *)imageForEnabled {
    UIImage *img = [self bundleImageNamed:self.enabledIconName];
    if (img) return img;
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:@"iphone.radiowaves.left.and.right"];
    }
    return [self drawPlaceholderIconWithText:@"✓"];
}

- (UIImage *)bundleImageNamed:(NSString *)name {
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    UIImage *image = [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
    if (image) return image;
    NSString *bundlePath = [NSString stringWithFormat:@"/var/jb/Library/PreferenceBundles/%@.bundle", 
                            [[bundle bundlePath] lastPathComponent]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
        bundlePath = @"/var/jb/Library/PreferenceBundles/UnixBootAnimPrefs.bundle";
    }
    bundle = [NSBundle bundleWithPath:bundlePath];
    image = [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
    if (image) return image;
    bundlePath = @"/var/jb/Library/PreferenceBundles/UnixBootAnimPrefs.bundle";
    bundle = [NSBundle bundleWithPath:bundlePath];
    image = [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
    if (image) return image;
    
    return nil;
}

- (UIImage *)drawPlaceholderIconWithText:(NSString *)text {
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = [UIScreen mainScreen].scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(44, 44) format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        CGContextRef ctx = context.CGContext;
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.85 alpha:1].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(2, 2, 40, 40));
        NSDictionary *attrs = @{NSFontAttributeName: [UIFont systemFontOfSize:24], NSForegroundColorAttributeName: [UIColor darkGrayColor]};
        CGSize textSize = [text sizeWithAttributes:attrs];
        CGRect textRect = CGRectMake((44 - textSize.width)/2, (44 - textSize.height)/2, textSize.width, textSize.height);
        [text drawInRect:textRect withAttributes:attrs];
    }];
}

- (UIImage *)normalCircleImage {
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:@"circle"];
    } else {
        UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
        format.scale = [UIScreen mainScreen].scale;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(22, 22) format:format];
        return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
            CGContextRef ctx = context.CGContext;
            CGContextSetStrokeColorWithColor(ctx, [UIColor grayColor].CGColor);
            CGContextSetLineWidth(ctx, 2);
            CGContextStrokeEllipseInRect(ctx, CGRectMake(1, 1, 20, 20));
        }];
    }
}

- (UIImage *)filledCheckmarkImage {
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:@"checkmark.circle.fill"];
    } else {
        UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
        format.scale = [UIScreen mainScreen].scale;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(22, 22) format:format];
        return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
            CGContextRef ctx = context.CGContext;
            CGContextSetFillColorWithColor(ctx, [UIColor systemBlueColor].CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, 22, 22));
            UIBezierPath *path = [UIBezierPath bezierPath];
            [path moveToPoint:CGPointMake(6, 11)];
            [path addLineToPoint:CGPointMake(10, 15)];
            [path addLineToPoint:CGPointMake(17, 6)];
            [path setLineWidth:2.5];
            CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);
            CGContextAddPath(ctx, path.CGPath);
            CGContextStrokePath(ctx);
        }];
    }
}

#pragma mark - 状态管理
- (void)loadStateAndUpdate:(BOOL)animated {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:self.defaultsPath];
    id value = prefs[self.prefKey];
    self.isPluginEnabled = value ? [value boolValue] : YES; // 默认开启
    [self updateUIAnimated:animated];
}

- (void)updateUIAnimated:(BOOL)animated {
    void (^updateBlock)(void) = ^{
        UIColor *activeColor = [UIColor systemBlueColor];
        if (self.isPluginEnabled) {
            self.enabledCheckmark.selected = YES;
            self.enabledCheckmark.tintColor = activeColor;
            self.enabledCard.layer.borderWidth = 2.0;
            self.enabledCard.layer.borderColor = activeColor.CGColor;

            self.disabledCheckmark.selected = NO;
            self.disabledCheckmark.tintColor = [UIColor systemGrayColor];
            self.disabledCard.layer.borderWidth = 0;
        } else {
            self.disabledCheckmark.selected = YES;
            self.disabledCheckmark.tintColor = activeColor;
            self.disabledCard.layer.borderWidth = 2.0;
            self.disabledCard.layer.borderColor = activeColor.CGColor;

            self.enabledCheckmark.selected = NO;
            self.enabledCheckmark.tintColor = [UIColor systemGrayColor];
            self.enabledCard.layer.borderWidth = 0;
        }
    };
    if (animated) {
        [UIView animateWithDuration:0.2 animations:updateBlock];
    } else {
        updateBlock();
    }
}

#pragma mark - 交互
- (void)cardTapped:(UITapGestureRecognizer *)sender {
    UIView *card = sender.view;
    BOOL newState = (card.tag == 1); // 1=Enabled, 0=Disabled
    if (self.isPluginEnabled != newState) {
        self.isPluginEnabled = newState;

        // 写入 plist
        NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:self.defaultsPath];
        if (!prefs) prefs = [NSMutableDictionary dictionary];
        prefs[self.prefKey] = @(newState);
        [prefs writeToFile:self.defaultsPath atomically:YES];

        // 发送 Darwin 通知
        if (self.postNotificationName) {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 (__bridge CFStringRef)self.postNotificationName,
                                                 NULL, NULL, YES);
        }

        if (@available(iOS 10.0, *)) {
            [self.feedbackGenerator impactOccurred];
        }

        [self updateUIAnimated:YES];
    }
}

#pragma mark - 刷新
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self loadStateAndUpdate:NO];
}

@end
