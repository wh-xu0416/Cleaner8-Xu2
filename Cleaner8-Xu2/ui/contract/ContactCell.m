#import "ContactCell.h"

#pragma mark - Adapt Helpers

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

@implementation ContactCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = UIColor.whiteColor;
        self.contentView.layer.cornerRadius = AS(10);
        self.contentView.clipsToBounds = YES;

        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.font = ASFontS(16, UIFontWeightBold);
        self.nameLabel.textColor = UIColor.blackColor;
        self.nameLabel.numberOfLines = 1;
        [self.contentView addSubview:self.nameLabel];

        self.phoneLabel = [[UILabel alloc] init];
        self.phoneLabel.font = ASFontS(14, UIFontWeightRegular);
        self.phoneLabel.textColor = UIColor.darkGrayColor;
        self.phoneLabel.numberOfLines = 1;
        [self.contentView addSubview:self.phoneLabel];

        self.checkButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.checkButton setImage:[UIImage systemImageNamed:@"checkmark.circle"] forState:UIControlStateNormal];
        [self.checkButton setImage:[UIImage systemImageNamed:@"checkmark.circle.fill"] forState:UIControlStateSelected];
        [self.checkButton addTarget:self action:@selector(selectButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.checkButton];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat padding = AS(10);

    CGFloat rightPad = AS(40);  
    CGFloat nameH = AS(20);
    CGFloat gap = AS(5);
    CGFloat phoneH = AS(20);

    CGFloat contentW = self.contentView.bounds.size.width;
    CGFloat contentH = self.contentView.bounds.size.height;

    self.nameLabel.frame = CGRectMake(padding,
                                      padding,
                                      contentW - padding - rightPad,
                                      nameH);

    self.phoneLabel.frame = CGRectMake(padding,
                                       CGRectGetMaxY(self.nameLabel.frame) + gap,
                                       contentW - padding - rightPad,
                                       phoneH);

    CGFloat btnW = AS(30);
    CGFloat btnH = AS(30);
    CGFloat btnX = contentW - AS(40);
    CGFloat btnY = (contentH - btnH) * 0.5;

    self.checkButton.frame = CGRectMake(btnX, btnY, btnW, btnH);

    self.checkButton.contentEdgeInsets = UIEdgeInsetsMake(AS(8), AS(8), AS(8), AS(8));
}

- (void)selectButtonTapped {
    if (self.onSelect) {
        self.onSelect();
    }
}

@end
