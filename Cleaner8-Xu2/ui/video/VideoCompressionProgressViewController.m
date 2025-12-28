#import "VideoCompressionProgressViewController.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import "VideoCompressionResultViewController.h"
#import "VideoCompressionManager.h"

#pragma mark - Helpers

static inline UIColor *ASBlue(void) {
    // #024DFF
    return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0];
}
static inline UIColor *ASGrayBG(void) {
    // #F6F6F6
    return [UIColor colorWithRed:246/255.0 green:246/255.0 blue:246/255.0 alpha:1.0];
}
static uint64_t ASAssetFileSize(PHAsset *asset) {
    PHAssetResource *r = [PHAssetResource assetResourcesForAsset:asset].firstObject;
    if (!r) return 0;
    NSNumber *n = nil;
    @try { n = [r valueForKey:@"fileSize"]; } @catch (__unused NSException *e) { n = nil; }
    return n.unsignedLongLongValue;
}
static NSString *ASMB1(uint64_t bytes) {
    double mb = (double)bytes / (1024.0 * 1024.0);
    return [NSString stringWithFormat:@"%.1fMB", mb];
}
static double ASRemainRatioForQuality(ASCompressionQuality q) {
    switch (q) {
        case ASCompressionQualitySmall:  return 0.20;
        case ASCompressionQualityMedium: return 0.50;
        case ASCompressionQualityLarge:  return 0.80;
    }
}

#pragma mark - Progress Bar View (bubble + icon)

@interface ASBubbleProgressBarView : UIView
@property (nonatomic) CGFloat progress; // 0..1
- (void)setProgress:(CGFloat)p percentText:(NSString *)text;
@end

@interface ASBubbleProgressBarView ()
@property (nonatomic, strong) UIView *trackView;
@property (nonatomic, strong) UIView *fillView;
@property (nonatomic, strong) UIImageView *iconView;

@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong) UILabel *bubbleLabel;
@property (nonatomic, strong) CAShapeLayer *arrowLayer;

@property (nonatomic, strong) NSLayoutConstraint *fillWidthC;
@property (nonatomic, strong) NSLayoutConstraint *iconCenterXC;
@property (nonatomic, strong) NSLayoutConstraint *bubbleCenterXC;
@end

@implementation ASBubbleProgressBarView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.clearColor;

        self.trackView = [UIView new];
        self.trackView.backgroundColor = [UIColor colorWithWhite:0.86 alpha:1.0];
        self.trackView.layer.cornerRadius = 8;
        self.trackView.layer.masksToBounds = YES;

        self.fillView = [UIView new];
        self.fillView.backgroundColor = ASBlue();
        self.fillView.layer.cornerRadius = 8;
        self.fillView.layer.masksToBounds = YES;

        [self addSubview:self.trackView];
        [self.trackView addSubview:self.fillView];

        self.iconView = [UIImageView new];
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;

        // ✅ 先用占位图标，后续你替换
        UIImage *placeholder = nil;
        if (@available(iOS 13.0, *)) placeholder = [UIImage systemImageNamed:@"paperplane.fill"];
        self.iconView.image = placeholder;
        self.iconView.tintColor = ASBlue();
        [self addSubview:self.iconView];

        self.bubbleView = [UIView new];
        self.bubbleView.backgroundColor = ASBlue();
        self.bubbleView.layer.cornerRadius = 10;
        self.bubbleView.layer.masksToBounds = YES;

        self.bubbleLabel = [UILabel new];
        self.bubbleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        self.bubbleLabel.textColor = UIColor.whiteColor;
        self.bubbleLabel.textAlignment = NSTextAlignmentCenter;
        self.bubbleLabel.text = @"0%";

        [self addSubview:self.bubbleView];
        [self.bubbleView addSubview:self.bubbleLabel];

        self.arrowLayer = [CAShapeLayer layer];
        self.arrowLayer.fillColor = ASBlue().CGColor;
        [self.layer addSublayer:self.arrowLayer];

        self.trackView.translatesAutoresizingMaskIntoConstraints = NO;
        self.fillView.translatesAutoresizingMaskIntoConstraints = NO;
        self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.bubbleView.translatesAutoresizingMaskIntoConstraints = NO;
        self.bubbleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [NSLayoutConstraint activateConstraints:@[
            [self.trackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.trackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6],
            [self.trackView.heightAnchor constraintEqualToConstant:16],

            [self.fillView.leadingAnchor constraintEqualToAnchor:self.trackView.leadingAnchor],
            [self.fillView.topAnchor constraintEqualToAnchor:self.trackView.topAnchor],
            [self.fillView.bottomAnchor constraintEqualToAnchor:self.trackView.bottomAnchor],

            [self.bubbleView.bottomAnchor constraintEqualToAnchor:self.trackView.topAnchor constant:-10],
            [self.bubbleView.heightAnchor constraintEqualToConstant:34],

            [self.bubbleLabel.leadingAnchor constraintEqualToAnchor:self.bubbleView.leadingAnchor constant:12],
            [self.bubbleLabel.trailingAnchor constraintEqualToAnchor:self.bubbleView.trailingAnchor constant:-12],
            [self.bubbleLabel.topAnchor constraintEqualToAnchor:self.bubbleView.topAnchor constant:6],
            [self.bubbleLabel.bottomAnchor constraintEqualToAnchor:self.bubbleView.bottomAnchor constant:-6],

            [self.iconView.centerYAnchor constraintEqualToAnchor:self.trackView.centerYAnchor],
            [self.iconView.widthAnchor constraintEqualToConstant:26],
            [self.iconView.heightAnchor constraintEqualToConstant:26],
        ]];

        self.fillWidthC = [self.fillView.widthAnchor constraintEqualToConstant:0];
        self.fillWidthC.active = YES;

        self.iconCenterXC = [self.iconView.centerXAnchor constraintEqualToAnchor:self.trackView.leadingAnchor constant:0];
        self.iconCenterXC.active = YES;

        self.bubbleCenterXC = [self.bubbleView.centerXAnchor constraintEqualToAnchor:self.trackView.leadingAnchor constant:0];
        self.bubbleCenterXC.active = YES;

        self.progress = 0;
    }
    return self;
}

