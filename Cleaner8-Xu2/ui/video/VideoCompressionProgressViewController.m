#import "VideoCompressionProgressViewController.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import "VideoCompressionResultViewController.h"
#import "VideoCompressionManager.h"

static inline CGFloat ASDesignWidth(void) { return 402.0; }
static inline CGFloat ASScale(void) {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    return MIN(1.0, w / ASDesignWidth());
}
static inline CGFloat AS(CGFloat v) { return round(v * ASScale()); }
static inline UIFont *ASFontS(CGFloat s, UIFontWeight w) { return [UIFont systemFontOfSize:round(s * ASScale()) weight:w]; }
static inline UIEdgeInsets ASEdgeInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) { return UIEdgeInsetsMake(AS(t), AS(l), AS(b), AS(r)); }

#pragma mark - Helpers

static inline UIColor *ASBlue(void) {
    return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0];
}
static inline UIColor *ASGrayBG(void) {
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
        self.trackView.layer.cornerRadius = AS(8);
        self.trackView.layer.masksToBounds = YES;

        self.fillView = [UIView new];
        self.fillView.backgroundColor = ASBlue();
        self.fillView.layer.cornerRadius = AS(8);
        self.fillView.layer.masksToBounds = YES;

        self.iconView = [UIImageView new];
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;
        self.iconView.image = [[UIImage imageNamed:@"ic_speed"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        self.iconView.tintColor = nil;
        self.iconView.layer.zPosition = 9999;

        self.bubbleView = [UIView new];
        self.bubbleView.backgroundColor = ASBlue();
        self.bubbleView.layer.cornerRadius = AS(8);
        self.bubbleView.layer.masksToBounds = YES;

        self.bubbleLabel = [UILabel new];
        self.bubbleLabel.font = ASFontS(15, UIFontWeightSemibold);
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
            [self.trackView.heightAnchor constraintEqualToConstant:AS(16)],

            [self.fillView.leadingAnchor constraintEqualToAnchor:self.trackView.leadingAnchor],
            [self.fillView.topAnchor constraintEqualToAnchor:self.trackView.topAnchor],
            [self.fillView.bottomAnchor constraintEqualToAnchor:self.trackView.bottomAnchor],

            [self.iconView.centerYAnchor constraintEqualToAnchor:self.trackView.centerYAnchor constant:AS(2)],
            [self.iconView.widthAnchor constraintEqualToConstant:AS(28)],
            [self.iconView.heightAnchor constraintEqualToConstant:AS(28)],

            [self.bubbleView.bottomAnchor constraintEqualToAnchor:self.trackView.topAnchor constant:-AS(10)],
            [self.bubbleView.heightAnchor constraintEqualToConstant:AS(40)],

            [self.bubbleLabel.leadingAnchor constraintEqualToAnchor:self.bubbleView.leadingAnchor constant:AS(5)],
            [self.bubbleLabel.trailingAnchor constraintEqualToAnchor:self.bubbleView.trailingAnchor constant:-AS(5)],
            [self.bubbleLabel.topAnchor constraintEqualToAnchor:self.bubbleView.topAnchor constant:AS(8)],
            [self.bubbleLabel.bottomAnchor constraintEqualToAnchor:self.bubbleView.bottomAnchor constant:-AS(8)],
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

    CGFloat iconW = AS(28);

    CGFloat bubbleW = [self.bubbleView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width;
    if (bubbleW <= 0) bubbleW = AS(60);

    CGFloat x = fillW;

    CGFloat iconX = MIN(MAX(x, iconW * 0.5), w - iconW * 0.5);
    CGFloat bubbleX = MIN(MAX(x, bubbleW * 0.5), w - bubbleW * 0.5);

    self.iconCenterXC.constant = iconX;
    self.bubbleCenterXC.constant = bubbleX;

    CGRect b = self.bubbleView.frame;
    CGFloat baseY = CGRectGetMaxY(b);
    CGFloat cx = CGRectGetMidX(b);

    CGFloat tri = AS(6);
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(cx - tri, baseY)];
    [path addLineToPoint:CGPointMake(cx + tri, baseY)];
    [path addLineToPoint:CGPointMake(cx, baseY + tri)];
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

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *scrollContentView;
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

        self.showingCancelAlert = NO;
        self.cancelAlert = nil;

        if (error) {
            if (error.code == -999) {
                [self.navigationController popViewControllerAnimated:YES];
                return;
            }

            UIAlertController *ac =
            [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Compress Failed",nil)
                                                message:error.localizedDescription ?: NSLocalizedString(@"Unknown error",nil)
                                         preferredStyle:UIAlertControllerStyleAlert];

            [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil)
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
        _showingCancelAlert = NO;
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

#pragma mark - Pop gesture

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

- (void)resetPopGesture {
    UIGestureRecognizer *pop = self.navigationController.interactivePopGestureRecognizer;
    if (!pop) return;
    pop.enabled = NO;
    pop.enabled = YES;
    pop.delegate = self;
}

#pragma mark - UI

- (void)buildUI {
    CGFloat side    = AS(20);
    CGFloat headerH = AS(56);

    CGFloat previewW = AS(210);
    CGFloat previewH = AS(280);

    UIView *headerBG = [UIView new];
    headerBG.translatesAutoresizingMaskIntoConstraints = NO;
    headerBG.backgroundColor = UIColor.whiteColor;
    [self.view addSubview:headerBG];

    UIView *header = [UIView new];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.backgroundColor = UIColor.clearColor;
    [self.view addSubview:header];

    self.backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *backImg = [[UIImage imageNamed:@"ic_back_blue"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.backBtn setImage:backImg forState:UIControlStateNormal];
    self.backBtn.contentEdgeInsets = ASEdgeInsets(10, 10, 10, 10);
    self.backBtn.adjustsImageWhenHighlighted = NO;
    [self.backBtn addTarget:self action:@selector(onCancelPressed) forControlEvents:UIControlEventTouchUpInside];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.backBtn];

    self.titleLabel = [UILabel new];
    self.titleLabel.text = NSLocalizedString(@"In Process",nil);
    self.titleLabel.font = ASFontS(24, UIFontWeightSemibold);
    self.titleLabel.textColor = UIColor.blackColor;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.titleLabel];

    self.cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cancelBtn setTitle:NSLocalizedString(@"Cancel",nil) forState:UIControlStateNormal];
    self.cancelBtn.titleLabel.font = ASFontS(20, UIFontWeightBold);
    [self.cancelBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.cancelBtn.backgroundColor = ASBlue();
    self.cancelBtn.layer.cornerRadius = AS(35);
    self.cancelBtn.layer.masksToBounds = NO;
    self.cancelBtn.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.18].CGColor;
    self.cancelBtn.layer.shadowOpacity = 1.0;
    self.cancelBtn.layer.shadowOffset = CGSizeMake(0, AS(10));
    self.cancelBtn.layer.shadowRadius = AS(18);
    [self.cancelBtn addTarget:self action:@selector(onCancelPressed) forControlEvents:UIControlEventTouchUpInside];
    self.cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.cancelBtn];

    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.showsVerticalScrollIndicator = YES;
    self.scrollView.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.scrollView];

    self.scrollContentView = [UIView new];
    self.scrollContentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollContentView.backgroundColor = UIColor.clearColor;
    [self.scrollView addSubview:self.scrollContentView];

    self.topCard = [UIView new];
    self.topCard.backgroundColor = UIColor.whiteColor;
    self.topCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.topCard.layer.cornerRadius = AS(34);
    if (@available(iOS 11.0,*)) {
        self.topCard.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    self.topCard.layer.masksToBounds = YES;
    [self.scrollContentView addSubview:self.topCard];

    // thumb
    self.thumbView = [UIImageView new];
    self.thumbView.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1];
    self.thumbView.contentMode = UIViewContentModeScaleAspectFill;
    self.thumbView.layer.cornerRadius = AS(22);
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
    self.beforeSizeLabel.font = ASFontS(15, UIFontWeightRegular);
    self.beforeSizeLabel.textColor = UIColor.blackColor;

    self.afterSizeLabel = [UILabel new];
    self.afterSizeLabel.font = ASFontS(15, UIFontWeightSemibold);
    self.afterSizeLabel.textColor = ASBlue();

    self.progressBar = [ASBubbleProgressBarView new];
    self.progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.progressBar setProgress:0 percentText:@"0%"];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.beforeSizeLabel, self.progressBar, self.afterSizeLabel]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentBottom;
    row.spacing = AS(16);
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topCard addSubview:row];

    [self.beforeSizeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.afterSizeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    self.tipLabel = [UILabel new];
    self.tipLabel.font = ASFontS(17, UIFontWeightRegular);
    self.tipLabel.textColor = [UIColor colorWithWhite:0.15 alpha:1];
    self.tipLabel.numberOfLines = 0;
    self.tipLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.tipLabel.textAlignment = NSTextAlignmentCenter;
    self.tipLabel.text = NSLocalizedString(@"It is recommended not to minimize or close the app...",nil);
    self.tipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollContentView addSubview:self.tipLabel];

    [NSLayoutConstraint activateConstraints:@[
        [headerBG.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [headerBG.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [headerBG.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [headerBG.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],

        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:headerH],

        [self.backBtn.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:AS(6)],
        [self.backBtn.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.backBtn.widthAnchor constraintEqualToConstant:AS(44)],
        [self.backBtn.heightAnchor constraintEqualToConstant:AS(44)],

        [self.titleLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        [self.cancelBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:AS(40)],
        [self.cancelBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-AS(40)],
        [self.cancelBtn.heightAnchor constraintEqualToConstant:AS(70)],
        [self.cancelBtn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-AS(22)],

        [self.scrollView.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.cancelBtn.topAnchor],

        [self.scrollContentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.scrollContentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.scrollContentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.scrollContentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.scrollContentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],

        [self.topCard.topAnchor constraintEqualToAnchor:self.scrollContentView.topAnchor constant:0],
        [self.topCard.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor],
        [self.topCard.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor],

        [self.thumbView.topAnchor constraintEqualToAnchor:self.topCard.topAnchor constant:AS(10)],
        [self.thumbView.centerXAnchor constraintEqualToAnchor:self.topCard.centerXAnchor],
        [self.thumbView.widthAnchor constraintEqualToConstant:previewW],
        [self.thumbView.heightAnchor constraintEqualToConstant:previewH],

        [self.playIcon.leadingAnchor constraintEqualToAnchor:self.thumbView.leadingAnchor constant:AS(15)],
        [self.playIcon.topAnchor constraintEqualToAnchor:self.thumbView.topAnchor constant:AS(15)],
        [self.playIcon.widthAnchor constraintEqualToConstant:AS(30)],
        [self.playIcon.heightAnchor constraintEqualToConstant:AS(30)],

        [row.topAnchor constraintEqualToAnchor:self.thumbView.bottomAnchor constant:AS(30)],
        [row.leadingAnchor constraintEqualToAnchor:self.topCard.leadingAnchor constant:side],
        [row.trailingAnchor constraintEqualToAnchor:self.topCard.trailingAnchor constant:-side],

        [self.progressBar.heightAnchor constraintEqualToConstant:AS(60)],
        [self.progressBar.widthAnchor constraintGreaterThanOrEqualToConstant:AS(150)],

        [self.topCard.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:AS(46)],

        [self.tipLabel.topAnchor constraintEqualToAnchor:self.topCard.bottomAnchor constant:AS(40)],
        [self.tipLabel.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:AS(30)],
        [self.tipLabel.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-AS(30)],
        [self.tipLabel.bottomAnchor constraintEqualToAnchor:self.scrollContentView.bottomAnchor constant:-AS(28)],
    ]];

    [self.view bringSubviewToFront:header];

    dispatch_async(dispatch_get_main_queue(), ^{
        self.cancelBtn.layer.shadowPath =
        [UIBezierPath bezierPathWithRoundedRect:self.cancelBtn.bounds cornerRadius:AS(35)].CGPath;
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

    CGFloat screenScale = UIScreen.mainScreen.scale;

    CGSize target = CGSizeMake(AS(210) * screenScale * 2.0, AS(280) * screenScale * 2.0);

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

#pragma mark - Cancel confirm

- (void)onCancelPressed {
    if (!self.manager || !self.manager.isRunning) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    if (self.showingCancelAlert) return;
    self.showingCancelAlert = YES;

    UIAlertController *ac =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Cancel Conversion",nil)
                                        message:NSLocalizedString(@"Are you sure you want to cancel the conversion of this Video?",nil)
                                 preferredStyle:UIAlertControllerStyleAlert];

    self.cancelAlert = ac;

    __weak typeof(self) weakSelf = self;

    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"NO",nil)
                                          style:UIAlertActionStyleCancel
                                        handler:^(__unused UIAlertAction * _Nonnull action) {
        weakSelf.showingCancelAlert = NO;
        weakSelf.cancelAlert = nil;
        [weakSelf resetPopGesture];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"YES",nil)
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

@end
