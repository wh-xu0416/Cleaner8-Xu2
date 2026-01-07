#import "ResultViewController.h"
#import "LearnPageViewController.h"

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
    self.titleLabel.text = @"Great！";
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.textColor = UIColor.blackColor;
    self.titleLabel.font = [UIFont systemFontOfSize:34 weight:UIFontWeightMedium];
    [self.view addSubview:self.titleLabel];

    self.descLabel = [UILabel new];
    self.descLabel.numberOfLines = 2;
    self.descLabel.textAlignment = NSTextAlignmentCenter;
    self.descLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [self.view addSubview:self.descLabel];
    [self updateDescText];

    self.learnMoreBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.learnMoreBtn.backgroundColor = UIColor.whiteColor;
    self.learnMoreBtn.layer.cornerRadius = 22;
    self.learnMoreBtn.clipsToBounds = YES;

    UIImage *moreImg = [[UIImage imageNamed:@"ic_learn"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.learnMoreBtn setImage:moreImg forState:UIControlStateNormal];
    [self.learnMoreBtn setTitle:@"Learn More" forState:UIControlStateNormal];
    [self.learnMoreBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    self.learnMoreBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];

    self.learnMoreBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    self.learnMoreBtn.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    self.learnMoreBtn.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.learnMoreBtn.titleLabel.lineBreakMode = NSLineBreakByClipping;
    self.learnMoreBtn.adjustsImageWhenHighlighted = NO;

    self.learnMoreBtn.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 0);
    self.learnMoreBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 0);

    [self.learnMoreBtn addTarget:self action:@selector(onTapLearnMore) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.learnMoreBtn];

    self.continueBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.continueBtn.backgroundColor = ASColorHex(0x024DFF, 1.0);
    self.continueBtn.layer.cornerRadius = 35;
    self.continueBtn.clipsToBounds = YES;

    [self.continueBtn setTitle:@"Continue" forState:UIControlStateNormal];
    [self.continueBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.continueBtn.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    self.continueBtn.contentEdgeInsets = UIEdgeInsetsMake(23, 0, 23, 0);
    [self.continueBtn addTarget:self action:@selector(onTapContinue) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.continueBtn];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat W = self.view.bounds.size.width;
    CGFloat topSafe = self.view.safeAreaInsets.top;
    CGFloat bottomSafe = self.view.safeAreaInsets.bottom;

    CGFloat gradH = 402;
    self.gradHost.frame = CGRectMake(0, 0, W, gradH);
    self.gradLayer.frame = self.gradHost.bounds;

    CGFloat imgW = 180, imgH = 170;
    CGFloat imgTop = topSafe + 40;
    self.greatImageView.frame = CGRectMake((W - imgW)/2.0, imgTop, imgW, imgH);

    CGFloat titleTop = CGRectGetMaxY(self.greatImageView.frame) + 20;
    self.titleLabel.frame = CGRectMake(20, titleTop, W - 40, 40);

    CGFloat descTop = CGRectGetMaxY(self.titleLabel.frame) + 10;
    self.descLabel.frame = CGRectMake(30, descTop, W - 60, 34);

    CGFloat learnTop = CGRectGetMaxY(self.descLabel.frame) + 30;
    self.learnMoreBtn.frame = CGRectMake((W - 150)/2.0, learnTop, 150, 36);

    CGFloat contTop = CGRectGetMaxY(self.learnMoreBtn.frame) + 110;
    CGFloat contX = 40;
    CGFloat contW = W - contX * 2;

    CGSize fit = [self.continueBtn sizeThatFits:CGSizeMake(contW, CGFLOAT_MAX)];
    CGFloat contH = MAX(60, ceil(fit.height));
    self.continueBtn.frame = CGRectMake(contX, contTop, contW, contH);

    CGFloat bottomLimit = self.view.bounds.size.height - bottomSafe - 20;
    CGFloat over = CGRectGetMaxY(self.continueBtn.frame) - bottomLimit;
    if (over > 0) {
        self.continueBtn.frame = CGRectOffset(self.continueBtn.frame, 0, -over);
    }
}

- (void)updateDescText {
    NSString *countStr = [NSString stringWithFormat:@"%lu", (unsigned long)self.deletedCount];
    NSString *sizeStr  = ASHumanSize(self.freedBytes);

    NSString *line1 = [NSString stringWithFormat:@"You deleted %@ photos today.", countStr];
    NSString *line2 = [NSString stringWithFormat:@"Freed up %@ space on your phone.", sizeStr];
    NSString *full = [NSString stringWithFormat:@"%@\n%@", line1, line2];

    UIColor *blue = ASColorHex(0x024DFF, 1.0);
    UIColor *black = UIColor.blackColor;

    NSMutableAttributedString *att =
    [[NSMutableAttributedString alloc] initWithString:full attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightMedium],
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