- (void)setProgress:(CGFloat)p percentText:(NSString *)text {
    self.progress = MAX(0, MIN(1, p));
    self.bubbleLabel.text = text ?: @"0%";
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat w = self.trackView.bounds.size.width;
    if (w <= 0) return;

    CGFloat fillW = w * self.progress;
    self.fillWidthC.constant = fillW;

    CGFloat iconW = 26;
    CGFloat bubbleW = self.bubbleView.bounds.size.width;
    if (bubbleW <= 0) bubbleW = 60;

    CGFloat x = fillW;

    CGFloat iconMin = iconW * 0.5;
    CGFloat iconMax = w - iconW * 0.5;
    CGFloat iconX = MIN(MAX(x, iconMin), iconMax);

    CGFloat bubbleMin = bubbleW * 0.5;
    CGFloat bubbleMax = w - bubbleW * 0.5;
    CGFloat bubbleX = MIN(MAX(x, bubbleMin), bubbleMax);

    self.iconCenterXC.constant = iconX;
    self.bubbleCenterXC.constant = bubbleX;

    CGRect b = [self.bubbleView.superview convertRect:self.bubbleView.frame fromView:self.bubbleView.superview];
    CGFloat baseY = CGRectGetMaxY(b);
    CGFloat cx = CGRectGetMidX(b);

    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(cx - 6, baseY)];
    [path addLineToPoint:CGPointMake(cx + 6, baseY)];
    [path addLineToPoint:CGPointMake(cx, baseY + 6)];
    [path closePath];
    self.arrowLayer.path = path.CGPath;
}

@end

#pragma mark - VC

@interface VideoCompressionProgressViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, weak) id<UIGestureRecognizerDelegate> popDelegateBackup;

// UI
@property (nonatomic, strong) UIView *topCard;

@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UILabel *titleLabel;

@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UIImageView *playIcon;

@property (nonatomic, strong) UILabel *beforeSizeLabel;
@property (nonatomic, strong) UILabel *afterSizeLabel;
@property (nonatomic, strong) ASBubbleProgressBarView *progressBar;

@property (nonatomic, strong) UILabel *tipLabel;
@property (nonatomic, strong) UIButton *cancelBtn;

// Data
@property (nonatomic, strong) NSArray<PHAsset *> *assets;
@property (nonatomic) ASCompressionQuality quality;

@property (nonatomic) uint64_t totalBeforeBytes;
@property (nonatomic) uint64_t estimatedAfterBytes;

