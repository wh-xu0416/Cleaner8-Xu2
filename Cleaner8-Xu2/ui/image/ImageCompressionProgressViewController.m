#import "ImageCompressionProgressViewController.h"
#import "ImageCompressionResultViewController.h"

static inline UIColor *ASBlue(void) { return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; }
static inline UIColor *ASGrayBG(void){ return [UIColor colorWithRed:246/255.0 green:246/255.0 blue:246/255.0 alpha:1.0]; }
static inline UIFont *ASSB(CGFloat s){ return [UIFont systemFontOfSize:s weight:UIFontWeightSemibold]; }
static inline UIFont *ASBD(CGFloat s){ return [UIFont systemFontOfSize:s weight:UIFontWeightBold]; }
static inline UIFont *ASRG(CGFloat s){ return [UIFont systemFontOfSize:s weight:UIFontWeightRegular]; }
static NSString *ASMB1(uint64_t bytes){ double mb=(double)bytes/(1024.0*1024.0); return [NSString stringWithFormat:@"%.1fMB",mb]; }

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
        self.track = [UIView new];
        self.track.backgroundColor = [UIColor colorWithWhite:0.86 alpha:1];
        self.track.layer.cornerRadius = 8;
        self.track.layer.masksToBounds = YES;

        self.fill = [UIView new];
        self.fill.backgroundColor = ASBlue();
        self.fill.layer.cornerRadius = 8;
        self.fill.layer.masksToBounds = YES;

        self.icon = [UIImageView new];
        self.icon.contentMode = UIViewContentModeScaleAspectFit;
        if (@available(iOS 13.0,*)) self.icon.image = [UIImage systemImageNamed:@"paperplane.fill"]; // 占位
        self.icon.tintColor = ASBlue();

        self.bubble = [UIView new];
        self.bubble.backgroundColor = ASBlue();
        self.bubble.layer.cornerRadius = 10;
        self.bubble.layer.masksToBounds = YES;

        self.bubbleLabel = [UILabel new];
        self.bubbleLabel.font = ASSB(18);
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

        [NSLayoutConstraint activateConstraints:@[
            [self.track.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.track.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            // ✅ track 底部贴 bar 底部（用于和左右文案底部对齐）
            [self.track.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:0],
            [self.track.heightAnchor constraintEqualToConstant:16],

            [self.fill.leadingAnchor constraintEqualToAnchor:self.track.leadingAnchor],
            [self.fill.topAnchor constraintEqualToAnchor:self.track.topAnchor],
            [self.fill.bottomAnchor constraintEqualToAnchor:self.track.bottomAnchor],

            // icon 覆盖在进度条上方（不被裁切）
            [self.icon.centerYAnchor constraintEqualToAnchor:self.track.centerYAnchor],
            [self.icon.widthAnchor constraintEqualToConstant:26],
            [self.icon.heightAnchor constraintEqualToConstant:26],

            [self.bubble.bottomAnchor constraintEqualToAnchor:self.track.topAnchor constant:-10],
            // ✅ bubble 高度加大，匹配上下内边距 8
            [self.bubble.heightAnchor constraintEqualToConstant:40],

            // ✅ bubbleLabel：上下 8，左右 5
            [self.bubbleLabel.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:5],
            [self.bubbleLabel.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-5],
            [self.bubbleLabel.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:8],
            [self.bubbleLabel.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-8],
        ]];

        self.fillW = [self.fill.widthAnchor constraintEqualToConstant:0];
        self.fillW.active = YES;

        self.iconCX = [self.icon.centerXAnchor constraintEqualToAnchor:self.track.leadingAnchor constant:0];
        self.iconCX.active = YES;

        self.bubbleCX = [self.bubble.centerXAnchor constraintEqualToAnchor:self.track.leadingAnchor constant:0];
        self.bubbleCX.active = YES;

        // ✅ 确保 icon 永远在最上层（覆盖在进度条上方）
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

    CGFloat iconW = 26;

    // ✅ 用 AutoLayout 计算 bubble 实际宽度（避免 0 导致 clamp 不准）
    CGFloat bubbleW = [self.bubble systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width;
    if (bubbleW <= 0) bubbleW = 60;

    CGFloat x = fill;

    CGFloat iconX = MIN(MAX(x, iconW * 0.5), w - iconW * 0.5);
    CGFloat bubbleX = MIN(MAX(x, bubbleW * 0.5), w - bubbleW * 0.5);

    self.iconCX.constant = iconX;
    self.bubbleCX.constant = bubbleX;

    CGRect b = self.bubble.frame;
    CGFloat baseY = CGRectGetMaxY(b);
    CGFloat cx = CGRectGetMidX(b);

    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(cx - 6, baseY)];
    [path addLineToPoint:CGPointMake(cx + 6, baseY)];
    [path addLineToPoint:CGPointMake(cx, baseY + 6)];
    [path closePath];
    self.arrow.path = path.CGPath;
}

