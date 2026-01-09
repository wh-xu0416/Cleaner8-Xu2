#import "ResultViewController.h"
#import "LearnPageViewController.h"
#import "Common.h"

static inline UIColor *ASColorHex(uint32_t rgb, CGFloat a) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF)/255.0
                           green:((rgb >> 8) & 0xFF)/255.0
                            blue:(rgb & 0xFF)/255.0
                           alpha:a];
}

static inline NSString *ASHumanSize(uint64_t bytes) {
    double b = (double)bytes;
    if (b < 1024) return [NSString stringWithFormat:@"%.0f B", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f KB", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f MB", b];
    b /= 1024; return [NSString stringWithFormat:@"%.2f GB", b];
}

static inline CGFloat SWDesignWidth(void) { return 402.0; }
static inline CGFloat SWScale(void) {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    return MIN(1.0, w / SWDesignWidth());
}
static inline CGFloat SW(CGFloat v) { return round(v * SWScale()); }
static inline UIFont *SWFontS(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:round(size * SWScale()) weight:weight];
}
static inline UIEdgeInsets SWInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) {
    return UIEdgeInsetsMake(SW(t), SW(l), SW(b), SW(r));
}

@interface ResultViewController ()
@property (nonatomic) NSUInteger deletedCount;
@property (nonatomic) uint64_t freedBytes;

@property (nonatomic, strong) UIView *gradHost;
@property (nonatomic, strong) CAGradientLayer *gradLayer;

@property (nonatomic, strong) UIImageView *greatImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *descLabel;

@property (nonatomic, strong) UIButton *learnMoreBtn;
@property (nonatomic, strong) UIButton *continueBtn;
@end

@implementation ResultViewController