@property (nonatomic, strong) VideoCompressionManager *manager;
@property (nonatomic) BOOL didExit;
@property (nonatomic) BOOL showingCancelAlert;
@end

@implementation VideoCompressionProgressViewController

- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets
                       quality:(ASCompressionQuality)quality
               totalBeforeBytes:(uint64_t)beforeBytes
            estimatedAfterBytes:(uint64_t)afterBytes {
    if (self = [super init]) {
        _assets = assets ?: @[];
        _quality = quality;
        _totalBeforeBytes = beforeBytes;
        _estimatedAfterBytes = afterBytes;
        _didExit = NO;
    }
    return self;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBarHidden = YES;

    // ✅ 底部区域背景 #F6F6F6
    self.view.backgroundColor = ASGrayBG();

    // 兜底：如果上个页面没传 before/after 就算一下
    if (self.totalBeforeBytes == 0) {
        uint64_t t = 0;
        for (PHAsset *a in self.assets) t += ASAssetFileSize(a);
        self.totalBeforeBytes = t;
    }
    if (self.estimatedAfterBytes == 0 && self.totalBeforeBytes > 0) {
        double r = ASRemainRatioForQuality(self.quality);
        self.estimatedAfterBytes = (uint64_t)llround((double)self.totalBeforeBytes * r);
    }

    [self buildUI];
    [self updateSizeTexts];

    // ✅ 只加载一次首图：压缩中不再换缩略图，避免闪烁
    [self loadThumbOnce:self.assets.firstObject];

    [self startCompress];
}

#pragma mark - Pop gesture (optional)
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIGestureRecognizer *pop = self.navigationController.interactivePopGestureRecognizer;
    if (!pop) return;
    if (!self.popDelegateBackup) self.popDelegateBackup = pop.delegate;
    pop.delegate = self;
    pop.enabled = YES;
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    UIGestureRecognizer *pop = self.navigationController.interactivePopGestureRecognizer;
    if (!pop) return;
    if (pop.delegate == self) {
        pop.delegate = self.popDelegateBackup;
        pop.enabled = YES;
    }
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.navigationController.interactivePopGestureRecognizer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self onCancelPressed];
        });
        return NO;
    }
    return YES;
}

#pragma mark - UI

