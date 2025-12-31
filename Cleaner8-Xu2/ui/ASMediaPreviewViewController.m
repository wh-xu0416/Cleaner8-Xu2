#import "ASMediaPreviewViewController.h"
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

#pragma mark - Helpers

static inline UIColor *ASBlue(void) { return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; } // #024DFF
static inline UIColor *ASGray666(void) { return [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0]; } // #666666
static inline UIColor *ASBlack(void) { return [UIColor colorWithRed:0 green:0 blue:0 alpha:1.0]; }

static NSString *ASHumanSizeShort(uint64_t bytes) {
    double b = (double)bytes;
    double mb = b / (1024.0 * 1024.0);
    if (mb >= 1.0) return [NSString stringWithFormat:@"%.2fMB", mb];
    if (b >= 1024.0) return [NSString stringWithFormat:@"%.1fKB", b/1024.0];
    return [NSString stringWithFormat:@"%.0fB", b];
}

static uint64_t ASAssetTotalBytes(PHAsset *asset) {
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    if (resources.count == 0) return 0;

    BOOL isLive = (asset.mediaType == PHAssetMediaTypeImage) && ((asset.mediaSubtypes & PHAssetMediaSubtypePhotoLive) != 0);
    uint64_t sum = 0;

    for (PHAssetResource *r in resources) {
        BOOL need = NO;
        if (asset.mediaType == PHAssetMediaTypeVideo) {
            need = (r.type == PHAssetResourceTypeVideo) || (r.type == PHAssetResourceTypeFullSizeVideo);
        } else if (isLive) {
            need = (r.type == PHAssetResourceTypePhoto) ||
                   (r.type == PHAssetResourceTypeFullSizePhoto) ||
                   (r.type == PHAssetResourceTypePairedVideo);
        } else {
            need = (r.type == PHAssetResourceTypePhoto) || (r.type == PHAssetResourceTypeFullSizePhoto);
        }
        if (!need) continue;

        NSNumber *n = nil;
        @try { n = [r valueForKey:@"fileSize"]; } @catch (__unused NSException *e) { n = nil; }
        sum += n.unsignedLongLongValue;
    }
    return sum;
}

static UIImage *ASSelectOnImg(void) {
    UIImage *img = [UIImage imageNamed:@"ic_select_s"];
    if (img) return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    if (@available(iOS 13.0,*)) return [UIImage systemImageNamed:@"checkmark.circle.fill"];
    return nil;
}
static UIImage *ASSelectOffImg(void) {
    UIImage *img = [UIImage imageNamed:@"ic_select_n"];
    if (img) return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    if (@available(iOS 13.0,*)) return [UIImage systemImageNamed:@"circle"];
    return nil;
}

static UIImage *ASSelectGrayOffImg(void) {
    UIImage *img = [UIImage imageNamed:@"ic_select_gray_n"];
    if (img) return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    if (@available(iOS 13.0,*)) return [UIImage systemImageNamed:@"circle"];
    return nil;
}

#pragma mark - Best Badge（改成图片 ic_best）

@interface ASBestBadgeView : UIView
@property (nonatomic, copy) void(^onClose)(void);
@property (nonatomic, assign) BOOL showsClose;
- (instancetype)initWithBadgeSize:(CGSize)badgeSize;
@end

@interface ASBestBadgeView ()
@property (nonatomic, assign) CGSize badgeSize;
@property (nonatomic, strong) UIImageView *iv;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) NSLayoutConstraint *closeW;
@property (nonatomic, strong) NSLayoutConstraint *gapW;
@end

@implementation ASBestBadgeView

