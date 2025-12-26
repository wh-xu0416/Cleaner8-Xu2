#import "VideoCompressionQualityViewController.h"
#import "ASCustomNavBar.h"
#import <AVKit/AVKit.h>
#import <Photos/Photos.h>
#import "VideoCompressionManager.h"
#import "VideoCompressionProgressViewController.h"

static uint64_t ASAssetFileSize(PHAsset *asset) {
    PHAssetResource *r = [PHAssetResource assetResourcesForAsset:asset].firstObject;
    if (!r) return 0;
    NSNumber *n = nil;
    @try { n = [r valueForKey:@"fileSize"]; } @catch (__unused NSException *e) { n = nil; }
    return n.unsignedLongLongValue;
}

static NSString *ASHumanSize(uint64_t bytes) {
    double b = (double)bytes;
    if (b < 1024) return [NSString stringWithFormat:@"%.0f B", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f KB", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f MB", b];
    b /= 1024; return [NSString stringWithFormat:@"%.2f GB", b];
}

static NSString *ASMB1(uint64_t bytes) {
    double mb = (double)bytes / (1024.0 * 1024.0);
    return [NSString stringWithFormat:@"%.1fMB", mb];
}

static NSString *ASDurationText(NSTimeInterval duration) {
    NSInteger d = (NSInteger)llround(duration);
    NSInteger m = d / 60, s = d % 60;
    if (m >= 60) { NSInteger h = m/60; m%=60; return [NSString stringWithFormat:@"%ld:%02ld:%02ld",(long)h,(long)m,(long)s]; }
    return [NSString stringWithFormat:@"%ld:%02ld",(long)m,(long)s];
}

/// ✅ 预估压缩后比例：必须和 VideoCompressionManager 的 remainRatio 一致
/// Small: save 80% => remain 0.20
/// Medium: save 50% => remain 0.50
/// Large: save 20% => remain 0.80
static double ASRatioForQuality(ASCompressionQuality q) {
    switch (q) {
        case ASCompressionQualitySmall:  return 0.20;
        case ASCompressionQualityMedium: return 0.50;
        case ASCompressionQualityLarge:  return 0.80;
    }
}

@interface VideoCompressionQualityViewController ()
@property (nonatomic, strong) ASCustomNavBar *nav;
@property (nonatomic, strong) NSArray<PHAsset *> *assets;

@property (nonatomic, strong) UILabel *selectedLabel;

@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UIButton *playButton;

@property (nonatomic, strong) UILabel *infoLabel;        // Size/Duration/Resolution
@property (nonatomic, strong) UILabel *previewLabel;     // before -> after
@property (nonatomic, strong) UILabel *saveLabel;        // You will save about XXMB

@property (nonatomic, strong) UISegmentedControl *qualitySeg;
@property (nonatomic, strong) UIButton *compressButton;

@property (nonatomic) ASCompressionQuality quality;
@property (nonatomic) uint64_t totalBeforeBytes;
@end

@implementation VideoCompressionQualityViewController

- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets {
    if (self = [super init]) {
        _assets = assets ?: @[];
        _quality = ASCompressionQualityMedium; // 默认 Medium（save 50%）
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.navigationController.navigationBarHidden = YES;

    [self buildUI];
    [self loadTopInfo];
    [self loadThumbForFirst];
    [self refreshPreview];
}

- (void)buildUI {
    self.nav = [[ASCustomNavBar alloc] initWithTitle:@"Compression Quality"];
    __weak typeof(self) weakSelf = self;
    self.nav.onBack = ^{ [weakSelf.navigationController popViewControllerAnimated:YES]; };
    [self.view addSubview:self.nav];
    self.nav.translatesAutoresizingMaskIntoConstraints = NO;

    self.selectedLabel = [UILabel new];
    self.selectedLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];

    self.thumbView = [UIImageView new];
    self.thumbView.layer.cornerRadius = 12;
    self.thumbView.layer.masksToBounds = YES;
    self.thumbView.contentMode = UIViewContentModeScaleAspectFill;
    self.thumbView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1];

    self.playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.playButton setTitle:@"Play" forState:UIControlStateNormal];
    self.playButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.playButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    [self.playButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.playButton.layer.cornerRadius = 18;
    [self.playButton addTarget:self action:@selector(onPlay) forControlEvents:UIControlEventTouchUpInside];

    self.infoLabel = [UILabel new];
    self.infoLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    self.infoLabel.numberOfLines = 0;

    self.previewLabel = [UILabel new];
    self.previewLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];

    self.saveLabel = [UILabel new];
    self.saveLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    self.saveLabel.textColor = [UIColor colorWithWhite:0.2 alpha:1];

    self.qualitySeg = [[UISegmentedControl alloc] initWithItems:@[@"Small", @"Medium", @"Large"]];
    self.qualitySeg.selectedSegmentIndex = 1; // Medium
    [self.qualitySeg addTarget:self action:@selector(onQualityChanged:) forControlEvents:UIControlEventValueChanged];

    self.compressButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.compressButton setTitle:@"Compress" forState:UIControlStateNormal];
    self.compressButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.compressButton.backgroundColor = [UIColor blackColor];
    [self.compressButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.compressButton.layer.cornerRadius = 12;
    [self.compressButton addTarget:self action:@selector(onCompress) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:self.selectedLabel];
    [self.view addSubview:self.thumbView];
    [self.view addSubview:self.playButton];
    [self.view addSubview:self.infoLabel];
    [self.view addSubview:self.previewLabel];
    [self.view addSubview:self.saveLabel];
    [self.view addSubview:self.qualitySeg];
    [self.view addSubview:self.compressButton];

    self.selectedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.thumbView.translatesAutoresizingMaskIntoConstraints = NO;
    self.playButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.saveLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.qualitySeg.translatesAutoresizingMaskIntoConstraints = NO;
    self.compressButton.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.nav.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.nav.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.nav.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.nav.heightAnchor constraintEqualToConstant:56],

        [self.selectedLabel.topAnchor constraintEqualToAnchor:self.nav.bottomAnchor constant:16],
        [self.selectedLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.selectedLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.thumbView.topAnchor constraintEqualToAnchor:self.selectedLabel.bottomAnchor constant:16],
        [self.thumbView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.thumbView.widthAnchor constraintEqualToConstant:140],
        [self.thumbView.heightAnchor constraintEqualToConstant:140],

        [self.playButton.centerXAnchor constraintEqualToAnchor:self.thumbView.centerXAnchor],
        [self.playButton.centerYAnchor constraintEqualToAnchor:self.thumbView.centerYAnchor],
        [self.playButton.widthAnchor constraintEqualToConstant:72],
        [self.playButton.heightAnchor constraintEqualToConstant:36],

        [self.infoLabel.topAnchor constraintEqualToAnchor:self.thumbView.topAnchor],
        [self.infoLabel.leadingAnchor constraintEqualToAnchor:self.thumbView.trailingAnchor constant:14],
        [self.infoLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.previewLabel.topAnchor constraintEqualToAnchor:self.thumbView.bottomAnchor constant:18],
        [self.previewLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.previewLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.saveLabel.topAnchor constraintEqualToAnchor:self.previewLabel.bottomAnchor constant:8],
        [self.saveLabel.leadingAnchor constraintEqualToAnchor:self.previewLabel.leadingAnchor],
        [self.saveLabel.trailingAnchor constraintEqualToAnchor:self.previewLabel.trailingAnchor],

        [self.qualitySeg.topAnchor constraintEqualToAnchor:self.saveLabel.bottomAnchor constant:18],
        [self.qualitySeg.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.qualitySeg.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.compressButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [self.compressButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.compressButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.compressButton.heightAnchor constraintEqualToConstant:52],
    ]];
}