- (void)buildUI {

    // ✅ topCard：从顶部到进度条下方 66pt 白色，底部圆角
    self.topCard = [UIView new];
    self.topCard.backgroundColor = UIColor.whiteColor;
    self.topCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.topCard];

    self.topCard.layer.cornerRadius = 34;
    if (@available(iOS 11.0, *)) {
        self.topCard.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner; // 只圆底部
    }
    self.topCard.layer.masksToBounds = YES;

    // Header（back + title）在 topCard 内
    UIView *header = [UIView new];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topCard addSubview:header];

    self.backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) {
        [self.backBtn setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    }
    self.backBtn.tintColor = ASBlue();
    [self.backBtn addTarget:self action:@selector(onCancelPressed) forControlEvents:UIControlEventTouchUpInside];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;

    self.titleLabel = [UILabel new];
    self.titleLabel.text = @"In Process";
    self.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = UIColor.blackColor;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [header addSubview:self.backBtn];
    [header addSubview:self.titleLabel];

    // Thumbnail 210x280
    self.thumbView = [UIImageView new];
    self.thumbView.layer.cornerRadius = 28;
    self.thumbView.layer.masksToBounds = YES;
    self.thumbView.contentMode = UIViewContentModeScaleAspectFill;
    self.thumbView.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    self.thumbView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topCard addSubview:self.thumbView];

    // ✅ 左上角 ic_play
    self.playIcon = [UIImageView new];
    self.playIcon.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *playImg = [UIImage imageNamed:@"ic_play"];
    self.playIcon.image = [playImg imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    self.playIcon.contentMode = UIViewContentModeScaleAspectFit;
    [self.thumbView addSubview:self.playIcon];

    // Progress row: before + bar + after
    self.beforeSizeLabel = [UILabel new];
    self.beforeSizeLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightRegular];
    self.beforeSizeLabel.textColor = UIColor.blackColor;

    self.afterSizeLabel = [UILabel new];
    self.afterSizeLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    self.afterSizeLabel.textColor = ASBlue();

    self.progressBar = [ASBubbleProgressBarView new];
    self.progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.progressBar setProgress:0 percentText:@"0%"];

    UIStackView *progressRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.beforeSizeLabel, self.progressBar, self.afterSizeLabel]];
    progressRow.axis = UILayoutConstraintAxisHorizontal;
    progressRow.alignment = UIStackViewAlignmentCenter;
    progressRow.distribution = UIStackViewDistributionFill;
    progressRow.spacing = 16;
    progressRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topCard addSubview:progressRow];

    [self.beforeSizeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.beforeSizeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.afterSizeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.afterSizeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    // Tip（在灰底上）
    self.tipLabel = [UILabel new];
    self.tipLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular]; // ✅ Regular 17
    self.tipLabel.textColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    self.tipLabel.numberOfLines = 0;
    self.tipLabel.textAlignment = NSTextAlignmentCenter;
    self.tipLabel.text = @"It is recommended not to minimize\nor close the app...";
    self.tipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tipLabel];

    // Cancel button（灰底上）
    self.cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cancelBtn setTitle:@"Cancel" forState:UIControlStateNormal];
    self.cancelBtn.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold]; // ✅ Bold 20
    [self.cancelBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.cancelBtn.backgroundColor = ASBlue(); // ✅ #024DFF
    self.cancelBtn.layer.cornerRadius = 35;
    self.cancelBtn.layer.masksToBounds = NO; // ✅ 需要阴影
    [self.cancelBtn addTarget:self action:@selector(onCancelPressed) forControlEvents:UIControlEventTouchUpInside];
    self.cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;

    // ✅ 阴影
    self.cancelBtn.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.18].CGColor;
    self.cancelBtn.layer.shadowOpacity = 1.0;
    self.cancelBtn.layer.shadowOffset = CGSizeMake(0, 10);
    self.cancelBtn.layer.shadowRadius = 18;

    [self.view addSubview:self.cancelBtn];

    CGFloat side = 20;

    [NSLayoutConstraint activateConstraints:@[
        // topCard pinned top
        [self.topCard.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.topCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        // header
        [header.topAnchor constraintEqualToAnchor:self.topCard.safeAreaLayoutGuide.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.topCard.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.topCard.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:56],

        [self.backBtn.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:12],
        [self.backBtn.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.backBtn.widthAnchor constraintEqualToConstant:44],
        [self.backBtn.heightAnchor constraintEqualToConstant:44],

        [self.titleLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        // thumb 210x280
        [self.thumbView.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:34],
        [self.thumbView.centerXAnchor constraintEqualToAnchor:self.topCard.centerXAnchor],
        [self.thumbView.widthAnchor constraintEqualToConstant:210],
        [self.thumbView.heightAnchor constraintEqualToConstant:280],

        // play icon top-left
        [self.playIcon.leadingAnchor constraintEqualToAnchor:self.thumbView.leadingAnchor constant:14],
        [self.playIcon.topAnchor constraintEqualToAnchor:self.thumbView.topAnchor constant:14],
        [self.playIcon.widthAnchor constraintEqualToConstant:40],
        [self.playIcon.heightAnchor constraintEqualToConstant:40],

        // progress row
        [progressRow.topAnchor constraintEqualToAnchor:self.thumbView.bottomAnchor constant:40],
        [progressRow.leadingAnchor constraintEqualToAnchor:self.topCard.leadingAnchor constant:side],
        [progressRow.trailingAnchor constraintEqualToAnchor:self.topCard.trailingAnchor constant:-side],
        [self.progressBar.heightAnchor constraintEqualToConstant:60],
        [self.progressBar.widthAnchor constraintGreaterThanOrEqualToConstant:150],

        // ✅ topCard bottom = progressRow.bottom + 66
        [self.topCard.bottomAnchor constraintEqualToAnchor:progressRow.bottomAnchor constant:66],

        // tip label (grey area)
        [self.tipLabel.topAnchor constraintEqualToAnchor:self.topCard.bottomAnchor constant:46],
        [self.tipLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:30],
        [self.tipLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-30],

        // cancel button: left/right 40
        [self.cancelBtn.topAnchor constraintEqualToAnchor:self.tipLabel.bottomAnchor constant:28],
        [self.cancelBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.cancelBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        [self.cancelBtn.heightAnchor constraintEqualToConstant:70],
        [self.cancelBtn.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-22],
    ]];

    // 阴影路径更稳定（布局后）
    dispatch_async(dispatch_get_main_queue(), ^{
        self.cancelBtn.layer.shadowPath =
        [UIBezierPath bezierPathWithRoundedRect:self.cancelBtn.bounds cornerRadius:35].CGPath;
    });
}

- (void)updateSizeTexts {
    self.beforeSizeLabel.text = (self.totalBeforeBytes > 0) ? ASMB1(self.totalBeforeBytes) : @"--";
    self.afterSizeLabel.text  = (self.estimatedAfterBytes > 0) ? ASMB1(self.estimatedAfterBytes) : @"--";
}

#pragma mark - Thumb (no flicker)

- (void)loadThumbOnce:(PHAsset *)asset {
    if (!asset) return;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.resizeMode = PHImageRequestOptionsResizeModeExact;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat; // ✅ 不要 opportunistic（会回调两次，容易闪）

    [[PHImageManager defaultManager] requestImageForAsset:asset
                                              targetSize:CGSizeMake(900, 1200)
                                             contentMode:PHImageContentModeAspectFill
                                                 options:opt
                                           resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;

        // ✅ 避免 degraded 图导致闪烁
        NSNumber *degraded = info[PHImageResultIsDegradedKey];
        if (degraded.boolValue) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            self.thumbView.image = result;
        });
    }];
}