- (instancetype)initWithBadgeSize:(CGSize)badgeSize {
    if (self = [super initWithFrame:CGRectZero]) {
        _badgeSize = badgeSize;

        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = UIColor.clearColor;

        self.iv = [UIImageView new];
        self.iv.translatesAutoresizingMaskIntoConstraints = NO;
        UIImage *img = [UIImage imageNamed:@"ic_best"];
        if (img) img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        self.iv.image = img;
        self.iv.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:self.iv];

        self.closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
        if (@available(iOS 13.0,*)) {
            [self.closeBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        }
        self.closeBtn.tintColor = [UIColor blackColor];
        self.closeBtn.contentEdgeInsets = UIEdgeInsetsMake(4, 4, 4, 4);
        [self.closeBtn addTarget:self action:@selector(onCloseTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.closeBtn];

        self.gapW   = [self.closeBtn.leadingAnchor constraintEqualToAnchor:self.iv.trailingAnchor constant:0];
        self.closeW = [self.closeBtn.widthAnchor constraintEqualToConstant:0];

        [NSLayoutConstraint activateConstraints:@[
            [self.iv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.iv.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.iv.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.iv.widthAnchor constraintEqualToConstant:badgeSize.width],
            [self.iv.heightAnchor constraintEqualToConstant:badgeSize.height],

            self.gapW,
            [self.closeBtn.centerYAnchor constraintEqualToAnchor:self.iv.centerYAnchor],
            self.closeW,
            [self.closeBtn.heightAnchor constraintEqualToConstant:24],
            [self.closeBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];

        self.showsClose = NO;
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    CGFloat w = self.badgeSize.width + (self.showsClose ? (4 + 24) : 0);
    CGFloat h = MAX(self.badgeSize.height, (self.showsClose ? 24 : self.badgeSize.height));
    return CGSizeMake(w, h);
}

- (void)setShowsClose:(BOOL)showsClose {
    _showsClose = showsClose;
    self.closeBtn.hidden = !showsClose;
    self.closeW.constant = showsClose ? 24 : 0;
    self.gapW.constant   = showsClose ? 4 : 0;
    [self invalidateIntrinsicContentSize];
}

- (void)onCloseTap {
    if (self.onClose) self.onClose();
}

@end

#pragma mark - Preview Cells（Photo/Video/Live：沿用你之前版本，省略逻辑不变，只保留核心）

typedef NS_ENUM(NSInteger, ASPreviewKind) { ASPreviewKindPhoto, ASPreviewKindVideo, ASPreviewKindLive };

@interface ASPreviewBaseCell : UICollectionViewCell
@property (nonatomic, strong) PHAsset *asset;
@property (nonatomic, copy) NSString *representedId;
- (void)prepareForDisplay;
- (void)endDisplay;
@end
@implementation ASPreviewBaseCell
- (void)prepareForDisplay {}
- (void)endDisplay {}
@end

@interface ASPreviewPhotoCell : ASPreviewBaseCell <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *sv;
@property (nonatomic, strong) UIImageView *iv;
@property (nonatomic, strong) PHCachingImageManager *mgr;
@property (nonatomic, assign) PHImageRequestID rid;
@end

@implementation ASPreviewPhotoCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.mgr = [PHCachingImageManager new];
//        self.contentView.backgroundColor = UIColor.blackColor;

        self.sv = [UIScrollView new];
        self.sv.minimumZoomScale = 1.0;
        self.sv.maximumZoomScale = 3.0;
        self.sv.delegate = self;
        self.sv.showsHorizontalScrollIndicator = NO;
        self.sv.showsVerticalScrollIndicator = NO;
        self.sv.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.sv];

        self.iv = [UIImageView new];
        self.iv.contentMode = UIViewContentModeScaleAspectFit;
        self.iv.translatesAutoresizingMaskIntoConstraints = NO;
        [self.sv addSubview:self.iv];

        [NSLayoutConstraint activateConstraints:@[
            [self.sv.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.sv.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.sv.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.sv.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            [self.iv.leadingAnchor constraintEqualToAnchor:self.sv.contentLayoutGuide.leadingAnchor],
            [self.iv.trailingAnchor constraintEqualToAnchor:self.sv.contentLayoutGuide.trailingAnchor],
            [self.iv.topAnchor constraintEqualToAnchor:self.sv.contentLayoutGuide.topAnchor],
            [self.iv.bottomAnchor constraintEqualToAnchor:self.sv.contentLayoutGuide.bottomAnchor],
            [self.iv.widthAnchor constraintEqualToAnchor:self.sv.frameLayoutGuide.widthAnchor],
            [self.iv.heightAnchor constraintEqualToAnchor:self.sv.frameLayoutGuide.heightAnchor],
        ]];

        UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onDoubleTap:)];
        dbl.numberOfTapsRequired = 2;
        [self.contentView addGestureRecognizer:dbl];
    }
    return self;
}
- (void)prepareForReuse {
    [super prepareForReuse];
    self.asset = nil;
    self.representedId = nil;
    self.iv.image = nil;
    self.sv.zoomScale = 1.0;
    if (self.rid != PHInvalidImageRequestID) [self.mgr cancelImageRequest:self.rid];
    self.rid = PHInvalidImageRequestID;
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return self.iv; }
- (void)onDoubleTap:(UITapGestureRecognizer *)g {
    if (self.sv.zoomScale > 1.01) { [self.sv setZoomScale:1.0 animated:YES]; return; }
    CGPoint p = [g locationInView:self.iv];
    CGFloat z = 2.5;
    CGFloat w = self.sv.bounds.size.width / z;
    CGFloat h = self.sv.bounds.size.height / z;
    [self.sv zoomToRect:CGRectMake(p.x-w/2.0, p.y-h/2.0, w, h) animated:YES];
}
- (void)prepareForDisplay {
    if (!self.asset) return;

    NSString *aid = self.asset.localIdentifier ?: @"";
    self.representedId = aid;
    self.iv.image = nil;
    self.sv.zoomScale = 1.0;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;

    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    opt.resizeMode   = PHImageRequestOptionsResizeModeFast;

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize target = CGSizeMake(self.bounds.size.width * scale,
                               self.bounds.size.height * scale);

    __weak typeof(self) weakSelf = self;
    if (self.rid != PHInvalidImageRequestID) [self.mgr cancelImageRequest:self.rid];

    self.rid = [self.mgr requestImageForAsset:self.asset
                                   targetSize:target
                                  contentMode:PHImageContentModeAspectFit
                                      options:opt
                                resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;
        if (![weakSelf.representedId isEqualToString:aid]) return;

        // degraded=YES 是快速图；degraded=NO 是最终高清图
        BOOL degraded = [info[PHImageResultIsDegradedKey] boolValue];
        if (degraded && weakSelf.iv.image) return;

        weakSelf.iv.image = result;
        if (!degraded) weakSelf.rid = PHInvalidImageRequestID;
    }];
}

- (void)endDisplay {
    if (self.rid != PHInvalidImageRequestID) [self.mgr cancelImageRequest:self.rid];
    self.rid = PHInvalidImageRequestID;
}
@end

@interface ASPreviewVideoCell : ASPreviewBaseCell
@property (nonatomic, strong) PHCachingImageManager *mgr;
@property (nonatomic, assign) PHImageRequestID rid;

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerViewController *pvc;
@property (nonatomic, weak) UIViewController *hostVC; // 外部注入

@property (nonatomic, copy) void(^onPlayerReady)(AVPlayer *player);
@end