- (void)loadTopInfo {
    NSInteger count = self.assets.count;
    self.selectedLabel.text = [NSString stringWithFormat:@"%ld video selected", (long)count];

    uint64_t total = 0;
    for (PHAsset *a in self.assets) {
        total += ASAssetFileSize(a);
    }
    self.totalBeforeBytes = total;

    // 右侧信息：展示第一条
    PHAsset *first = self.assets.firstObject;
    if (!first) return;

    uint64_t b = ASAssetFileSize(first);
    NSString *size = (b > 0) ? ASHumanSize(b) : @"--";
    NSString *dur = ASDurationText(first.duration);
    NSString *res = [NSString stringWithFormat:@"%ld×%ld", (long)first.pixelWidth, (long)first.pixelHeight];

    self.infoLabel.text = [NSString stringWithFormat:@"Size: %@\nDuration: %@\nResolution: %@", size, dur, res];
}

- (void)loadThumbForFirst {
    PHAsset *first = self.assets.firstObject;
    if (!first) return;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.resizeMode = PHImageRequestOptionsResizeModeExact;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;

    CGSize target = CGSizeMake(600, 600);
    [[PHImageManager defaultManager] requestImageForAsset:first
                                              targetSize:target
                                             contentMode:PHImageContentModeAspectFill
                                                 options:opt
                                           resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (result) self.thumbView.image = result;
    }];
}

- (void)refreshPreview {
    double ratio = ASRatioForQuality(self.quality);          // ✅ 和 manager 一致
    uint64_t after = (uint64_t)llround((double)self.totalBeforeBytes * ratio);
    uint64_t saved = (self.totalBeforeBytes > after) ? (self.totalBeforeBytes - after) : 0;

    self.previewLabel.text = [NSString stringWithFormat:@"%@ → %@", ASMB1(self.totalBeforeBytes), ASMB1(after)];
    self.saveLabel.text = [NSString stringWithFormat:@"You will save about %@", ASMB1(saved)];
}

- (void)onQualityChanged:(UISegmentedControl *)seg {
    if (seg.selectedSegmentIndex == 0) self.quality = ASCompressionQualitySmall;
    else if (seg.selectedSegmentIndex == 1) self.quality = ASCompressionQualityMedium;
    else self.quality = ASCompressionQualityLarge;

    [self refreshPreview];
}

- (void)onPlay {
    PHAsset *first = self.assets.firstObject;
    if (!first) return;

    PHVideoRequestOptions *opt = [PHVideoRequestOptions new];
    opt.networkAccessAllowed = YES;

    __weak typeof(self) weakSelf = self;
    [[PHImageManager defaultManager] requestAVAssetForVideo:first options:opt resultHandler:^(AVAsset * _Nullable avAsset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
        if (!avAsset) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:avAsset];
            AVPlayerViewController *pvc = [AVPlayerViewController new];
            pvc.player = [AVPlayer playerWithPlayerItem:item];
            [weakSelf presentViewController:pvc animated:YES completion:^{
                [pvc.player play];
            }];
        });
    }];
}

- (void)onCompress {
    VideoCompressionProgressViewController *vc =
    [[VideoCompressionProgressViewController alloc] initWithAssets:self.assets quality:self.quality];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