@end

#pragma mark - Grid cell

@interface ASProgCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iv;
@end
@implementation ASProgCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.iv = [UIImageView new];
        self.iv.contentMode = UIViewContentModeScaleAspectFill;
        self.iv.layer.cornerRadius = 18;
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
@end

#pragma mark - VC

@interface ImageCompressionProgressViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate>
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
@end

@implementation ImageCompressionProgressViewController

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
    CGFloat side = 20;

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

    self.backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.backBtn.tintColor = ASBlue();
    if (@available(iOS 13.0,*)) [self.backBtn setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    [self.backBtn addTarget:self action:@selector(onCancelTapped) forControlEvents:UIControlEventTouchUpInside];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;

    self.titleLabel = [UILabel new];
    self.titleLabel.text = @"In Process";
    self.titleLabel.font = ASSB(28);
    self.titleLabel.textColor = UIColor.blackColor;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [header addSubview:self.backBtn];
    [header addSubview:self.titleLabel];

    // ✅ grid：item 114，间距 5
    UICollectionViewFlowLayout *lay = [UICollectionViewFlowLayout new];
    lay.minimumLineSpacing = 5;
    lay.minimumInteritemSpacing = 5;
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
    self.beforeLabel.font = ASRG(22);
    self.beforeLabel.textColor = UIColor.blackColor;

    self.afterLabel = [UILabel new];
    self.afterLabel.font = ASSB(22);
    self.afterLabel.textColor = ASBlue();

    self.bar = [ASImageBubbleProgressBarView new];
    self.bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bar setProgress:0 percentText:@"0%"];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.beforeLabel, self.bar, self.afterLabel]];
    row.axis = UILayoutConstraintAxisHorizontal;

    // ✅ 底部对齐（进度条底部与两边文案底部对齐）
    row.alignment = UIStackViewAlignmentBottom;

    row.spacing = 16;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topCard addSubview:row];

    [self.beforeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.afterLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    self.tipLabel = [UILabel new];
    self.tipLabel.font = ASRG(17);
    self.tipLabel.textColor = [UIColor colorWithWhite:0.15 alpha:1];
    self.tipLabel.numberOfLines = 0;
    self.tipLabel.lineBreakMode = NSLineBreakByWordWrapping; // ✅ 多行更稳
    self.tipLabel.textAlignment = NSTextAlignmentCenter;
    self.tipLabel.text = @"It is recommended not to minimize\nor close the app...";
    self.tipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tipLabel];

    self.cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cancelBtn setTitle:@"Cancel" forState:UIControlStateNormal];
    self.cancelBtn.titleLabel.font = ASBD(20);
    [self.cancelBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.cancelBtn.backgroundColor = ASBlue();
    self.cancelBtn.layer.cornerRadius = 35;
    self.cancelBtn.layer.masksToBounds = NO;
    self.cancelBtn.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.18].CGColor;
    self.cancelBtn.layer.shadowOpacity = 1.0;
    self.cancelBtn.layer.shadowOffset = CGSizeMake(0, 10);
    self.cancelBtn.layer.shadowRadius = 18;
    [self.cancelBtn addTarget:self action:@selector(onCancelTapped) forControlEvents:UIControlEventTouchUpInside];
    self.cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.cancelBtn];

    // ✅ gridSide = 114*3 + 5*2 = 352
    CGFloat gridSide = 352;

    [NSLayoutConstraint activateConstraints:@[
        [self.topCard.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.topCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

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

        // ✅ 九宫格距离 titlebar 10
        [self.grid.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10],
        [self.grid.centerXAnchor constraintEqualToAnchor:self.topCard.centerXAnchor],
        [self.grid.widthAnchor constraintEqualToConstant:gridSide],
        [self.grid.heightAnchor constraintEqualToConstant:gridSide],

        // ✅ 九宫格到气泡/进度条这一行 30
        [row.topAnchor constraintEqualToAnchor:self.grid.bottomAnchor constant:30],
        [row.leadingAnchor constraintEqualToAnchor:self.topCard.leadingAnchor constant:side],
        [row.trailingAnchor constraintEqualToAnchor:self.topCard.trailingAnchor constant:-side],

        [self.bar.heightAnchor constraintEqualToConstant:60],
        [self.bar.widthAnchor constraintGreaterThanOrEqualToConstant:150],

        [self.topCard.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:66],

        [self.tipLabel.topAnchor constraintEqualToAnchor:self.topCard.bottomAnchor constant:46],
        [self.tipLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:30],
        [self.tipLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-30],

        [self.cancelBtn.topAnchor constraintEqualToAnchor:self.tipLabel.bottomAnchor constant:28],
        [self.cancelBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.cancelBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        [self.cancelBtn.heightAnchor constraintEqualToConstant:70],
        [self.cancelBtn.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-22],
    ]];

    dispatch_async(dispatch_get_main_queue(), ^{
        self.cancelBtn.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.cancelBtn.bounds cornerRadius:35].CGPath;
    });
}