@implementation ASPreviewVideoCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.mgr = [PHCachingImageManager new];
        self.rid = PHInvalidImageRequestID;
//        self.contentView.backgroundColor = UIColor.blackColor;
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self endDisplay];
    self.asset = nil;
    self.representedId = nil;
    self.hostVC = nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.pvc.view.frame = self.contentView.bounds;
}

- (void)prepareForDisplay {
    if (!self.asset) return;

    NSString *aid = self.asset.localIdentifier ?: @"";
    self.representedId = aid;

    // 清理旧的
    [self endDisplay];

    PHVideoRequestOptions *opt = [PHVideoRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHVideoRequestOptionsDeliveryModeFastFormat;

    __weak typeof(self) weakSelf = self;
    self.rid = [self.mgr requestPlayerItemForVideo:self.asset
                                          options:opt
                                    resultHandler:^(AVPlayerItem * _Nullable item, NSDictionary * _Nullable info) {
        if (![weakSelf.representedId isEqualToString:aid]) return;
        if (!item) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (![weakSelf.representedId isEqualToString:aid]) return;

            weakSelf.player = [AVPlayer playerWithPlayerItem:item];

            if (!weakSelf.pvc) {
                weakSelf.pvc = [AVPlayerViewController new];
                weakSelf.pvc.showsPlaybackControls = YES;
                weakSelf.pvc.videoGravity = AVLayerVideoGravityResizeAspect;
                weakSelf.pvc.view.backgroundColor = UIColor.clearColor;

                if (weakSelf.hostVC) {
                    [weakSelf.hostVC addChildViewController:weakSelf.pvc];
                }
                [weakSelf.contentView addSubview:weakSelf.pvc.view];
                weakSelf.pvc.view.frame = weakSelf.contentView.bounds;
                weakSelf.pvc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

                if (weakSelf.hostVC) {
                    [weakSelf.pvc didMoveToParentViewController:weakSelf.hostVC];
                }
            }

            weakSelf.pvc.player = weakSelf.player;

            if (weakSelf.onPlayerReady) weakSelf.onPlayerReady(weakSelf.player);
        });
    }];
}

- (void)endDisplay {
    if (self.rid != PHInvalidImageRequestID) {
        [self.mgr cancelImageRequest:self.rid];
        self.rid = PHInvalidImageRequestID;
    }

    [self.player pause];
    self.player = nil;

    if (self.pvc) {
        self.pvc.player = nil;

        if (self.pvc.parentViewController) {
            [self.pvc willMoveToParentViewController:nil];
            [self.pvc.view removeFromSuperview];
            [self.pvc removeFromParentViewController];
        } else {
            [self.pvc.view removeFromSuperview];
        }
        self.pvc = nil;
    }
}

@end


@interface ASPreviewLiveCell : ASPreviewBaseCell
@property (nonatomic, strong) UIButton *liveBadgeTapBtn;
@property (nonatomic, assign) BOOL livePlaying;
@property (nonatomic, strong) UIView *liveBadge;
@property (nonatomic, strong) UIImageView *liveIcon;
@property (nonatomic, strong) UILabel *liveText;

@property (nonatomic, strong) PHCachingImageManager *mgr;
@property (nonatomic, assign) PHImageRequestID rid;
@property (nonatomic, strong) PHLivePhotoView *lpv;
@property (nonatomic, strong) UIImpactFeedbackGenerator *impact;

// ✅ 用这两个可调约束来定位 badge 到“图片区域”的底部
@property (nonatomic, strong) NSLayoutConstraint *liveBadgeCenterXToLPVLeading;
@property (nonatomic, strong) NSLayoutConstraint *liveBadgeBottomToLPVTop;
@end

