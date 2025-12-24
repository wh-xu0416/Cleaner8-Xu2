// ContactCell.m
#import "ContactCell.h"

@implementation ContactCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // 初始化视图
        self.contentView.backgroundColor = [UIColor whiteColor];
        self.contentView.layer.cornerRadius = 10;
        self.contentView.clipsToBounds = YES;
        
        // 创建姓名标签
        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.font = [UIFont boldSystemFontOfSize:16];
        self.nameLabel.textColor = [UIColor blackColor];
        [self.contentView addSubview:self.nameLabel];
        
        // 创建电话标签
        self.phoneLabel = [[UILabel alloc] init];
        self.phoneLabel.font = [UIFont systemFontOfSize:14];
        self.phoneLabel.textColor = [UIColor darkGrayColor];
        [self.contentView addSubview:self.phoneLabel];
        
        // 创建选择按钮
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
    
    // 设置姓名标签布局
    self.nameLabel.frame = CGRectMake(padding, padding, self.contentView.bounds.size.width - 80, 20);
    
    // 设置电话标签布局
    self.phoneLabel.frame = CGRectMake(padding, CGRectGetMaxY(self.nameLabel.frame) + 5, self.contentView.bounds.size.width - 80, 20);
    
    // 设置选择按钮布局
    self.checkButton.frame = CGRectMake(self.contentView.bounds.size.width - 40, (self.contentView.bounds.size.height - 30) / 2, 30, 30);
}

- (void)selectButtonTapped {
    // 点击选择按钮时调用 onSelect 回调
    if (self.onSelect) {
        self.onSelect();
    }
}

@end