- (instancetype)initWithDeletedCount:(NSUInteger)deletedCount freedBytes:(uint64_t)freedBytes {
    if (self = [super init]) {
        _deletedCount = deletedCount;
        _freedBytes = freedBytes;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = ASColorHex(0xF6F6F6, 1.0);

    self.gradHost = [[UIView alloc] initWithFrame:CGRectZero];
    self.gradHost.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.gradHost];

    self.gradLayer = [CAGradientLayer layer];
    self.gradLayer.startPoint = CGPointMake(0.5, 0.0);
    self.gradLayer.endPoint   = CGPointMake(0.5, 1.0);
    self.gradLayer.colors = @[
        (id)ASColorHex(0xE0E0E0, 1.0).CGColor,
        (id)ASColorHex(0x008DFF, 0.0).CGColor
    ];
    self.gradLayer.locations = @[@0.0, @1.0];
    [self.gradHost.layer addSublayer:self.gradLayer];

    self.greatImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_img_great"]];
    self.greatImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.view addSubview:self.greatImageView];

    self.titleLabel = [UILabel new];
    self.titleLabel.text = NSLocalizedString(@"Great!", nil);
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.textColor = UIColor.blackColor;
    self.titleLabel.font = SWFontS(34, UIFontWeightMedium);
    [self.view addSubview:self.titleLabel];

    self.descLabel = [UILabel new];
    self.descLabel.numberOfLines = 2;
    self.descLabel.textAlignment = NSTextAlignmentCenter;
    self.descLabel.font = SWFontS(12, UIFontWeightMedium);
    [self.view addSubview:self.descLabel];
    [self updateDescText];

    self.learnMoreBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.learnMoreBtn.backgroundColor = UIColor.whiteColor;
    self.learnMoreBtn.layer.cornerRadius = SW(22);
    self.learnMoreBtn.clipsToBounds = YES;

    UIImage *moreImg = [[UIImage imageNamed:@"ic_learn"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.learnMoreBtn setImage:moreImg forState:UIControlStateNormal];
    [self.learnMoreBtn setTitle:NSLocalizedString(@"Learn More", nil) forState:UIControlStateNormal];
    [self.learnMoreBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    self.learnMoreBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];

    self.learnMoreBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    self.learnMoreBtn.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    self.learnMoreBtn.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.learnMoreBtn.titleLabel.lineBreakMode = NSLineBreakByClipping;
    self.learnMoreBtn.adjustsImageWhenHighlighted = NO;

    self.learnMoreBtn.imageEdgeInsets = SWInsets(0, -6, 0, 0);
    self.learnMoreBtn.titleEdgeInsets = SWInsets(0, 6, 0, 0);

    [self.learnMoreBtn addTarget:self action:@selector(onTapLearnMore) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.learnMoreBtn];

    self.continueBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.continueBtn.backgroundColor = ASColorHex(0x024DFF, 1.0);
    self.continueBtn.layer.cornerRadius = SW(35);
    self.continueBtn.clipsToBounds = YES;

    [self.continueBtn setTitle:NSLocalizedString(@"Continue", nil) forState:UIControlStateNormal];
    [self.continueBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.continueBtn.titleLabel.font = SWFontS(20, UIFontWeightBold);
    self.continueBtn.contentEdgeInsets = SWInsets(23, 0, 23, 0);
    [self.continueBtn addTarget:self action:@selector(onTapContinue) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.continueBtn];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat W = self.view.bounds.size.width;
    CGFloat topSafe = self.view.safeAreaInsets.top;
    CGFloat bottomSafe = self.view.safeAreaInsets.bottom;

    CGFloat gradH = SW(402);
    self.gradHost.frame = CGRectMake(0, 0, W, gradH);
    self.gradLayer.frame = self.gradHost.bounds;

    CGFloat imgW = SW(180), imgH = SW(170);
    CGFloat imgTop = topSafe + SW(40);
    self.greatImageView.frame = CGRectMake((W - imgW)/2.0, imgTop, imgW, imgH);

    CGFloat titleTop = CGRectGetMaxY(self.greatImageView.frame) + SW(20);
    self.titleLabel.frame = CGRectMake(SW(20), titleTop, W - SW(40), SW(40));

    CGFloat descTop = CGRectGetMaxY(self.titleLabel.frame) + SW(10);
    self.descLabel.frame = CGRectMake(SW(30), descTop, W - SW(60), SW(34));

    CGFloat learnTop = CGRectGetMaxY(self.descLabel.frame) + SW(30);
    self.learnMoreBtn.frame = CGRectMake((W - SW(150))/2.0, learnTop, SW(150), SW(36));

    CGFloat contTop = CGRectGetMaxY(self.learnMoreBtn.frame) + SW(110);
    CGFloat contX = SW(40);
    CGFloat contW = W - contX * 2;

    CGSize fit = [self.continueBtn sizeThatFits:CGSizeMake(contW, CGFLOAT_MAX)];
    CGFloat contH = MAX(SW(60), ceil(fit.height));
    self.continueBtn.frame = CGRectMake(contX, contTop, contW, contH);

    CGFloat bottomLimit = self.view.bounds.size.height - bottomSafe - SW(20);
    CGFloat over = CGRectGetMaxY(self.continueBtn.frame) - bottomLimit;
    if (over > 0) {
        self.continueBtn.frame = CGRectOffset(self.continueBtn.frame, 0, -over);
    }
}

- (void)updateDescText {
    NSString *countStr = [NSString stringWithFormat:@"%lu", (unsigned long)self.deletedCount];
    NSString *sizeStr  = ASHumanSize(self.freedBytes);

    NSString *line1 = [NSString stringWithFormat:NSLocalizedString(@"You deleted %@ photos today.", nil), countStr];
    NSString *line2 = [NSString stringWithFormat:NSLocalizedString(@"Freed up %@ space on your phone.", nil), sizeStr];
    NSString *full = [NSString stringWithFormat:@"%@\n%@", line1, line2];

    UIColor *blue = ASColorHex(0x024DFF, 1.0);
    UIColor *black = UIColor.blackColor;

    NSMutableAttributedString *att =
    [[NSMutableAttributedString alloc] initWithString:full attributes:@{
        NSFontAttributeName: SWFontS(12, UIFontWeightMedium),
        NSForegroundColorAttributeName: black
    }];

    NSRange rCount = [full rangeOfString:countStr];
    if (rCount.location != NSNotFound) {
        [att addAttribute:NSForegroundColorAttributeName value:blue range:rCount];
    }

    NSRange rSize = [full rangeOfString:sizeStr];
    if (rSize.location != NSNotFound) {
        [att addAttribute:NSForegroundColorAttributeName value:blue range:rSize];
    }

    self.descLabel.attributedText = att;
}

#pragma mark - Actions

- (void)onTapLearnMore {
    LearnPageViewController *learnPageVC = [[LearnPageViewController alloc] init];
    
    [self.navigationController pushViewController:learnPageVC animated:YES];
}

- (void)onTapContinue {
    [self.navigationController popViewControllerAnimated:YES];
}

@end
