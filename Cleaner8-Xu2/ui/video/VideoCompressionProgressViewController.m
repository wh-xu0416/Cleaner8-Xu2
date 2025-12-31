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

        self.iconView = [UIImageView new];
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;
        self.iconView.image = [[UIImage imageNamed:@"ic_speed"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        self.iconView.tintColor = nil;
        self.iconView.layer.zPosition = 9999;

        self.bubbleView = [UIView new];
        self.bubbleView.backgroundColor = ASBlue();
        self.bubbleView.layer.cornerRadius = 8;
        self.bubbleView.layer.masksToBounds = YES;

        self.bubbleLabel = [UILabel new];
        self.bubbleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        self.bubbleLabel.textColor = UIColor.whiteColor;
        self.bubbleLabel.textAlignment = NSTextAlignmentCenter;
        self.bubbleLabel.text = @"0%";

        self.arrowLayer = [CAShapeLayer layer];
        self.arrowLayer.fillColor = ASBlue().CGColor;

        [self addSubview:self.trackView];
        [self.trackView addSubview:self.fillView];
        [self addSubview:self.iconView];
        [self addSubview:self.bubbleView];
        [self.bubbleView addSubview:self.bubbleLabel];
        [self.layer addSublayer:self.arrowLayer];

        for (UIView *v in @[self.trackView,self.fillView,self.iconView,self.bubbleView,self.bubbleLabel]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
        }

        [NSLayoutConstraint activateConstraints:@[
            [self.trackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [self.trackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:0],
            [self.trackView.heightAnchor constraintEqualToConstant:16],

            [self.fillView.leadingAnchor constraintEqualToAnchor:self.trackView.leadingAnchor],
            [self.fillView.topAnchor constraintEqualToAnchor:self.trackView.topAnchor],
            [self.fillView.bottomAnchor constraintEqualToAnchor:self.trackView.bottomAnchor],

            [self.iconView.centerYAnchor constraintEqualToAnchor:self.trackView.centerYAnchor constant:2],
            [self.iconView.widthAnchor constraintEqualToConstant:28],
            [self.iconView.heightAnchor constraintEqualToConstant:28],

            [self.bubbleView.bottomAnchor constraintEqualToAnchor:self.trackView.topAnchor constant:-10],
            [self.bubbleView.heightAnchor constraintEqualToConstant:40],

            [self.bubbleLabel.leadingAnchor constraintEqualToAnchor:self.bubbleView.leadingAnchor constant:5],
            [self.bubbleLabel.trailingAnchor constraintEqualToAnchor:self.bubbleView.trailingAnchor constant:-5],
            [self.bubbleLabel.topAnchor constraintEqualToAnchor:self.bubbleView.topAnchor constant:8],
            [self.bubbleLabel.bottomAnchor constraintEqualToAnchor:self.bubbleView.bottomAnchor constant:-8],
        ]];

        self.fillWidthC = [self.fillView.widthAnchor constraintEqualToConstant:0];
        self.fillWidthC.active = YES;

        self.iconCenterXC = [self.iconView.centerXAnchor constraintEqualToAnchor:self.trackView.leadingAnchor constant:0];
        self.iconCenterXC.active = YES;

        self.bubbleCenterXC = [self.bubbleView.centerXAnchor constraintEqualToAnchor:self.trackView.leadingAnchor constant:0];
        self.bubbleCenterXC.active = YES;

        [self bringSubviewToFront:self.iconView];

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

    CGFloat iconW = 28;

    CGFloat bubbleW = [self.bubbleView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width;
    if (bubbleW <= 0) bubbleW = 60;

    CGFloat x = fillW;

    CGFloat iconX = MIN(MAX(x, iconW * 0.5), w - iconW * 0.5);
    CGFloat bubbleX = MIN(MAX(x, bubbleW * 0.5), w - bubbleW * 0.5);

    self.iconCenterXC.constant = iconX;
    self.bubbleCenterXC.constant = bubbleX;

    CGRect b = self.bubbleView.frame;
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
@property (nonatomic, strong, nullable) UIAlertController *cancelAlert;

@end

@implementation VideoCompressionProgressViewController

- (void)as_dismissPresentedIfNeededThen:(dispatch_block_t)block {
    UIViewController *presented = self.presentedViewController;
    if (presented) {
        [self dismissViewControllerAnimated:NO completion:block];
    } else {
        if (block) block();
    }
}

- (void)as_finishWithSummary:(ASCompressionSummary * _Nullable)summary
                       error:(NSError * _Nullable)error {

    __weak typeof(self) weakSelf = self;
    [self as_dismissPresentedIfNeededThen:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.didExit) return;

        // ✅ 如果此时还在显示取消确认弹窗，完成后就把它作废并隐藏
        self.showingCancelAlert = NO;
        self.cancelAlert = nil;

        if (error) {
            if (error.code == -999) {
                [self.navigationController popViewControllerAnimated:YES];
                return;
            }

            UIAlertController *ac =
            [UIAlertController alertControllerWithTitle:@"Compress Failed"
                                                message:error.localizedDescription ?: @"Unknown error"
                                         preferredStyle:UIAlertControllerStyleAlert];

            [ac addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
                [self.navigationController popViewControllerAnimated:YES];
            }]];
            [self presentViewController:ac animated:YES completion:nil];
            return;
        }

        VideoCompressionResultViewController *vc =
        [[VideoCompressionResultViewController alloc] initWithSummary:summary];
        [self.navigationController pushViewController:vc animated:YES];
    }];
}

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
    CGFloat side = 20;
    CGFloat previewW = 210;
    CGFloat previewH = 280;
    
    self.topCard = [UIView new];
    self.topCard.backgroundColor = UIColor.whiteColor;
    self.topCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.topCard.layer.cornerRadius = 34;
    if (@available(iOS 11.0,*)) {
        self.topCard.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    self.topCard.layer.masksToBounds = YES;
    [self.view addSubview:self.topCard];

    UIView *header = [UIView new];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topCard addSubview:header];

    self.backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *backImg = [[UIImage imageNamed:@"ic_back_blue"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.backBtn setImage:backImg forState:UIControlStateNormal];
    self.backBtn.contentEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10);
    self.backBtn.adjustsImageWhenHighlighted = NO;
    [self.backBtn addTarget:self action:@selector(onCancelPressed) forControlEvents:UIControlEventTouchUpInside];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;

    self.titleLabel = [UILabel new];
    self.titleLabel.text = @"In Process";
    self.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = UIColor.blackColor;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [header addSubview:self.backBtn];
    [header addSubview:self.titleLabel];

    self.thumbView = [UIImageView new];
    self.thumbView.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1];
    self.thumbView.contentMode = UIViewContentModeScaleAspectFill;
    self.thumbView.layer.cornerRadius = 22;
    self.thumbView.layer.masksToBounds = YES;
    self.thumbView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topCard addSubview:self.thumbView];

    self.playIcon = [UIImageView new];
    self.playIcon.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *playImg = [UIImage imageNamed:@"ic_play"];
    self.playIcon.image = [playImg imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    self.playIcon.contentMode = UIViewContentModeScaleAspectFit;
    [self.thumbView addSubview:self.playIcon];

    self.beforeSizeLabel = [UILabel new];
    self.beforeSizeLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    self.beforeSizeLabel.textColor = UIColor.blackColor;

    self.afterSizeLabel = [UILabel new];
    self.afterSizeLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.afterSizeLabel.textColor = ASBlue();

    self.progressBar = [ASBubbleProgressBarView new];
    self.progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.progressBar setProgress:0 percentText:@"0%"];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.beforeSizeLabel, self.progressBar, self.afterSizeLabel]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentBottom;
    row.spacing = 16;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topCard addSubview:row];

    [self.beforeSizeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.afterSizeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    self.tipLabel = [UILabel new];
    self.tipLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
    self.tipLabel.textColor = [UIColor colorWithWhite:0.15 alpha:1];
    self.tipLabel.numberOfLines = 0;
    self.tipLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.tipLabel.preferredMaxLayoutWidth = UIScreen.mainScreen.bounds.size.width - 60;
    self.tipLabel.textAlignment = NSTextAlignmentCenter;
    self.tipLabel.text = @"It is recommended not to minimize or close the app...";
    self.tipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tipLabel];

    self.cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cancelBtn setTitle:@"Cancel" forState:UIControlStateNormal];
    self.cancelBtn.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    [self.cancelBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.cancelBtn.backgroundColor = ASBlue();
    self.cancelBtn.layer.cornerRadius = 35;
    self.cancelBtn.layer.masksToBounds = NO;
    self.cancelBtn.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.18].CGColor;
    self.cancelBtn.layer.shadowOpacity = 1.0;
    self.cancelBtn.layer.shadowOffset = CGSizeMake(0, 10);
    self.cancelBtn.layer.shadowRadius = 18;
    [self.cancelBtn addTarget:self action:@selector(onCancelPressed) forControlEvents:UIControlEventTouchUpInside];
    self.cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.cancelBtn];

    [NSLayoutConstraint activateConstraints:@[
        [self.topCard.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.topCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [header.topAnchor constraintEqualToAnchor:self.topCard.safeAreaLayoutGuide.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.topCard.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.topCard.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:56],

        [self.backBtn.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:6],
        [self.backBtn.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.backBtn.widthAnchor constraintEqualToConstant:44],
        [self.backBtn.heightAnchor constraintEqualToConstant:44],

        [self.titleLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        [self.thumbView.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10],
        [self.thumbView.centerXAnchor constraintEqualToAnchor:self.topCard.centerXAnchor],
        [self.thumbView.widthAnchor constraintEqualToConstant:previewW],
        [self.thumbView.heightAnchor constraintEqualToConstant:previewH],

        [self.playIcon.leadingAnchor constraintEqualToAnchor:self.thumbView.leadingAnchor constant:15],
        [self.playIcon.topAnchor constraintEqualToAnchor:self.thumbView.topAnchor constant:15],
        [self.playIcon.widthAnchor constraintEqualToConstant:30],
        [self.playIcon.heightAnchor constraintEqualToConstant:30],

        [row.topAnchor constraintEqualToAnchor:self.thumbView.bottomAnchor constant:30],
        [row.leadingAnchor constraintEqualToAnchor:self.topCard.leadingAnchor constant:side],
        [row.trailingAnchor constraintEqualToAnchor:self.topCard.trailingAnchor constant:-side],

        [self.progressBar.heightAnchor constraintEqualToConstant:60],
        [self.progressBar.widthAnchor constraintGreaterThanOrEqualToConstant:150],

        [self.topCard.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:46],

        [self.tipLabel.topAnchor constraintEqualToAnchor:self.topCard.bottomAnchor constant:40],
        [self.tipLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:30],
        [self.tipLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-30],

        [self.cancelBtn.topAnchor constraintEqualToAnchor:self.tipLabel.bottomAnchor constant:28],
        [self.cancelBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.cancelBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        [self.cancelBtn.heightAnchor constraintEqualToConstant:70],
        [self.cancelBtn.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-22],
    ]];

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
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize target = CGSizeMake(210.0 * scale * 2.0, 280.0 * scale * 2.0);

    [[PHImageManager defaultManager] requestImageForAsset:asset
                                              targetSize:target
                                             contentMode:PHImageContentModeAspectFill
                                                 options:opt
                                           resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;
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
            [weakSelf as_finishWithSummary:summary error:error];
        });
    }];
}

#pragma mark - Cancel (no confirm per request)

- (void)onCancelPressed {
    if (!self.manager || !self.manager.isRunning) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    if (self.showingCancelAlert) return;
    self.showingCancelAlert = YES;

    UIAlertController *ac =
    [UIAlertController alertControllerWithTitle:@"Cancel Conversion"
                                        message:@"Are you sure you want to cancel the conversion of this Video?"
                                 preferredStyle:UIAlertControllerStyleAlert];

    self.cancelAlert = ac;

    __weak typeof(self) weakSelf = self;

    [ac addAction:[UIAlertAction actionWithTitle:@"NO"
                                          style:UIAlertActionStyleCancel
                                        handler:^(__unused UIAlertAction * _Nonnull action) {
        weakSelf.showingCancelAlert = NO;
        weakSelf.cancelAlert = nil;
        [weakSelf resetPopGesture];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"YES"
                                          style:UIAlertActionStyleDestructive
                                        handler:^(__unused UIAlertAction * _Nonnull action) {
        weakSelf.showingCancelAlert = NO;
        weakSelf.cancelAlert = nil;

        weakSelf.didExit = YES;
        [weakSelf.manager cancel];

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
