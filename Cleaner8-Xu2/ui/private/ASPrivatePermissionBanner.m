#import "ASPrivatePermissionBanner.h"
#import "ASColors.h"

@implementation ASPrivatePermissionBanner {
    UILabel *_title;
    UIButton *_btn;
    UIImageView *_arrow;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.whiteColor;
        self.layer.cornerRadius = 16;
        self.layer.masksToBounds = YES;

        _title = [UILabel new];
        _title.translatesAutoresizingMaskIntoConstraints = NO;
        _title.text = @"Full Photo Access Required";
        _title.textColor = UIColor.blackColor;
        _title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        _title.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_title];

        _btn = [UIButton buttonWithType:UIButtonTypeCustom];
        _btn.translatesAutoresizingMaskIntoConstraints = NO;
        _btn.backgroundColor = ASBlue();
        _btn.layer.cornerRadius = 25;
        _btn.layer.masksToBounds = YES;
        [_btn addTarget:self action:@selector(go) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_btn];

        UILabel *t = [UILabel new];
        t.translatesAutoresizingMaskIntoConstraints = NO;
        t.text = @"Go to Settings";
        t.textColor = UIColor.whiteColor;
        t.font = [UIFont systemFontOfSize:20 weight:UIFontWeightMedium];
        [_btn addSubview:t];

        _arrow = [UIImageView new];
        _arrow.translatesAutoresizingMaskIntoConstraints = NO;
        _arrow.contentMode = UIViewContentModeScaleAspectFit;
        _arrow.image = [[UIImage imageNamed:@"ic_todo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [_btn addSubview:_arrow];
        
        [NSLayoutConstraint activateConstraints:@[
            [_title.topAnchor constraintEqualToAnchor:self.topAnchor constant:27],
            [_title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [_title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],

            [_btn.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-27],
            [_btn.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

            [_btn.heightAnchor constraintGreaterThanOrEqualToConstant:50],

            [t.leadingAnchor constraintEqualToAnchor:_btn.leadingAnchor constant:32],
            [t.topAnchor constraintEqualToAnchor:_btn.topAnchor constant:10],
            [t.bottomAnchor constraintEqualToAnchor:_btn.bottomAnchor constant:-10],
            [t.centerYAnchor constraintEqualToAnchor:_btn.centerYAnchor],

            [_arrow.leadingAnchor constraintEqualToAnchor:t.trailingAnchor constant:10],
            [_arrow.centerYAnchor constraintEqualToAnchor:_btn.centerYAnchor],
            [_arrow.widthAnchor constraintEqualToConstant:9],
            [_arrow.heightAnchor constraintEqualToConstant:15],
            [_arrow.trailingAnchor constraintEqualToAnchor:_btn.trailingAnchor constant:-32],
        ]];

    }
    return self;
}

- (void)go {
    if (self.onGoSettings) self.onGoSettings();
}

@end
