#import "UBARootListController.h"
#import <spawn.h>

@implementation UBARootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 右上角重启用户空间按钮
    UIBarButtonItem *rebootButton = [[UIBarButtonItem alloc] initWithTitle:@"重启用户空间" 
                                                                     style:UIBarButtonItemStyleDone 
                                                                    target:self 
                                                                    action:@selector(rebootUserspace)];
    rebootButton.tintColor = [UIColor systemBlueColor];
    self.navigationItem.rightBarButtonItem = rebootButton;
    
    [self setupHeaderView];
}

- (void)setupHeaderView {
    // 创建顶部大容器
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.table.bounds.size.width, 180)];
    headerView.backgroundColor = [UIColor clearColor];
    
    // 创建圆角卡片
    UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(16, 12, self.table.bounds.size.width - 32, 156)];
    cardView.layer.cornerRadius = 14;
    cardView.layer.masksToBounds = YES;
    cardView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    // 【终极修复】直接定义 Rootless 的绝对物理路径
    NSString *bundlePath = @"/var/jb/Library/PreferenceBundles/UnixBootAnimPrefs.bundle";
    
    NSString *bannerPath = [bundlePath stringByAppendingPathComponent:@"Banner.png"];
    UIImage *bannerImage = [UIImage imageWithContentsOfFile:bannerPath];
    
    if (bannerImage) {
        // 方案 A：如果存在 Banner.png，直接渲染成全幅背景横幅
        UIImageView *bannerView = [[UIImageView alloc] initWithFrame:cardView.bounds];
        bannerView.image = bannerImage;
        bannerView.contentMode = UIViewContentModeScaleAspectFill;
        bannerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [cardView addSubview:bannerView];
    } else {
        // 方案 B：如果不存在 Banner，采用大图标 + 标题的现代卡片进行兜底
        if (@available(iOS 13.0, *)) {
            cardView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        } else {
            cardView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        }
        
        UIImageView *iconView = [[UIImageView alloc] init];
        
        // 【已修复】这里补上了丢失的双引号
        NSString *iconPath = [bundlePath stringByAppendingPathComponent:@"icon.png"];
        iconView.image = [UIImage imageWithContentsOfFile:iconPath];
        
        iconView.layer.cornerRadius = 12;
        iconView.layer.masksToBounds = YES;
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.frame = CGRectMake((cardView.bounds.size.width - 60) / 2, 20, 60, 60);
        iconView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [cardView addSubview:iconView];
        
        // 主标题
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 90, cardView.bounds.size.width, 25)];
        titleLabel.text = @"UnixBootAnim";
        titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
        
        if (@available(iOS 13.0, *)) {
            titleLabel.textColor = [UIColor labelColor];
        } else {
            titleLabel.textColor = [UIColor blackColor];
        }
        
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cardView addSubview:titleLabel];
        
        // 副标题
        UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 118, cardView.bounds.size.width, 15)];
        subtitleLabel.text = @"v1.0.0 • By LF";
        subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        
        if (@available(iOS 13.0, *)) {
            subtitleLabel.textColor = [UIColor secondaryLabelColor];
        } else {
            subtitleLabel.textColor = [UIColor grayColor];
        }
        
        subtitleLabel.textAlignment = NSTextAlignmentCenter;
        subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cardView addSubview:subtitleLabel];
    }
    
    [headerView addSubview:cardView];
    self.table.tableHeaderView = headerView;
}

- (void)rebootUserspace {
    pid_t pid;
    const char* args[] = {"launchctl", "reboot", "userspace", NULL};
    if (posix_spawn(&pid, "/var/jb/bin/launchctl", NULL, NULL, (char* const *)args, NULL) != 0) {
        posix_spawn(&pid, "/var/jb/usr/bin/launchctl", NULL, NULL, (char* const *)args, NULL);
    }
}

@end
