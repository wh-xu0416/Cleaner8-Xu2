#import "VideoCompressionProgressViewController.h"
#import "ASCustomNavBar.h"
#import <Photos/Photos.h>
#import "VideoCompressionResultViewController.h"

@interface VideoCompressionProgressViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, weak) id<UIGestureRecognizerDelegate> popDelegateBackup;

@property (nonatomic, strong) ASCustomNavBar *nav;

@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UILabel *percentLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *tipLabel;

@property (nonatomic, strong) NSArray<PHAsset *> *assets;
@property (nonatomic) ASCompressionQuality quality;

@property (nonatomic, strong) VideoCompressionManager *manager;
@property (nonatomic) BOOL showingCancelAlert;
@end

@implementation VideoCompressionProgressViewController

- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets quality:(ASCompressionQuality)quality {
    if (self = [super init]) {
        _assets = assets ?: @[];
        _quality = quality;
        _showingCancelAlert = NO;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.navigationController.navigationBarHidden = YES;

    [self buildUI];
    [self loadThumb:self.assets.firstObject];
    [self startCompress];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    UIGestureRecognizer *pop = self.navigationController.interactivePopGestureRecognizer;
    if (!pop) return;

    // 备份系统原 delegate（只备份一次）
    if (!self.popDelegateBackup) self.popDelegateBackup = pop.delegate;

    pop.delegate = self;
    pop.enabled = YES;
}

- (void)resetPopGesture {
    UIGestureRecognizer *pop = self.navigationController.interactivePopGestureRecognizer;
    if (!pop) return;
    pop.enabled = NO;
    pop.enabled = YES;
    pop.delegate = self;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    UIGestureRecognizer *pop = self.navigationController.interactivePopGestureRecognizer;
    if (!pop) return;

    // 恢复原 delegate，避免影响后续页面
    if (pop.delegate == self) {
        pop.delegate = self.popDelegateBackup;
        pop.enabled = YES;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // ✅ 拦截侧滑返回
    if (self.navigationController.interactivePopGestureRecognizer) {
        self.navigationController.interactivePopGestureRecognizer.delegate = self;
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    }
}

- (void)dealloc {
    // 释放 delegate（防止影响别的页面）
    if (self.navigationController.interactivePopGestureRecognizer.delegate == self) {
        self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    // 只拦截系统侧滑返回手势
    if (gestureRecognizer == self.navigationController.interactivePopGestureRecognizer) {
        if (self.manager.isRunning) {
            // ✅ 阻止直接返回，改为弹确认
            dispatch_async(dispatch_get_main_queue(), ^{
                [self onCancelTapped];
            });
            return NO;
        }
    }
    return YES;
}

#pragma mark - UI

- (void)buildUI {
    self.nav = [[ASCustomNavBar alloc] initWithTitle:@"Converting"];
    __weak typeof(self) weakSelf = self;
    self.nav.onBack = ^{ [weakSelf onCancelTapped]; }; // ✅ titlebar 返回弹确认
    [self.view addSubview:self.nav];
    self.nav.translatesAutoresizingMaskIntoConstraints = NO;

    self.thumbView = [UIImageView new];
    self.thumbView.layer.cornerRadius = 12;
    self.thumbView.layer.masksToBounds = YES;
    self.thumbView.contentMode = UIViewContentModeScaleAspectFill;
    self.thumbView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1];

    self.percentLabel = [UILabel new];
    self.percentLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightSemibold];
    self.percentLabel.textAlignment = NSTextAlignmentCenter;
    self.percentLabel.text = @"0%";

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [self.spinner startAnimating];

    self.tipLabel = [UILabel new];
    self.tipLabel.font = [UIFont systemFontOfSize:14];
    self.tipLabel.textColor = [UIColor colorWithWhite:0.25 alpha:1];
    self.tipLabel.numberOfLines = 0;
    self.tipLabel.textAlignment = NSTextAlignmentCenter;
    self.tipLabel.text = @"It is recommended not to minimize or close the app...";

    [self.view addSubview:self.thumbView];
    [self.view addSubview:self.percentLabel];
    [self.view addSubview:self.spinner];
    [self.view addSubview:self.tipLabel];

    self.thumbView.translatesAutoresizingMaskIntoConstraints = NO;
    self.percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.tipLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.nav.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.nav.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.nav.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.nav.heightAnchor constraintEqualToConstant:56],

        [self.thumbView.topAnchor constraintEqualToAnchor:self.nav.bottomAnchor constant:30],
        [self.thumbView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.thumbView.widthAnchor constraintEqualToConstant:180],
        [self.thumbView.heightAnchor constraintEqualToConstant:180],

        [self.percentLabel.topAnchor constraintEqualToAnchor:self.thumbView.bottomAnchor constant:24],
        [self.percentLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.percentLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.spinner.topAnchor constraintEqualToAnchor:self.percentLabel.bottomAnchor constant:12],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.tipLabel.topAnchor constraintEqualToAnchor:self.spinner.bottomAnchor constant:16],
        [self.tipLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.tipLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];
}

- (void)loadThumb:(PHAsset *)asset {
    if (!asset) return;
    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    opt.resizeMode = PHImageRequestOptionsResizeModeExact;

    [[PHImageManager defaultManager] requestImageForAsset:asset
                                              targetSize:CGSizeMake(900, 900)
                                             contentMode:PHImageContentModeAspectFill
                                                 options:opt
                                           resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (result) self.thumbView.image = result;
    }];
}

#pragma mark - Compress

- (void)startCompress {
    self.manager = [VideoCompressionManager new];

    __weak typeof(self) weakSelf = self;
    [self.manager compressAssets:self.assets
                         quality:self.quality
                        progress:^(NSInteger currentIndex, NSInteger totalCount, float overallProgress, PHAsset *currentAsset) {

        if (currentAsset) [weakSelf loadThumb:currentAsset];

        int percent = (int)lrintf(overallProgress * 100.0f);
        percent = MAX(0, MIN(100, percent));
        weakSelf.percentLabel.text = [NSString stringWithFormat:@"%d%%", percent];

    } completion:^(ASCompressionSummary * _Nullable summary, NSError * _Nullable error) {

        if (error) {
            // cancel：直接返回
            if (error.code == -999) {
                [weakSelf.navigationController popViewControllerAnimated:YES];
                return;
            }

            // 其他错误：提示一下再返回
            UIAlertController *ac =
            [UIAlertController alertControllerWithTitle:@"Compress Failed"
                                                message:error.localizedDescription ?: @"Unknown error"
                                         preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [weakSelf.navigationController popViewControllerAnimated:YES];
            }]];
            [weakSelf presentViewController:ac animated:YES completion:nil];
            return;
        }

        VideoCompressionResultViewController *vc =
        [[VideoCompressionResultViewController alloc] initWithSummary:summary];
        [weakSelf.navigationController pushViewController:vc animated:YES];
    }];
}

#pragma mark - Cancel Confirm

- (void)onCancelTapped {
    if (!self.manager.isRunning) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    if (self.showingCancelAlert) return;
    self.showingCancelAlert = YES;

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Cancel Conversion"
                                                                message:@"Are you sure you want to cancel the conversion of this Video?"
                                                         preferredStyle:UIAlertControllerStyleAlert];

    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"NO" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        weakSelf.showingCancelAlert = NO;
        [weakSelf resetPopGesture];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"YES" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        weakSelf.showingCancelAlert = NO;
        [weakSelf.manager cancel];
        [weakSelf resetPopGesture];  
        [weakSelf.navigationController popViewControllerAnimated:YES];
    }]];

    [self presentViewController:ac animated:YES completion:nil];
}

@end
