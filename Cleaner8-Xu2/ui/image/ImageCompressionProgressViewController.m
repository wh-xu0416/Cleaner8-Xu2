#import "ImageCompressionProgressViewController.h"
#import "ImageCompressionResultViewController.h"
#import "LivePhotoCoverFrameManager.h"


static inline CGFloat SWDesignWidth(void) { return 402.0; }
static inline CGFloat SWDesignHeight(void) { return 874.0; }
static inline CGFloat SWScaleX(void) {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    return w / SWDesignWidth();
}

static inline CGFloat SWScaleY(void) {
    CGFloat h = UIScreen.mainScreen.bounds.size.height;
    return h / SWDesignHeight();
}

static inline CGFloat ASScale(void) {
    return MIN(SWScaleX(), SWScaleY());
}
static inline CGFloat AS(CGFloat v) { return round(v * ASScale()); }
static inline UIFont *ASFontS(CGFloat s, UIFontWeight w) { return [UIFont systemFontOfSize:round(s * ASScale()) weight:w]; }
static inline UIEdgeInsets ASEdgeInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) { return UIEdgeInsetsMake(AS(t), AS(l), AS(b), AS(r)); }

#pragma mark - Style helpers

static inline UIColor *ASBlue(void) { return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; }
static inline UIColor *ASGrayBG(void){ return [UIColor colorWithRed:246/255.0 green:246/255.0 blue:246/255.0 alpha:1.0]; }

static inline UIFont *ASSB(CGFloat s){ return ASFontS(s, UIFontWeightSemibold); }
static inline UIFont *ASBD(CGFloat s){ return ASFontS(s, UIFontWeightBold); }
static inline UIFont *ASRG(CGFloat s){ return ASFontS(s, UIFontWeightRegular); }

static NSString *ASMB1(uint64_t bytes){
    double mb=(double)bytes/(1024.0*1024.0);
    return [NSString stringWithFormat:@"%.1fMB",mb];
}

#pragma mark - Bubble progress view

@interface ASImageBubbleProgressBarView : UIView
- (void)setProgress:(CGFloat)p percentText:(NSString *)text;
@end

@interface ASImageBubbleProgressBarView ()
@property (nonatomic, strong) UIView *track;
@property (nonatomic, strong) UIView *fill;
@property (nonatomic, strong) UIImageView *icon;

@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UILabel *bubbleLabel;
@property (nonatomic, strong) CAShapeLayer *arrow;

@property (nonatomic, strong) NSLayoutConstraint *fillW;
@property (nonatomic, strong) NSLayoutConstraint *iconCX;
@property (nonatomic, strong) NSLayoutConstraint *bubbleCX;
@property (nonatomic) CGFloat progress;
@end

