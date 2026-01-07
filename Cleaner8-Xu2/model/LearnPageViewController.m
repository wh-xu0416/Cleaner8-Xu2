#import "LearnPageViewController.h"

#pragma mark - Cell (one page = one big image centered)

@interface LearnBigImageCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imgView;
@end

@implementation LearnBigImageCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;

        _imgView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _imgView.translatesAutoresizingMaskIntoConstraints = NO;
        _imgView.contentMode = UIViewContentModeScaleAspectFit;
        _imgView.clipsToBounds = YES;
        [self.contentView addSubview:_imgView];

        // 目标尺寸 402x402；小屏幕时允许自动缩小（优先级 999）
        NSLayoutConstraint *w = [_imgView.widthAnchor constraintEqualToConstant:402];
        w.priority = 999;
        NSLayoutConstraint *h = [_imgView.heightAnchor constraintEqualToConstant:402];
        h.priority = 999;

        [NSLayoutConstraint activateConstraints:@[
            [_imgView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_imgView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

            w, h,
            // 防止小屏溢出
            [_imgView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:15],
            [_imgView.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-15],
            [_imgView.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor],
            [_imgView.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.imgView.image = nil;
}

@end

#pragma mark - VC

@interface LearnPageViewController () <UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate>
@property (nonatomic, strong) UIImageView *bgImageView;
@property (nonatomic, strong) UIView *descContainer;

@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *backButton;

@property (nonatomic, strong) UIImageView *qpImageView;
@property (nonatomic, strong) UIImageView *bookImageView;

@property (nonatomic, strong) UILabel *titleLabel;        // 浮在 ic_qp 中心
@property (nonatomic, strong) UILabel *descriptionLabel;  // 说明文字（居中）

@property (nonatomic, strong) UICollectionView *collectionView; // 一屏一张，分页滑动
@property (nonatomic, strong) UIButton *nextButton;              // 底部贴边（不留底部距离）

@property (nonatomic, strong) NSArray<NSString *> *instructions;
@property (nonatomic, strong) NSArray<NSString *> *imageNames;
@property (nonatomic, assign) NSInteger currentIndex;
@end

@implementation LearnPageViewController

static NSString * const kCellId = @"LearnBigImageCell";

- (instancetype)init {
    if ((self = [super init])) {
        _instructions = @[
            @"1、Open The “Photos\" APP",
            @"2、Open The “Photos\" APP",
            @"3、Tap the \"Select\" button in the upper right corner",
            @"4、Click the \"Delete All\" Button on the Top Right Corner",
            @"5、Next, tap the\n\"Delete From All Devices\" Button"
        ];
        _imageNames = @[@"ic_learn_1", @"ic_learn_2", @"ic_learn_3", @"ic_learn_4", @"ic_learn_5"];
        _currentIndex = 0;
    }
    return self;
}

- (UIColor *)brandBlue {
    return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; // #024DFF
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.whiteColor;
    self.edgesForExtendedLayout = UIRectEdgeAll;

    [self buildUI];
    [self updateStepUIAnimated:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    // 让每一页宽度 = collectionView 的宽度，分页丝滑对齐
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout;
    CGSize size = self.collectionView.bounds.size;
    if (!CGSizeEqualToSize(layout.itemSize, size)) {
        layout.itemSize = size;
        layout.minimumLineSpacing = 0;
        layout.sectionInset = UIEdgeInsetsZero;
        [layout invalidateLayout];
    }
}

#pragma mark - UI

- (void)buildUI {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    // 全屏背景（延伸到状态栏 & 底部导航区域）
    self.bgImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_learn_bg"]];
    self.bgImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.bgImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.bgImageView.clipsToBounds = YES;
    [self.view addSubview:self.bgImageView];

    // TopBar（只放返回按钮；背景继续延伸）
    self.topBar = [[UIView alloc] init];
    self.topBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.topBar.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.topBar];

    self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backButton setImage:[UIImage imageNamed:@"ic_back_blue"] forState:UIControlStateNormal];
    [self.backButton addTarget:self action:@selector(onBack) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.backButton];

    // ic_qp 居中（342x115）
    self.qpImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_qp"]];
    self.qpImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.qpImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.qpImageView.userInteractionEnabled = YES;
    [self.view addSubview:self.qpImageView];

    // ic_book 右上角，往上偏移（不再往下）
    self.bookImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_book"]];
    self.bookImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.bookImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.view addSubview:self.bookImageView];

    // 标题文字浮在 ic_qp 中心
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = @"How to empty\n\"Recently Deleted\" album?";
    self.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = UIColor.blackColor;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 2;
    [self.qpImageView addSubview:self.titleLabel];

    self.descContainer = [[UIView alloc] init];
    self.descContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.descContainer.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.descContainer];

    // 说明文字（最多两行，居中显示在容器内）
    self.descriptionLabel = [[UILabel alloc] init];
    self.descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.descriptionLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    self.descriptionLabel.textColor = [self brandBlue];
    self.descriptionLabel.textAlignment = NSTextAlignmentCenter;
    self.descriptionLabel.numberOfLines = 2;
    self.descriptionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    // 关键：不要让 label “撑开”容器
    [self.descriptionLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];

    [self.descContainer addSubview:self.descriptionLabel];
    
    // 下方大图：一屏一张，分页左右滑（每张目标 402x402）
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.minimumLineSpacing = 0;

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = UIColor.clearColor;
    self.collectionView.showsHorizontalScrollIndicator = NO;
    self.collectionView.pagingEnabled = YES;
    self.collectionView.decelerationRate = UIScrollViewDecelerationRateFast;
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    [self.collectionView registerClass:LearnBigImageCell.class forCellWithReuseIdentifier:kCellId];
    [self.view addSubview:self.collectionView];

    // 底部按钮：不留底部距离
    self.nextButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.nextButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.nextButton setTitle:@"Next" forState:UIControlStateNormal];
    self.nextButton.backgroundColor = [self brandBlue];
    self.nextButton.layer.cornerRadius = 35;
    self.nextButton.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
    [self.nextButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.nextButton addTarget:self action:@selector(onNext) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.nextButton];
    CGFloat twoLinesHeight = ceil(self.descriptionLabel.font.lineHeight * 2.0);

    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        // BG full screen
        [self.bgImageView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.bgImageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bgImageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bgImageView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        // TopBar
        [self.topBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.topBar.heightAnchor constraintEqualToConstant:44],

        [self.backButton.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor constant:20],
        [self.backButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.backButton.widthAnchor constraintEqualToConstant:24],
        [self.backButton.heightAnchor constraintEqualToConstant:24],

        // ic_qp centered horizontally
        [self.qpImageView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.qpImageView.topAnchor constraintEqualToAnchor:safe.topAnchor constant:60],
        [self.qpImageView.widthAnchor constraintEqualToConstant:342],
        [self.qpImageView.heightAnchor constraintEqualToConstant:115],

        // title floats in qp center
        [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.qpImageView.centerXAnchor constant:-20],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.qpImageView.centerYAnchor constant:-10],
        [self.titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.qpImageView.leadingAnchor constant:12],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.qpImageView.trailingAnchor constant:-12],

        // book top-right and shifted UP
        [self.bookImageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-39],
        [self.bookImageView.topAnchor constraintEqualToAnchor:self.qpImageView.topAnchor constant:-30], // 往上偏移
        [self.bookImageView.widthAnchor constraintEqualToConstant:88],
        [self.bookImageView.heightAnchor constraintEqualToConstant:73],

        // Next button bottom = 0 (no spacing)
        [self.nextButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [self.nextButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.nextButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.nextButton.heightAnchor constraintEqualToConstant:70],

        [self.descContainer.topAnchor constraintEqualToAnchor:self.qpImageView.bottomAnchor constant:25],
        [self.descContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.descContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.descContainer.heightAnchor constraintEqualToConstant:twoLinesHeight],
        [self.descriptionLabel.leadingAnchor constraintEqualToAnchor:self.descContainer.leadingAnchor],
        [self.descriptionLabel.trailingAnchor constraintEqualToAnchor:self.descContainer.trailingAnchor],
        [self.descriptionLabel.centerYAnchor constraintEqualToAnchor:self.descContainer.centerYAnchor],

        // collection view between desc and button
        [self.collectionView.topAnchor constraintEqualToAnchor:self.descContainer.bottomAnchor constant:15],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.nextButton.topAnchor constant:-10],
    ]];
}

