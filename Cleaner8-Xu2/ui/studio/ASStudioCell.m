#import "ASStudioCell.h"

#pragma mark - 402 Design Adapt Helpers

static inline CGFloat ASDesignWidth(void) { return 402.0; }
static inline CGFloat ASScale(void) {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    return MIN(1.0, w / ASDesignWidth());
}
static inline CGFloat AS(CGFloat v) { return round(v * ASScale()); }
static inline UIEdgeInsets ASEdgeInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) {
    return UIEdgeInsetsMake(AS(t), AS(l), AS(b), AS(r));
}
static inline UIFont *ASFontS(CGFloat s, UIFontWeight w) {
    return [UIFont systemFontOfSize:round(s * ASScale()) weight:w];
}

@interface ASStudioCell ()
@property (nonatomic, strong) UIView *card;
@end

@implementation ASStudioCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {

        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _card = [UIView new];
        _card.translatesAutoresizingMaskIntoConstraints = NO;
        _card.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        _card.layer.cornerRadius = AS(16);
        _card.layer.masksToBounds = YES;
        if (@available(iOS 13.0, *)) {
            _card.layer.cornerCurve = kCACornerCurveContinuous;
        }
        [self.contentView addSubview:_card];

        [NSLayoutConstraint activateConstraints:@[
            [_card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:AS(10)],
            [_card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-AS(10)],
            [_card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:AS(5)],
            [_card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-AS(5)],
        ]];

        _thumbView = [UIImageView new];
        _thumbView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbView.clipsToBounds = YES;
        _thumbView.layer.cornerRadius = AS(8);
        _thumbView.layer.masksToBounds = YES;
        if (@available(iOS 13.0, *)) {
            _thumbView.layer.cornerCurve = kCACornerCurveContinuous;
        }
        [_card addSubview:_thumbView];

        _playBadge = [UIImageView new];
        _playBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _playBadge.contentMode = UIViewContentModeScaleAspectFit;
        _playBadge.image = [[UIImage imageNamed:@"ic_play"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        _playBadge.hidden = YES;
        [_thumbView addSubview:_playBadge];

        _nameLabel = [UILabel new];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = ASFontS(15, UIFontWeightSemibold);
        _nameLabel.textColor = UIColor.blackColor;
        _nameLabel.numberOfLines = 1;
        [_card addSubview:_nameLabel];

        _metaLabel = [UILabel new];
        _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _metaLabel.font = ASFontS(15, UIFontWeightRegular);
        _metaLabel.textColor = [UIColor colorWithWhite:0 alpha:0.55];
        _metaLabel.numberOfLines = 1;
        [_card addSubview:_metaLabel];

        _dateLabel = [UILabel new];
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _dateLabel.font = ASFontS(13, UIFontWeightSemibold);
        _dateLabel.textColor = UIColor.blackColor;
        _dateLabel.numberOfLines = 1;
        [_card addSubview:_dateLabel];

        _deleteButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _deleteButton.translatesAutoresizingMaskIntoConstraints = NO;

        UIImage *delImg = [[UIImage imageNamed:@"ic_delete_studio"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [_deleteButton setImage:delImg forState:UIControlStateNormal];

        _deleteButton.contentEdgeInsets = ASEdgeInsets(10, 10, 10, 10);
        _deleteButton.imageView.contentMode = UIViewContentModeScaleAspectFit;

        [_card addSubview:_deleteButton];

        [NSLayoutConstraint activateConstraints:@[
            [_thumbView.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:AS(10)],
            [_thumbView.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor],
            [_thumbView.widthAnchor constraintEqualToConstant:AS(80)],
            [_thumbView.heightAnchor constraintEqualToConstant:AS(80)],

            [_playBadge.leadingAnchor constraintEqualToAnchor:_thumbView.leadingAnchor constant:AS(6)],
            [_playBadge.topAnchor constraintEqualToAnchor:_thumbView.topAnchor constant:AS(6)],
            [_playBadge.widthAnchor constraintEqualToConstant:AS(16)],
            [_playBadge.heightAnchor constraintEqualToConstant:AS(16)],

            [_deleteButton.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-AS(20)],
            [_deleteButton.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor],
            [_deleteButton.widthAnchor constraintEqualToConstant:AS(44)],
            [_deleteButton.heightAnchor constraintEqualToConstant:AS(44)],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_thumbView.trailingAnchor constant:AS(12)],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_deleteButton.leadingAnchor constant:-AS(10)],
            [_nameLabel.topAnchor constraintEqualToAnchor:_thumbView.topAnchor constant:AS(2)],

            [_metaLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_metaLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_deleteButton.leadingAnchor constant:-AS(10)],
            [_metaLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:AS(6)],

            [_dateLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_dateLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_deleteButton.leadingAnchor constant:-AS(10)],
            [_dateLabel.bottomAnchor constraintEqualToAnchor:_thumbView.bottomAnchor constant:-AS(2)],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.thumbView.image = nil;
    self.playBadge.hidden = YES;
    self.nameLabel.text = @"";
    self.metaLabel.text = @"";
    self.dateLabel.text = @"";
}

- (void)showVideoBadge:(BOOL)show {
    self.playBadge.hidden = !show;
}

@end