@implementation ASImageBubbleProgressBarView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {

        CGFloat rTrack = AS(8);
        CGFloat rBubble = AS(8);

        self.track = [UIView new];
        self.track.backgroundColor = [UIColor colorWithWhite:0.86 alpha:1];
        self.track.layer.cornerRadius = rTrack;
        self.track.layer.masksToBounds = YES;

        self.fill = [UIView new];
        self.fill.backgroundColor = ASBlue();
        self.fill.layer.cornerRadius = rTrack;
        self.fill.layer.masksToBounds = YES;

        self.icon = [UIImageView new];
        self.icon.contentMode = UIViewContentModeScaleAspectFit;
        self.icon.image = [[UIImage imageNamed:@"ic_speed"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        self.icon.tintColor = nil;
        self.icon.layer.zPosition = 9999;

        self.bubble = [UIView new];
        self.bubble.backgroundColor = ASBlue();
        self.bubble.layer.cornerRadius = rBubble;
        self.bubble.layer.masksToBounds = YES;

        self.bubbleLabel = [UILabel new];
        self.bubbleLabel.font = ASSB(15);
        self.bubbleLabel.textColor = UIColor.whiteColor;
        self.bubbleLabel.textAlignment = NSTextAlignmentCenter;
        self.bubbleLabel.text = @"0%";

        self.arrow = [CAShapeLayer layer];
        self.arrow.fillColor = ASBlue().CGColor;

        [self addSubview:self.track];
        [self.track addSubview:self.fill];
        [self addSubview:self.icon];
        [self addSubview:self.bubble];
        [self.bubble addSubview:self.bubbleLabel];
        [self.layer addSublayer:self.arrow];

        for (UIView *v in @[self.track,self.fill,self.icon,self.bubble,self.bubbleLabel]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
        }

        CGFloat trackH = AS(16);
        CGFloat iconS  = AS(28);
        CGFloat bubbleH = AS(40);

        [NSLayoutConstraint activateConstraints:@[
            [self.track.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.track.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [self.track.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:0],
            [self.track.heightAnchor constraintEqualToConstant:trackH],

            [self.fill.leadingAnchor constraintEqualToAnchor:self.track.leadingAnchor],
            [self.fill.topAnchor constraintEqualToAnchor:self.track.topAnchor],
            [self.fill.bottomAnchor constraintEqualToAnchor:self.track.bottomAnchor],

            [self.icon.centerYAnchor constraintEqualToAnchor:self.track.centerYAnchor constant:AS(2)],
            [self.icon.widthAnchor constraintEqualToConstant:iconS],
            [self.icon.heightAnchor constraintEqualToConstant:iconS],

            [self.bubble.bottomAnchor constraintEqualToAnchor:self.track.topAnchor constant:-AS(10)],
            [self.bubble.heightAnchor constraintEqualToConstant:bubbleH],

            [self.bubbleLabel.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:AS(5)],
            [self.bubbleLabel.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-AS(5)],
            [self.bubbleLabel.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:AS(8)],
            [self.bubbleLabel.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-AS(8)],
        ]];

        self.fillW = [self.fill.widthAnchor constraintEqualToConstant:0];
        self.fillW.active = YES;

        self.iconCX = [self.icon.centerXAnchor constraintEqualToAnchor:self.track.leadingAnchor constant:0];
        self.iconCX.active = YES;

        self.bubbleCX = [self.bubble.centerXAnchor constraintEqualToAnchor:self.track.leadingAnchor constant:0];
        self.bubbleCX.active = YES;

        [self bringSubviewToFront:self.icon];
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

    CGFloat w = self.track.bounds.size.width;
    if (w <= 0) return;

    CGFloat fill = w * self.progress;
    self.fillW.constant = fill;

    CGFloat iconW = AS(28);

    CGFloat bubbleW = [self.bubble systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width;
    if (bubbleW <= 0) bubbleW = AS(60);

    CGFloat x = fill;

    CGFloat iconX = MIN(MAX(x, iconW * 0.5), w - iconW * 0.5);
    CGFloat bubbleX = MIN(MAX(x, bubbleW * 0.5), w - bubbleW * 0.5);

    self.iconCX.constant = iconX;
    self.bubbleCX.constant = bubbleX;

    CGRect b = self.bubble.frame;
    CGFloat baseY = CGRectGetMaxY(b);
    CGFloat cx = CGRectGetMidX(b);

    CGFloat a = AS(6);
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(cx - a, baseY)];
    [path addLineToPoint:CGPointMake(cx + a, baseY)];
    [path addLineToPoint:CGPointMake(cx, baseY + a)];
    [path closePath];
    self.arrow.path = path.CGPath;
}

@end

#pragma mark - Grid cell

@interface ASProgCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iv;
@property (nonatomic, copy) NSString *representedAssetId;
@end

@implementation ASProgCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.iv = [UIImageView new];
        self.iv.contentMode = UIViewContentModeScaleAspectFill;
        self.iv.layer.cornerRadius = AS(11);
        self.iv.layer.masksToBounds = YES;
        self.iv.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1];
        self.iv.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.iv];
        [NSLayoutConstraint activateConstraints:@[
            [self.iv.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.iv.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.iv.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.iv.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.iv.image = nil;
    self.representedAssetId = nil;
}
@end

#pragma mark - VC

@interface ImageCompressionProgressViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate>

typedef NS_ENUM(NSInteger, ASProgressMode) {
    ASProgressModeImageCompress = 0,
    ASProgressModeLiveCover     = 1,
};
@property (nonatomic, strong, nullable) UIAlertController *cancelAlert;

@property (nonatomic) ASProgressMode mode;
@property (nonatomic) BOOL deleteOriginalLive;

@property (nonatomic, strong) LivePhotoCoverFrameManager *liveManager;

@property (nonatomic, weak) id<UIGestureRecognizerDelegate> popDelegateBackup;

@property (nonatomic, strong) NSArray<PHAsset *> *assets;
@property (nonatomic) ASImageCompressionQuality quality;
@property (nonatomic) uint64_t totalBeforeBytes;
@property (nonatomic) uint64_t estimatedAfterBytes;

@property (nonatomic, strong) ImageCompressionManager *manager;
@property (nonatomic) BOOL showingCancelAlert;
@property (nonatomic) BOOL didExit;

@property (nonatomic, strong) UIView *topCard;

@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UILabel *titleLabel;

@property (nonatomic, strong) UICollectionView *grid;

@property (nonatomic, strong) UILabel *beforeLabel;
@property (nonatomic, strong) UILabel *afterLabel;
@property (nonatomic, strong) ASImageBubbleProgressBarView *bar;

@property (nonatomic, strong) UILabel *tipLabel;
@property (nonatomic, strong) UIButton *cancelBtn;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *scrollContentView;

@end

@implementation ImageCompressionProgressViewController

- (void)as_dismissPresentedIfNeededThen:(dispatch_block_t)block {
    UIViewController *presented = self.presentedViewController;
    if (presented) {
        [self dismissViewControllerAnimated:NO completion:block];
    } else {
        if (block) block();
    }
}

- (void)as_finishWithSummary:(ASImageCompressionSummary * _Nullable)summary
                       error:(NSError * _Nullable)error
                 failedTitle:(NSString *)failedTitle {

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
            [UIAlertController alertControllerWithTitle:failedTitle
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

        ImageCompressionResultViewController *vc =
        [[ImageCompressionResultViewController alloc] initWithSummary:summary];

        [self.navigationController pushViewController:vc animated:YES];
    }];
}

- (instancetype)initWithLiveAssets:(NSArray<PHAsset *> *)assets
                   totalBeforeBytes:(uint64_t)beforeBytes
                estimatedAfterBytes:(uint64_t)afterBytes
                      deleteOriginal:(BOOL)deleteOriginal {
    if (self = [super init]) {
        _assets = assets ?: @[];
        _mode = ASProgressModeLiveCover;
        _deleteOriginalLive = deleteOriginal;
        _totalBeforeBytes = beforeBytes;
        _estimatedAfterBytes = afterBytes;
        _showingCancelAlert = NO;
        _didExit = NO;
    }
    return self;
}

- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets
                       quality:(ASImageCompressionQuality)quality
               totalBeforeBytes:(uint64_t)beforeBytes
            estimatedAfterBytes:(uint64_t)afterBytes {
    if (self = [super init]) {
        _assets = assets ?: @[];
        _quality = quality;
        _totalBeforeBytes = beforeBytes;
        _estimatedAfterBytes = afterBytes;
        _showingCancelAlert = NO;
        _didExit = NO;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBarHidden = YES;
    self.view.backgroundColor = ASGrayBG();

    [self buildUI];
    [self updateSizeTexts];

    [self startCompress];
}

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
            [self onCancelTapped];
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

    // 设计稿 gridSide=352、cell=114、gap=5 => 114*3 + 5*2 = 352
    CGFloat gridSide = AS(352);

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
    [self.backBtn addTarget:self action:@selector(onCancelTapped) forControlEvents:UIControlEventTouchUpInside];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.backBtn];

    self.titleLabel = [UILabel new];
    self.titleLabel.text = NSLocalizedString(@"In Process",nil);
    self.titleLabel.font = ASSB(24);
    self.titleLabel.textColor = UIColor.blackColor;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.titleLabel];

    self.cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cancelBtn setTitle:NSLocalizedString(@"Cancel",nil) forState:UIControlStateNormal];
    self.cancelBtn.titleLabel.font = ASBD(20);
    [self.cancelBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.cancelBtn.backgroundColor = ASBlue();
    self.cancelBtn.layer.cornerRadius = AS(35);
    self.cancelBtn.layer.masksToBounds = NO;
    self.cancelBtn.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.18].CGColor;
    self.cancelBtn.layer.shadowOpacity = 1.0;
    self.cancelBtn.layer.shadowOffset = CGSizeMake(0, AS(10));
    self.cancelBtn.layer.shadowRadius = AS(18);
    [self.cancelBtn addTarget:self action:@selector(onCancelTapped) forControlEvents:UIControlEventTouchUpInside];
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

    UICollectionViewFlowLayout *lay = [UICollectionViewFlowLayout new];
    lay.minimumLineSpacing = AS(5);
    lay.minimumInteritemSpacing = AS(5);
    lay.sectionInset = UIEdgeInsetsZero;

    self.grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:lay];
    self.grid.backgroundColor = UIColor.clearColor;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    self.grid.scrollEnabled = NO;
    self.grid.translatesAutoresizingMaskIntoConstraints = NO;
    [self.grid registerClass:ASProgCell.class forCellWithReuseIdentifier:@"p"];
    [self.topCard addSubview:self.grid];

    self.beforeLabel = [UILabel new];
    self.beforeLabel.font = ASRG(15);
    self.beforeLabel.textColor = UIColor.blackColor;

    self.afterLabel = [UILabel new];
    self.afterLabel.font = ASSB(15);
    self.afterLabel.textColor = ASBlue();

    self.bar = [ASImageBubbleProgressBarView new];
    self.bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bar setProgress:0 percentText:@"0%"];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.beforeLabel, self.bar, self.afterLabel]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentBottom;
    row.spacing = AS(16);
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topCard addSubview:row];

    [self.beforeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.afterLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    self.tipLabel = [UILabel new];
    self.tipLabel.font = ASRG(17);
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

        // grid
        [self.grid.topAnchor constraintEqualToAnchor:self.topCard.topAnchor constant:AS(10)],
        [self.grid.centerXAnchor constraintEqualToAnchor:self.topCard.centerXAnchor],
        [self.grid.widthAnchor constraintEqualToConstant:gridSide],
        [self.grid.heightAnchor constraintEqualToConstant:gridSide],

        // row
        [row.topAnchor constraintEqualToAnchor:self.grid.bottomAnchor constant:AS(30)],
        [row.leadingAnchor constraintEqualToAnchor:self.topCard.leadingAnchor constant:side],
        [row.trailingAnchor constraintEqualToAnchor:self.topCard.trailingAnchor constant:-side],

        [self.bar.heightAnchor constraintEqualToConstant:AS(60)],
        [self.bar.widthAnchor constraintGreaterThanOrEqualToConstant:AS(150)],

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
    self.beforeLabel.text = self.totalBeforeBytes ? ASMB1(self.totalBeforeBytes) : @"--";
    self.afterLabel.text  = self.estimatedAfterBytes ? ASMB1(self.estimatedAfterBytes) : @"--";
}