@implementation ASPreviewLiveCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.mgr = [PHCachingImageManager new];

        self.lpv = [PHLivePhotoView new];
        self.lpv.contentMode = UIViewContentModeScaleAspectFit;
        self.lpv.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.lpv];

        [NSLayoutConstraint activateConstraints:@[
            [self.lpv.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.lpv.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.lpv.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.lpv.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        ]];

        // badge
        self.liveBadge = [UIView new];
        self.liveBadge.translatesAutoresizingMaskIntoConstraints = NO;
        self.liveBadge.userInteractionEnabled = YES;
        self.liveBadge.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
        self.liveBadge.layer.cornerRadius = 14;
        self.liveBadge.layer.masksToBounds = YES;
        if (@available(iOS 13.0, *)) self.liveBadge.layer.cornerCurve = kCACornerCurveContinuous;
        [self.contentView addSubview:self.liveBadge];

        self.liveIcon = [UIImageView new];
        self.liveIcon.translatesAutoresizingMaskIntoConstraints = NO;
        self.liveIcon.userInteractionEnabled = NO;
        self.liveIcon.contentMode = UIViewContentModeScaleAspectFit;
        if (@available(iOS 13.0, *)) {
            UIImage *sf = [UIImage systemImageNamed:@"livephoto"];
            self.liveIcon.image = [sf imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            self.liveIcon.tintColor = UIColor.whiteColor;
        } else {
            UIImage *img = [UIImage imageNamed:@"ic_livephoto"];
            self.liveIcon.image = [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        }
        [self.liveBadge addSubview:self.liveIcon];

        self.liveText = [UILabel new];
        self.liveText.translatesAutoresizingMaskIntoConstraints = NO;
        self.liveText.userInteractionEnabled = NO;
        self.liveText.text = @"Live";
        self.liveText.textColor = UIColor.whiteColor;
        self.liveText.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [self.liveBadge addSubview:self.liveText];

        self.liveBadgeTapBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.liveBadgeTapBtn.translatesAutoresizingMaskIntoConstraints = NO;
        self.liveBadgeTapBtn.backgroundColor = UIColor.clearColor;
        [self.liveBadgeTapBtn addTarget:self action:@selector(onLiveBadgeTap)
                       forControlEvents:UIControlEventTouchUpInside];
        [self.liveBadge addSubview:self.liveBadgeTapBtn];

        self.liveBadgeCenterXToLPVLeading = [self.liveBadge.centerXAnchor constraintEqualToAnchor:self.lpv.leadingAnchor constant:0];
        self.liveBadgeBottomToLPVTop = [self.liveBadge.bottomAnchor constraintEqualToAnchor:self.lpv.topAnchor constant:0];

        [NSLayoutConstraint activateConstraints:@[
            self.liveBadgeCenterXToLPVLeading,
            self.liveBadgeBottomToLPVTop,
            [self.liveBadge.heightAnchor constraintEqualToConstant:28],

            [self.liveIcon.leadingAnchor constraintEqualToAnchor:self.liveBadge.leadingAnchor constant:10],
            [self.liveIcon.centerYAnchor constraintEqualToAnchor:self.liveBadge.centerYAnchor],
            [self.liveIcon.widthAnchor constraintEqualToConstant:20],
            [self.liveIcon.heightAnchor constraintEqualToConstant:20],

            [self.liveText.leadingAnchor constraintEqualToAnchor:self.liveIcon.trailingAnchor constant:6],
            [self.liveText.trailingAnchor constraintEqualToAnchor:self.liveBadge.trailingAnchor constant:-12],
            [self.liveText.centerYAnchor constraintEqualToAnchor:self.liveBadge.centerYAnchor],

            [self.liveBadgeTapBtn.leadingAnchor constraintEqualToAnchor:self.liveBadge.leadingAnchor],
            [self.liveBadgeTapBtn.trailingAnchor constraintEqualToAnchor:self.liveBadge.trailingAnchor],
            [self.liveBadgeTapBtn.topAnchor constraintEqualToAnchor:self.liveBadge.topAnchor],
            [self.liveBadgeTapBtn.bottomAnchor constraintEqualToAnchor:self.liveBadge.bottomAnchor],
        ]];

        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPress:)];
        lp.minimumPressDuration = 0.22;
        lp.allowableMovement = 10;
        [self.contentView addGestureRecognizer:lp];

        self.impact = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    // 计算 LivePhoto 在 lpv 中 AspectFit 后的真实显示区域
    CGRect bounds = self.lpv.bounds;
    CGSize mediaSize = CGSizeZero;
    if (self.asset) {
        mediaSize = CGSizeMake(self.asset.pixelWidth, self.asset.pixelHeight);
    }

    CGRect imgRect = bounds;
    if (mediaSize.width > 0 && mediaSize.height > 0) {
        imgRect = AVMakeRectWithAspectRatioInsideRect(mediaSize, bounds);
    }

    // badge 居中到图片区域中点，底部=图片区域底-20
    self.liveBadgeCenterXToLPVLeading.constant = CGRectGetMidX(imgRect);
    self.liveBadgeBottomToLPVTop.constant = CGRectGetMaxY(imgRect) - 20.0;
}

- (void)prepareForDisplay {
    if (!self.asset) return;

    [self setNeedsLayout];
    [self layoutIfNeeded];

    NSString *aid = self.asset.localIdentifier ?: @"";
    self.representedId = aid;
    self.lpv.livePhoto = nil;

    PHLivePhotoRequestOptions *opt = [PHLivePhotoRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize target = CGSizeMake(self.bounds.size.width * scale,
                               self.bounds.size.height * scale);

    __weak typeof(self) weakSelf = self;
    self.rid = [self.mgr requestLivePhotoForAsset:self.asset
                                      targetSize:target
                                     contentMode:PHImageContentModeAspectFit
                                         options:opt
                                   resultHandler:^(PHLivePhoto * _Nullable livePhoto, NSDictionary * _Nullable info) {
        if (![weakSelf.representedId isEqualToString:aid]) return;
        if (!livePhoto) return;

        BOOL degraded = [info[PHImageResultIsDegradedKey] boolValue];
        if (degraded && weakSelf.lpv.livePhoto) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (![weakSelf.representedId isEqualToString:aid]) return;

            weakSelf.lpv.livePhoto = livePhoto;

            // ✅ livePhoto 回来后再触发一次，确保最终位置稳定
            [weakSelf setNeedsLayout];
            [weakSelf layoutIfNeeded];

            if (!degraded) weakSelf.rid = PHInvalidImageRequestID;
        });
    }];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self endDisplay];
    self.livePlaying = NO;
    self.asset = nil;
    self.representedId = nil;
    self.lpv.livePhoto = nil;
}

- (void)endDisplay {
    self.livePlaying = NO;
    if (self.rid != PHInvalidImageRequestID) [self.mgr cancelImageRequest:self.rid];
    self.rid = PHInvalidImageRequestID;
    [self.lpv stopPlayback];
    self.lpv.livePhoto = nil;
}

#pragma mark - play control

- (void)as_startLivePlayback {
    if (!self.lpv.livePhoto) return;
    self.livePlaying = YES;
    [self.impact prepare];
    [self.impact impactOccurred];
    [self.lpv startPlaybackWithStyle:PHLivePhotoViewPlaybackStyleFull];
}

- (void)as_stopLivePlayback {
    self.livePlaying = NO;
    [self.impact prepare];
    [self.impact impactOccurred];
    [self.lpv stopPlayback];
}

