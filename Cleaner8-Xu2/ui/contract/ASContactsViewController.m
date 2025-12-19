#import "ASContactsViewController.h"
#import "ASCustomNavBar.h"

@interface ASContactsViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) ASCustomNavBar *navBar;  // 自定义导航栏
@end

@implementation ASContactsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = UIColor.whiteColor;
    
    // 设置自定义导航栏
    [self setupNavBar];
    
    // 设置其他UI（例如：collection view）
    [self setupUI];
}

- (void)setupNavBar {
    // 创建自定义导航栏并设置标题
    self.navBar = [[ASCustomNavBar alloc] initWithTitle:@"联系人"];
    
    __weak typeof(self) weakSelf = self;
    self.navBar.onBack = ^{
        // 处理返回按钮的点击事件
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };
    
    // 不显示全选按钮
    [self.navBar setShowRightButton:NO];

    // 将导航栏添加到视图中
    [self.view addSubview:self.navBar];
}

- (void)setupUI {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 8;
    layout.sectionInset = UIEdgeInsetsMake(0, 12, 0, 12);

    self.cv = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.cv.backgroundColor = UIColor.whiteColor;
    self.cv.dataSource = self;
    self.cv.delegate = self;
    [self.view addSubview:self.cv];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return 0; // 实现来显示联系人
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    // 实现联系人信息的显示
    return nil;
}

// 调整布局，确保导航栏和底部栏不会遮挡内容
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat navH = 44 + self.view.safeAreaInsets.top;  // 考虑安全区
    self.navBar.frame = CGRectMake(0, 0, self.view.bounds.size.width, navH);

    // 调整 collection view 的布局
    self.cv.frame = CGRectMake(0, navH, self.view.bounds.size.width, self.view.bounds.size.height - navH);
}

@end