#pragma mark - Compress

- (void)startCompress {
    __weak typeof(self) weakSelf = self;

    if (self.mode == ASProgressModeLiveCover) {
        self.liveManager = [LivePhotoCoverFrameManager new];

        [self.liveManager convertLiveAssets:self.assets
                              deleteOriginal:self.deleteOriginalLive
                                    progress:^(NSInteger currentIndex, NSInteger totalCount, float overallProgress, PHAsset *currentAsset) {

            dispatch_async(dispatch_get_main_queue(), ^{
                if (weakSelf.didExit) return;
                int percent = (int)lrintf(overallProgress * 100.0f);
                percent = MAX(0, MIN(100, percent));
                [weakSelf.bar setProgress:overallProgress percentText:[NSString stringWithFormat:@"%d%%", percent]];
            });

        } completion:^(ASImageCompressionSummary * _Nullable summary, NSError * _Nullable error) {
            [weakSelf as_finishWithSummary:summary error:error failedTitle:NSLocalizedString(@"Convert Failed",nil)];
        }];
        return;
    }

    self.manager = [ImageCompressionManager new];
    [self.manager compressAssets:self.assets
                         quality:self.quality
                        progress:^(NSInteger currentIndex, NSInteger totalCount, float overallProgress, PHAsset *currentAsset) {

        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.didExit) return;
            int percent = (int)lrintf(overallProgress * 100.0f);
            percent = MAX(0, MIN(100, percent));
            [weakSelf.bar setProgress:overallProgress percentText:[NSString stringWithFormat:@"%d%%", percent]];
        });

    } completion:^(ASImageCompressionSummary * _Nullable summary, NSError * _Nullable error) {
        [weakSelf as_finishWithSummary:summary error:error failedTitle:NSLocalizedString(@"Compress Failed",nil)];
    }];
}