- (void)onLiveBadgeTap {
    if (!self.lpv.livePhoto) return;

    if (self.livePlaying) {
        [self as_stopLivePlayback];
        return;
    }

    [self as_startLivePlayback];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.livePlaying = NO;
    });
}

- (void)onLongPress:(UILongPressGestureRecognizer *)g {
    if (!self.lpv.livePhoto) return;

    if (g.state == UIGestureRecognizerStateBegan) {
        [self as_startLivePlayback];
    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled ||
               g.state == UIGestureRecognizerStateFailed) {
        [self as_stopLivePlayback];
    }
}

@end

#pragma mark - Thumb cell

@interface ASPreviewThumbCell : UICollectionViewCell
@property (nonatomic, strong) UIView *ring;
@property (nonatomic, strong) UIImageView *iv;
@property (nonatomic, strong) UIButton *checkBtn;
@property (nonatomic, strong) UIButton *checkTapBtn;
@property (nonatomic, strong) ASBestBadgeView *best;

@property (nonatomic, copy) NSString *representedId;
@property (nonatomic, assign) PHImageRequestID rid;

- (void)applyChecked:(BOOL)checked;
- (void)applyCurrent:(BOOL)isCurrent;
@end

@implementation ASPreviewThumbCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.contentView.backgroundColor = UIColor.clearColor;
        self.rid = PHInvalidImageRequestID;

        self.ring = [UIView new];
        self.ring.translatesAutoresizingMaskIntoConstraints = NO;
        self.ring.backgroundColor = UIColor.clearColor;
        self.ring.layer.cornerRadius = 34;
        self.ring.layer.masksToBounds = YES;
        [self.contentView addSubview:self.ring];

        self.iv = [UIImageView new];
        self.iv.translatesAutoresizingMaskIntoConstraints = NO;
        self.iv.contentMode = UIViewContentModeScaleAspectFill;
        self.iv.clipsToBounds = YES;
        self.iv.layer.cornerRadius = 33;
        self.iv.layer.masksToBounds = YES;
        [self.ring addSubview:self.iv];

        self.checkBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.checkBtn.userInteractionEnabled = NO;
        self.checkBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.checkBtn];

        self.checkTapBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.checkTapBtn.translatesAutoresizingMaskIntoConstraints = NO;
        self.checkTapBtn.backgroundColor = UIColor.clearColor;
        [self.contentView addSubview:self.checkTapBtn];

        self.best = [[ASBestBadgeView alloc] initWithBadgeSize:CGSizeMake(42, 16)];
        self.best.userInteractionEnabled = NO;
        self.best.showsClose = NO;
        self.best.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.best];

        [NSLayoutConstraint activateConstraints:@[
            [self.ring.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.ring.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.ring.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.ring.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            // inset = 3（border=2 + gap=1）
            [self.iv.leadingAnchor constraintEqualToAnchor:self.ring.leadingAnchor constant:3],
            [self.iv.trailingAnchor constraintEqualToAnchor:self.ring.trailingAnchor constant:-3],
            [self.iv.topAnchor constraintEqualToAnchor:self.ring.topAnchor constant:3],
            [self.iv.bottomAnchor constraintEqualToAnchor:self.ring.bottomAnchor constant:-3],

            [self.checkBtn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:-2],
            [self.checkBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:2],
            [self.checkBtn.widthAnchor constraintEqualToConstant:22],
            [self.checkBtn.heightAnchor constraintEqualToConstant:22],

            [self.checkTapBtn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:-10],
            [self.checkTapBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:10],
            [self.checkTapBtn.widthAnchor constraintEqualToConstant:44],
            [self.checkTapBtn.heightAnchor constraintEqualToConstant:44],

            [self.best.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [self.best.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:0],
        ]];

        [self applyCurrent:NO];
        [self applyChecked:NO];
        self.best.hidden = YES;
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedId = nil;
    self.iv.image = nil;
    self.best.hidden = YES;
    [self applyCurrent:NO];
    [self applyChecked:NO];
    self.rid = PHInvalidImageRequestID;
}

- (void)applyChecked:(BOOL)checked {
    [self.checkBtn setImage:(checked ? ASSelectOnImg() : ASSelectOffImg()) forState:UIControlStateNormal];
}

- (void)applyCurrent:(BOOL)isCurrent {
    self.ring.layer.borderWidth = isCurrent ? 2.0 : 0.0;
    self.ring.layer.borderColor = isCurrent ? ASBlue().CGColor : UIColor.clearColor.CGColor;
}

@end

#pragma mark - VC

@interface ASMediaPreviewViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate>
@property (nonatomic, strong) NSArray<PHAsset *> *assets;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, strong) NSMutableIndexSet *selected;

@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UILabel *indexLabel;

@property (nonatomic, strong) UICollectionView *pager;
@property (nonatomic, strong) NSLayoutConstraint *pagerHeight;

@property (nonatomic, strong) UIButton *topSelectBtn;
@property (nonatomic, strong) ASBestBadgeView *bestBadge;

@property (nonatomic, strong) UICollectionView *thumbs;
@property (nonatomic, strong) PHCachingImageManager *mgr;

@property (nonatomic, weak) AVPlayer *currentPlayer;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, assign) BOOL isExiting;
@property (nonatomic, assign) BOOL didSendBackCallback;

@end

@implementation ASMediaPreviewViewController

- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets initialIndex:(NSInteger)initialIndex {
    if (self = [super init]) {
        _assets = assets ?: @[];
        _currentIndex = MAX(0, MIN(initialIndex, (NSInteger)_assets.count - 1));
        _bestIndex = 0;
        _showsBestBadge = YES;
        _selected = [NSMutableIndexSet indexSet];
        _mgr = [PHCachingImageManager new];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (void)as_updateThumbCurrentFrom:(NSInteger)oldIdx to:(NSInteger)newIdx {
    if (self.thumbs.hidden) return;

    [UIView performWithoutAnimation:^{
        if (oldIdx >= 0 && oldIdx < self.assets.count) {
            NSIndexPath *oldIP = [NSIndexPath indexPathForItem:oldIdx inSection:0];
            ASPreviewThumbCell *oldCell = (ASPreviewThumbCell *)[self.thumbs cellForItemAtIndexPath:oldIP];
            if (oldCell) {
                [oldCell applyCurrent:NO];
                // best 你说不管就不处理
            }
        }

        if (newIdx >= 0 && newIdx < self.assets.count) {
            NSIndexPath *newIP = [NSIndexPath indexPathForItem:newIdx inSection:0];
            ASPreviewThumbCell *newCell = (ASPreviewThumbCell *)[self.thumbs cellForItemAtIndexPath:newIP];
            if (newCell) {
                [newCell applyCurrent:YES];
                [newCell applyChecked:[self.selected containsIndex:newIdx]];
            }
        }
    }];
}

- (void)as_updateThumbCheckedAtIndex:(NSInteger)idx {
    if (self.thumbs.hidden) return;
    NSIndexPath *ip = [NSIndexPath indexPathForItem:idx inSection:0];
    ASPreviewThumbCell *cell = (ASPreviewThumbCell *)[self.thumbs cellForItemAtIndexPath:ip];

    [UIView performWithoutAnimation:^{
        if (cell) {
            [cell applyChecked:[self.selected containsIndex:idx]];
        } else {
            // 不在屏幕上才 reload（不会导致“可见闪烁”）
            [self.thumbs reloadItemsAtIndexPaths:@[ip]];
        }
    }];
}

- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets
                  initialIndex:(NSInteger)initialIndex
               selectedIndexes:(NSIndexSet *)selectedIndexes {
    if (self = [self initWithAssets:assets initialIndex:initialIndex]) {
        if (selectedIndexes.count) {
            [self.selected addIndexes:selectedIndexes];
        }
    }
    return self;
}

- (void)notifySelectionChanged {
    if (self.onSelectionChanged) {
        self.onSelectionChanged([self.selected copy]); // NSMutableIndexSet -> NSIndexSet
    }
}

- (void)dealloc {
    if (self.timeObserver && self.currentPlayer) {
        @try { [self.currentPlayer removeTimeObserver:self.timeObserver]; } @catch (__unused NSException *e) {}
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.navigationController.navigationBarHidden = YES;

    [self buildUI];
    [self reloadTopText];
    [self scrollToIndex:self.currentIndex animated:NO];
    [self updateOverlays];
}

#pragma mark - UI

- (void)buildUI {
    BOOL multi = (self.assets.count > 1);

    // top bar
    self.topBar = [UIView new];
    self.topBar.backgroundColor = UIColor.whiteColor;
    self.topBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.topBar];

    self.backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *back = [[UIImage imageNamed:@"ic_back_blue"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.backBtn setImage:back forState:UIControlStateNormal];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backBtn addTarget:self action:@selector(onTapBack) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.backBtn];

    self.sizeLabel = [UILabel new];
    self.sizeLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
    self.sizeLabel.textColor = ASBlack();
    self.sizeLabel.textAlignment = NSTextAlignmentCenter;

    self.indexLabel = [UILabel new];
    self.indexLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    self.indexLabel.textColor = ASGray666();
    self.indexLabel.textAlignment = NSTextAlignmentCenter;

    UIStackView *center = [[UIStackView alloc] initWithArrangedSubviews:@[self.sizeLabel, self.indexLabel]];
    center.axis = UILayoutConstraintAxisVertical;
    center.alignment = UIStackViewAlignmentCenter;
    center.spacing = 4;
    center.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topBar addSubview:center];

    // pager（横向分页）
    UICollectionViewFlowLayout *lay = [UICollectionViewFlowLayout new];
    lay.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    lay.minimumLineSpacing = 0;
    lay.minimumInteritemSpacing = 0;

    self.pager = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:lay];
    self.pager.pagingEnabled = YES;
    self.pager.showsHorizontalScrollIndicator = NO;
//    self.pager.backgroundColor = UIColor.blackColor;
    self.pager.dataSource = self;
    self.pager.delegate = self;
    self.pager.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pager registerClass:ASPreviewPhotoCell.class forCellWithReuseIdentifier:@"photo"];
    [self.pager registerClass:ASPreviewVideoCell.class forCellWithReuseIdentifier:@"video"];
    [self.pager registerClass:ASPreviewLiveCell.class  forCellWithReuseIdentifier:@"live"];
    [self.view addSubview:self.pager];

    // overlays（多资源才显示）
    self.topSelectBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.topSelectBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.topSelectBtn.contentEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10);
    [self.topSelectBtn addTarget:self action:@selector(onToggleSelectCurrent) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.topSelectBtn];

    self.bestBadge = [[ASBestBadgeView alloc] initWithBadgeSize:CGSizeMake(60, 24)];
    self.bestBadge.translatesAutoresizingMaskIntoConstraints = NO;

    self.bestBadge.showsClose = NO;
    self.bestBadge.onClose = nil;

    [self.view addSubview:self.bestBadge];

    // thumbs（多资源才显示）
    UICollectionViewFlowLayout *tlay = [UICollectionViewFlowLayout new];
    tlay.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    tlay.minimumLineSpacing = 10;
    tlay.sectionInset = UIEdgeInsetsMake(0, 16, 0, 16);

    self.thumbs = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:tlay];
    self.thumbs.backgroundColor = UIColor.clearColor;
    self.thumbs.opaque = NO;
    self.thumbs.backgroundView = nil;
    self.thumbs.dataSource = self;
    self.thumbs.delegate = self;
    self.thumbs.showsHorizontalScrollIndicator = NO;
    self.thumbs.translatesAutoresizingMaskIntoConstraints = NO;
    [self.thumbs registerClass:ASPreviewThumbCell.class forCellWithReuseIdentifier:@"thumb"];
    [self.view addSubview:self.thumbs];
    self.thumbs.hidden = !multi;

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    [NSLayoutConstraint activateConstraints:@[
        [self.topBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.topBar.heightAnchor constraintEqualToConstant:56],

        [self.backBtn.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor constant:16],
        [self.backBtn.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.backBtn.widthAnchor constraintEqualToConstant:24],
        [self.backBtn.heightAnchor constraintEqualToConstant:24],

        [center.centerXAnchor constraintEqualToAnchor:self.topBar.centerXAnchor],
        [center.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],

        [self.pager.topAnchor constraintEqualToAnchor:self.topBar.bottomAnchor constant:10],
        [self.pager.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.pager.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    self.pagerHeight = [self.pager.heightAnchor constraintEqualToAnchor:self.pager.widthAnchor multiplier:(611.0/402.0)];
    self.pagerHeight.active = YES;

    [NSLayoutConstraint activateConstraints:@[
//        [self.pager.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

        [self.thumbs.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.thumbs.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.thumbs.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.thumbs.heightAnchor constraintEqualToConstant:(multi ? 120 : 0)],
        [self.pager.bottomAnchor constraintEqualToAnchor:(multi ? self.thumbs.topAnchor : safe.bottomAnchor)],
    ]];

    [NSLayoutConstraint activateConstraints:@[
        [self.topSelectBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.topSelectBtn.topAnchor constraintEqualToAnchor:self.pager.topAnchor constant:18],
        [self.topSelectBtn.widthAnchor constraintEqualToConstant:44],
        [self.topSelectBtn.heightAnchor constraintEqualToConstant:44],

        [self.bestBadge.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],
        [self.bestBadge.bottomAnchor constraintEqualToAnchor:self.pager.bottomAnchor constant:-18],
    ]];

    self.topSelectBtn.hidden = !multi;
    self.bestBadge.hidden = YES;
}

#pragma mark - Back / Return selected

- (NSArray<PHAsset *> *)selectedAssetsArray {
    NSMutableArray<PHAsset *> *arr = [NSMutableArray array];
    [self.selected enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx < self.assets.count) [arr addObject:self.assets[idx]];
    }];
    return arr;
}