#pragma mark - Actions

- (void)onBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)onNext {
    NSInteger next = self.currentIndex + 1;
    if (next >= self.instructions.count) next = 0;
    self.currentIndex = next;
    [self updateStepUIAnimated:YES];
}

- (void)updateStepUIAnimated:(BOOL)animated {
    // 文案切换
    self.descriptionLabel.text = self.instructions[self.currentIndex];

    // 翻页到对应大图
    if (self.currentIndex < self.imageNames.count) {
        NSIndexPath *idx = [NSIndexPath indexPathForItem:self.currentIndex inSection:0];
        [self.collectionView scrollToItemAtIndexPath:idx
                                    atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                            animated:animated];
    }
}

#pragma mark - UICollectionView

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.imageNames.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    LearnBigImageCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kCellId forIndexPath:indexPath];
    cell.imgView.image = [UIImage imageNamed:self.imageNames[indexPath.item]];
    return cell;
}

#pragma mark - UIScrollViewDelegate (手势滑动后同步文案/索引)

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView != self.collectionView) return;

    CGFloat pageW = scrollView.bounds.size.width;
    if (pageW <= 0) return;

    NSInteger page = (NSInteger)llround(scrollView.contentOffset.x / pageW);
    page = MAX(0, MIN(page, (NSInteger)self.instructions.count - 1));

    if (page != self.currentIndex) {
        self.currentIndex = page;
        self.descriptionLabel.text = self.instructions[self.currentIndex];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (scrollView != self.collectionView) return;
    if (decelerate) return;

    CGFloat pageW = scrollView.bounds.size.width;
    if (pageW <= 0) return;

    NSInteger page = (NSInteger)llround(scrollView.contentOffset.x / pageW);
    page = MAX(0, MIN(page, (NSInteger)self.instructions.count - 1));

    if (page != self.currentIndex) {
        self.currentIndex = page;
        self.descriptionLabel.text = self.instructions[self.currentIndex];
    }
}

@end