#pragma mark - Cancel confirm

- (void)onCancelTapped {

    BOOL isRunning = NO;
    if (self.mode == ASProgressModeLiveCover) {
        isRunning = (self.liveManager != nil);
    } else {
        isRunning = self.manager.isRunning;
    }

    if (!isRunning) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    if (self.showingCancelAlert) return;
    self.showingCancelAlert = YES;

    UIAlertController *ac =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Cancel Conversion",nil)
                                        message:NSLocalizedString(@"Are you sure you want to cancel the conversion of this Photo?",nil)
                                 preferredStyle:UIAlertControllerStyleAlert];

    self.cancelAlert = ac;

    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"NO",nil) style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.showingCancelAlert = NO;
        self.cancelAlert = nil;
        [self resetPopGesture];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"YES",nil) style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.showingCancelAlert = NO;
        self.cancelAlert = nil;

        self.didExit = YES;

        if (self.mode == ASProgressModeLiveCover) {
            [self.liveManager cancel];
        } else {
            [self.manager cancel];
        }
        [self.navigationController popViewControllerAnimated:YES];
    }]];

    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Grid

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return MIN(self.assets.count, 9);
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ASProgCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"p" forIndexPath:indexPath];
    PHAsset *a = self.assets[indexPath.item];

    cell.representedAssetId = a.localIdentifier;
    cell.iv.image = nil;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.resizeMode = PHImageRequestOptionsResizeModeExact;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    opt.synchronous = NO;

    CGFloat scale = UIScreen.mainScreen.scale;

    CGFloat cellSide = AS(114);
    CGFloat px = cellSide * scale * 2.0;
    CGSize target = CGSizeMake(px, px);

    [[PHImageManager defaultManager] requestImageForAsset:a
                                              targetSize:target
                                             contentMode:PHImageContentModeAspectFill
                                                 options:opt
                                           resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;
        if ([cell.representedAssetId isEqualToString:a.localIdentifier]) {
            cell.iv.image = result;
        }
    }];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout*)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat s = AS(114);
    return CGSizeMake(s, s);
}

@end
