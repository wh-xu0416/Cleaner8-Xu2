#import "VideoCompressionResultViewController.h"
#import "ASCustomNavBar.h"
#import <Photos/Photos.h>

static NSString *ASHumanSize(uint64_t bytes) {
    double b = (double)bytes;
    if (b < 1024) return [NSString stringWithFormat:@"%.0f B", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f KB", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f MB", b];
    b /= 1024; return [NSString stringWithFormat:@"%.2f GB", b];
}

@interface VideoCompressionResultViewController ()
@property (nonatomic, strong) ASCustomNavBar *nav;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UILabel *dataLabel;

@property (nonatomic, strong) UIButton *studioButton;
@property (nonatomic, strong) UIButton *homeButton;

@property (nonatomic, strong) ASCompressionSummary *summary;
@end

@implementation VideoCompressionResultViewController

- (instancetype)initWithSummary:(ASCompressionSummary *)summary {
    if (self = [super init]) {
        _summary = summary;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.navigationController.navigationBarHidden = YES;

    [self buildUI];
    [self fillData];

    [self askDeleteOriginal];
}

- (void)buildUI {
    self.nav = [[ASCustomNavBar alloc] initWithTitle:@"Result"];
    __weak typeof(self) weakSelf = self;
    self.nav.onBack = ^{ [weakSelf.navigationController popToRootViewControllerAnimated:YES]; };
    [self.view addSubview:self.nav];
    self.nav.translatesAutoresizingMaskIntoConstraints = NO;

    self.titleLabel = [UILabel new];
    self.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.text = @"Compression Complete";

    self.infoLabel = [UILabel new];
    self.infoLabel.font = [UIFont systemFontOfSize:14];
    self.infoLabel.textColor = [UIColor colorWithWhite:0.25 alpha:1];
    self.infoLabel.numberOfLines = 0;
    self.infoLabel.textAlignment = NSTextAlignmentCenter;

    self.dataLabel = [UILabel new];
    self.dataLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.dataLabel.numberOfLines = 0;
    self.dataLabel.textAlignment = NSTextAlignmentCenter;

    self.studioButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.studioButton setTitle:@"My Studio" forState:UIControlStateNormal];
    self.studioButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.studioButton.backgroundColor = UIColor.blackColor;
    [self.studioButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.studioButton.layer.cornerRadius = 12;
    [self.studioButton addTarget:self action:@selector(onStudio) forControlEvents:UIControlEventTouchUpInside];

    self.homeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.homeButton setTitle:@"Home" forState:UIControlStateNormal];
    self.homeButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.homeButton.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1];
    [self.homeButton setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    self.homeButton.layer.cornerRadius = 12;
    [self.homeButton addTarget:self action:@selector(onHome) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:self.titleLabel];
    [self.view addSubview:self.infoLabel];
    [self.view addSubview:self.dataLabel];
    [self.view addSubview:self.studioButton];
    [self.view addSubview:self.homeButton];

    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.dataLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.studioButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.homeButton.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.nav.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.nav.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.nav.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.nav.heightAnchor constraintEqualToConstant:56],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.nav.bottomAnchor constant:24],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.infoLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:10],
        [self.infoLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.infoLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.dataLabel.topAnchor constraintEqualToAnchor:self.infoLabel.bottomAnchor constant:18],
        [self.dataLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.dataLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.studioButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [self.studioButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.studioButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.studioButton.heightAnchor constraintEqualToConstant:52],

        [self.homeButton.bottomAnchor constraintEqualToAnchor:self.studioButton.topAnchor constant:-10],
        [self.homeButton.leadingAnchor constraintEqualToAnchor:self.studioButton.leadingAnchor],
        [self.homeButton.trailingAnchor constraintEqualToAnchor:self.studioButton.trailingAnchor],
        [self.homeButton.heightAnchor constraintEqualToConstant:52],
    ]];
}

- (void)fillData {
    NSInteger count = self.summary.items.count;
    self.infoLabel.text = [NSString stringWithFormat:@"%ld videos have been compressed and saved to your system album", (long)count];

    NSString *before = ASHumanSize(self.summary.totalBeforeBytes);
    NSString *after  = ASHumanSize(self.summary.totalAfterBytes);
    NSString *saved  = ASHumanSize(self.summary.totalSavedBytes);

    self.dataLabel.text = [NSString stringWithFormat:@"Before: %@\nAfter: %@\nSpace Saved: %@", before, after, saved];
}

- (void)askDeleteOriginal {
    if (self.summary.items.count == 0) return;

    UIAlertController *ac =
    [UIAlertController alertControllerWithTitle:@"Delete original video?"
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];

    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Keep" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {

        NSMutableArray<PHAsset *> *toDelete = [NSMutableArray array];
        for (ASCompressionItemResult *it in weakSelf.summary.items) {
            if (it.originalAsset) [toDelete addObject:it.originalAsset];
        }
        if (toDelete.count == 0) return;

        [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
            [PHAssetChangeRequest deleteAssets:toDelete];
        } completionHandler:^(BOOL success, NSError * _Nullable error) {
            // 可选：你可以提示 toast
        }];
    }]];

    [self presentViewController:ac animated:YES completion:nil];
}

- (void)onStudio {
    // TODO: push MyStudio page
    // [self.navigationController pushViewController:[MyStudioViewController new] animated:YES];
}

- (void)onHome {
    [self.navigationController popToRootViewControllerAnimated:YES];
}

@end