- (void)sendBackIfNeeded {
    if (self.didSendBackCallback) return;
    self.didSendBackCallback = YES;

    NSIndexSet *idxs = [self.selected copy];
    NSArray<PHAsset *> *assets = [self selectedAssetsArray];

    if (self.onBack) self.onBack(assets, idxs);
    if (self.onSelectionChanged) self.onSelectionChanged(idxs);
}

- (void)onTapBack {
    [self sendBackIfNeeded];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    // ✅ 手势返回 / interactive pop 会走这里
    if (self.isMovingFromParentViewController || self.isBeingDismissed) {
        [self sendBackIfNeeded];
    }
}

#pragma mark - Top texts & overlays

- (void)reloadTopText {
    if (self.assets.count == 0) { self.sizeLabel.text = @"--"; self.indexLabel.text = @"--"; return; }
    PHAsset *a = self.assets[self.currentIndex];
    uint64_t bytes = ASAssetTotalBytes(a);
    self.sizeLabel.text = bytes > 0 ? ASHumanSizeShort(bytes) : @"--";
    self.indexLabel.text = [NSString stringWithFormat:@"%ld/%ld", (long)self.currentIndex+1, (long)self.assets.count];
}

- (void)updateOverlays {
    BOOL multi = (self.assets.count > 1);
    self.topSelectBtn.hidden = !multi;

    if (!multi) {
        self.bestBadge.hidden = YES;
        return;
    }

    BOOL checked = [self.selected containsIndex:self.currentIndex];
    [self.topSelectBtn setImage:(checked ? ASSelectOnImg() : ASSelectGrayOffImg()) forState:UIControlStateNormal];

    BOOL isBest = (self.currentIndex == self.bestIndex);
    self.bestBadge.hidden = !(multi && isBest);
    self.bestBadge.showsClose = NO;
}

#pragma mark - Selection

- (void)onToggleSelectCurrent {
    if ([self.selected containsIndex:self.currentIndex]) [self.selected removeIndex:self.currentIndex];
    else [self.selected addIndex:self.currentIndex];

    [self updateOverlays];
    [self as_updateThumbCheckedAtIndex:self.currentIndex]; // ✅ 不 reload 可见 cell

    [self notifySelectionChanged];
}

#pragma mark - Paging

