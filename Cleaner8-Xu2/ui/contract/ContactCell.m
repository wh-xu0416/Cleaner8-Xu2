#import "ContactCell.h"

@implementation ContactCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = [UIColor whiteColor];
        self.contentView.layer.cornerRadius = 10;
        self.contentView.clipsToBounds = YES;
        
        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.font = [UIFont boldSystemFontOfSize:16];
        self.nameLabel.textColor = [UIColor blackColor];
        [self.contentView addSubview:self.nameLabel];
        
        self.phoneLabel = [[UILabel alloc] init];
        self.phoneLabel.font = [UIFont systemFontOfSize:14];
        self.phoneLabel.textColor = [UIColor darkGrayColor];
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
    
    CGFloat padding = 10;
    
    self.nameLabel.frame = CGRectMake(padding, padding, self.contentView.bounds.size.width - 80, 20);
    
    self.phoneLabel.frame = CGRectMake(padding, CGRectGetMaxY(self.nameLabel.frame) + 5, self.contentView.bounds.size.width - 80, 20);
    
    self.checkButton.frame = CGRectMake(self.contentView.bounds.size.width - 40, (self.contentView.bounds.size.height - 30) / 2, 30, 30);
}

- (void)selectButtonTapped {
    if (self.onSelect) {
        self.onSelect();
    }
}

@end