- (void)updateSizeTexts {
    self.beforeLabel.text = self.totalBeforeBytes ? ASMB1(self.totalBeforeBytes) : @"--";
    self.afterLabel.text  = self.estimatedAfterBytes ? ASMB1(self.estimatedAfterBytes) : @"--";
}

#pragma mark - Compress

- (void)startCompress {
    self.manager = [ImageCompressionManager new];

    __weak typeof(self) weakSelf = self;
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

        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.didExit) return;

            if (error) {
                if (error.code == -999) { // cancel
                    [weakSelf.navigationController popViewControllerAnimated:YES];
                    return;
                }
                UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Compress Failed"
                                                                            message:error.localizedDescription ?: @"Unknown error"
                                                                     preferredStyle:UIAlertControllerStyleAlert];
                [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [weakSelf.navigationController popViewControllerAnimated:YES];
                }]];
                [weakSelf presentViewController:ac animated:YES completion:nil];
                return;
            }

            ImageCompressionResultViewController *vc =
            [[ImageCompressionResultViewController alloc] initWithSummary:summary];
            [weakSelf.navigationController pushViewController:vc animated:YES];
        });
    }];
}

#pragma mark - Cancel confirm (back / cancel / swipe all use this)

- (void)onCancelTapped {
    if (!self.manager.isRunning) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    if (self.showingCancelAlert) return;
    self.showingCancelAlert = YES;

    UIAlertController *ac =
    [UIAlertController alertControllerWithTitle:@"Cancel Conversion"
                                        message:@"Are you sure you want to cancel the conversion of this Photo?"
                                 preferredStyle:UIAlertControllerStyleAlert];

    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"NO" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        weakSelf.showingCancelAlert = NO;
        [weakSelf resetPopGesture];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"YES" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        weakSelf.showingCancelAlert = NO;
        weakSelf.didExit = YES;
        [weakSelf.manager cancel];
        [weakSelf.navigationController popViewControllerAnimated:YES];
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

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;

    [[PHImageManager defaultManager] requestImageForAsset:a
                                              targetSize:CGSizeMake(500, 500)
                                             contentMode:PHImageContentModeAspectFill
                                                 options:opt
                                           resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (result) cell.iv.image = result;
    }];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout*)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(114, 114);
}

@end