- (void)scrollToIndex:(NSInteger)idx animated:(BOOL)animated {
    if (idx == self.currentIndex && !animated) return;
    if (self.assets.count == 0) return;
    idx = MAX(0, MIN(idx, (NSInteger)self.assets.count - 1));

    NSInteger old = self.currentIndex;
    self.currentIndex = idx;

    [self.view layoutIfNeeded];
    CGFloat w = self.pager.bounds.size.width;
    [self.pager setContentOffset:CGPointMake(w * idx, 0) animated:animated];

    [self reloadTopText];
    [self updateOverlays];

    if (self.assets.count > 1) {
        NSIndexPath *ip = [NSIndexPath indexPathForItem:idx inSection:0];
        [self.thumbs scrollToItemAtIndexPath:ip
                            atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                    animated:animated];

        [self as_updateThumbCurrentFrom:old to:idx];   // ✅ 只更新旧/新
    }
}

#pragma mark - UICollectionView

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.assets.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {

    PHAsset *a = self.assets[indexPath.item];
    BOOL isLive = (a.mediaType == PHAssetMediaTypeImage) && ((a.mediaSubtypes & PHAssetMediaSubtypePhotoLive) != 0);

    if (collectionView == self.pager) {
        if (a.mediaType == PHAssetMediaTypeVideo) {
            ASPreviewVideoCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"video" forIndexPath:indexPath];
            cell.asset = a;
            cell.hostVC = self;
            __weak typeof(self) weakSelf = self;
            cell.onPlayerReady = ^(AVPlayer *player) {
                if (weakSelf.currentIndex == indexPath.item) [player play];
            };
            return cell;
        } else if (isLive) {
            ASPreviewLiveCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"live" forIndexPath:indexPath];
            cell.asset = a;
            [cell prepareForDisplay];
            return cell;
        } else {
            ASPreviewPhotoCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"photo" forIndexPath:indexPath];
            cell.asset = a;
            [cell prepareForDisplay];
            return cell;
        }
    }

    ASPreviewThumbCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"thumb" forIndexPath:indexPath];

    BOOL checked = [self.selected containsIndex:indexPath.item];
    [cell applyChecked:checked];

    [cell applyCurrent:(indexPath.item == self.currentIndex)];

    BOOL multi = (self.assets.count > 1);
    BOOL isBest = (indexPath.item == self.bestIndex);
    cell.best.hidden = !(multi && isBest);

    [cell.checkTapBtn removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    cell.checkTapBtn.tag = indexPath.item;
    [cell.checkTapBtn addTarget:self action:@selector(onThumbCheckTap:) forControlEvents:UIControlEventTouchUpInside];

    NSString *aid = a.localIdentifier ?: @"";
    cell.representedId = aid;
    cell.iv.image = nil;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;

    CGFloat px = 68 * UIScreen.mainScreen.scale * 2.0;
    CGSize target = CGSizeMake(px, px);

    __weak typeof(cell) weakCell = cell;
    cell.rid = [self.mgr requestImageForAsset:a
                                   targetSize:target
                                  contentMode:PHImageContentModeAspectFill
                                      options:opt
                                resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;
        if (![weakCell.representedId isEqualToString:aid]) return;
        BOOL degraded = [info[PHImageResultIsDegradedKey] boolValue];
        if (degraded && weakCell.iv.image) return;
        weakCell.iv.image = result;
    }];

    return cell;
}

- (void)onThumbCheckTap:(UIButton *)btn {
    NSInteger idx = btn.tag;
    if (idx < 0 || idx >= self.assets.count) return;

    if ([self.selected containsIndex:idx]) [self.selected removeIndex:idx];
    else [self.selected addIndex:idx];

    if (idx == self.currentIndex) [self updateOverlays];

    [self as_updateThumbCheckedAtIndex:idx];
    [self notifySelectionChanged];
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout*)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {

    if (collectionView == self.pager) return collectionView.bounds.size;
    return CGSizeMake(68, 68);
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    if (collectionView != self.pager) return;
    if ([cell isKindOfClass:ASPreviewBaseCell.class]) {
        [(ASPreviewBaseCell *)cell prepareForDisplay];
    }
}

- (void)collectionView:(UICollectionView *)collectionView
 didEndDisplayingCell:(UICollectionViewCell *)cell
   forItemAtIndexPath:(NSIndexPath *)indexPath {

    if (collectionView == self.thumbs && [cell isKindOfClass:ASPreviewThumbCell.class]) {
        ASPreviewThumbCell *c = (ASPreviewThumbCell *)cell;
        if (c.rid != PHInvalidImageRequestID) {
            [self.mgr cancelImageRequest:c.rid];
            c.rid = PHInvalidImageRequestID;
        }
        return;
    }

    if (collectionView != self.pager) return;
    if ([cell isKindOfClass:ASPreviewBaseCell.class]) {
        [(ASPreviewBaseCell *)cell endDisplay];
    }
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (collectionView != self.thumbs) return;
    [self scrollToIndex:indexPath.item animated:YES];
}

#pragma mark - pager scroll end

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView != self.pager) return;

    CGFloat w = self.pager.bounds.size.width;
    if (w <= 0) return;

    NSInteger idx = (NSInteger)lrint(scrollView.contentOffset.x / w);
    idx = MAX(0, MIN(idx, (NSInteger)self.assets.count - 1));
    if (idx == self.currentIndex) return;

    NSInteger old = self.currentIndex;
    self.currentIndex = idx;

    [self reloadTopText];
    [self updateOverlays];

    if (self.assets.count > 1) {
        NSIndexPath *ip = [NSIndexPath indexPathForItem:idx inSection:0];
        [self.thumbs scrollToItemAtIndexPath:ip
                            atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                    animated:YES];

        [self as_updateThumbCurrentFrom:old to:idx];   // ✅ 不 reloadData
    }
}

@end