#pragma mark - Compress

- (void)startCompress {
    self.manager = [VideoCompressionManager new];

    __weak typeof(self) weakSelf = self;
    [self.manager compressAssets:self.assets
                         quality:self.quality
                        progress:^(NSInteger currentIndex, NSInteger totalCount, float overallProgress, PHAsset *currentAsset) {

        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.didExit) return;

            int percent = (int)lrintf(overallProgress * 100.0f);
            percent = MAX(0, MIN(100, percent));
            [weakSelf.progressBar setProgress:overallProgress
                                  percentText:[NSString stringWithFormat:@"%d%%", percent]];
        });

    } completion:^(ASCompressionSummary * _Nullable summary, NSError * _Nullable error) {

        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.didExit) return;

            if (error) {
                // cancel
                if (error.code == -999) {
                    [weakSelf.navigationController popViewControllerAnimated:YES];
                    return;
                }

                UIAlertController *ac =
                [UIAlertController alertControllerWithTitle:@"Compress Failed"
                                                    message:error.localizedDescription ?: @"Unknown error"
                                             preferredStyle:UIAlertControllerStyleAlert];
                [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [weakSelf.navigationController popViewControllerAnimated:YES];
                }]];
                [weakSelf presentViewController:ac animated:YES completion:nil];
                return;
            }

            VideoCompressionResultViewController *vc =
            [[VideoCompressionResultViewController alloc] initWithSummary:summary];
            [weakSelf.navigationController pushViewController:vc animated:YES];
        });
    }];
}

#pragma mark - Cancel (no confirm per request)

- (void)onCancelPressed {
    // 不在压缩：直接返回
    if (!self.manager || !self.manager.isRunning) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    // 防止重复弹窗
    if (self.showingCancelAlert) return;
    self.showingCancelAlert = YES;

    UIAlertController *ac =
    [UIAlertController alertControllerWithTitle:@"Cancel Conversion"
                                        message:@"Are you sure you want to cancel the conversion of this Video?"
                                 preferredStyle:UIAlertControllerStyleAlert];

    __weak typeof(self) weakSelf = self;

    [ac addAction:[UIAlertAction actionWithTitle:@"NO"
                                          style:UIAlertActionStyleCancel
                                        handler:^(UIAlertAction * _Nonnull action) {
        weakSelf.showingCancelAlert = NO;
        [weakSelf resetPopGesture];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"YES"
                                          style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction * _Nonnull action) {
        weakSelf.showingCancelAlert = NO;

        [weakSelf.manager cancel];

        // 返回上一页
        [weakSelf.navigationController popViewControllerAnimated:YES];
    }]];

    [self presentViewController:ac animated:YES completion:nil];
}

- (void)resetPopGesture {
    UIGestureRecognizer *pop = self.navigationController.interactivePopGestureRecognizer;
    if (!pop) return;
    pop.enabled = NO;
    pop.enabled = YES;
    pop.delegate = self;
}

@end
