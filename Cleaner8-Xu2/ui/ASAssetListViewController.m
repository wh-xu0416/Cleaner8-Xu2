#import "ASAssetListViewController.h"
#import <Photos/Photos.h>
#import "ASPhotoScanManager.h"
#import "ASCustomNavBar.h"
#import "ASMediaPreviewViewController.h"
#import "ResultViewController.h"
#import "Common.h"

static inline CGFloat SWDesignWidth(void) { return 402.0; }
static inline CGFloat SWDesignHeight(void) { return 874.0; }
static inline CGFloat SWScaleX(void) {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    return w / SWDesignWidth();
}

static inline CGFloat SWScaleY(void) {
    CGFloat h = UIScreen.mainScreen.bounds.size.height;
    return h / SWDesignHeight();
}

static inline CGFloat SWScale(void) {
    return MIN(SWScaleX(), SWScaleY());
}
static inline CGFloat SW(CGFloat v) { return round(v * SWScale()); }
static inline UIFont *SWFontS(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:round(size * SWScale()) weight:weight];
}
static inline UIEdgeInsets SWInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) {
    return UIEdgeInsetsMake(SW(t), SW(l), SW(b), SW(r));
}
#pragma mark - UI helpers
typedef NS_ENUM(NSInteger, ASAssetSortMode) {
    ASAssetSortModeNewest = 0,   // 新 -> 旧（默认）
    ASAssetSortModeOldest,
    ASAssetSortModeLargest,
    ASAssetSortModeSmallest
};

static inline UIColor *ASHexRGBA(uint32_t hex) {
    CGFloat r = ((hex >> 24) & 0xFF) / 255.0;
    CGFloat g = ((hex >> 16) & 0xFF) / 255.0;
    CGFloat b = ((hex >> 8)  & 0xFF) / 255.0;
    CGFloat a = ( hex        & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static inline UIColor *ASBgColor(void) {
    // LaunchViewController: ASRGB(246, 248, 251)
    return [UIColor colorWithRed:246/255.0 green:248/255.0 blue:251/255.0 alpha:1.0];
}

static inline NSString *ASHumanSize(uint64_t bytes) {
    double b = (double)bytes;
    if (b < 1024) return [NSString stringWithFormat:@"%.0f B", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f KB", b];
    b /= 1024; if (b < 1024) return [NSString stringWithFormat:@"%.1f MB", b];
    b /= 1024; return [NSString stringWithFormat:@"%.2f GB", b];
}

static inline NSString *ASTypeText(PHAssetMediaType t) {
    return (t == PHAssetMediaTypeVideo) ? NSLocalizedString(@"video", nil) : NSLocalizedString(@"photo", nil);
}

static inline NSString *ASDurationText(NSTimeInterval seconds) {
    if (seconds < 0) seconds = 0;
    NSInteger s = (NSInteger)llround(seconds);
    NSInteger h = s / 3600;
    NSInteger m = (s % 3600) / 60;
    NSInteger ss = s % 60;
    if (h > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)ss];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)ss];
}

@interface ASVideoGroupThumbCell : UICollectionViewCell
@property (nonatomic, copy) NSString *representedLocalId;

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UIImageView *selectIcon; 
@property (nonatomic, strong) UIButton *selectBtn;
@property (nonatomic, strong) UIButton *previewBtn;

@property (nonatomic, strong) UIImageView *bestBadge;

- (void)applySelected:(BOOL)sel;
- (void)applyBest:(BOOL)isBest;
@end

@implementation ASVideoGroupThumbCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (self=[super initWithFrame:frame]) {
        _coverView = [UIImageView new];
        _coverView.contentMode = UIViewContentModeScaleAspectFill;
        _coverView.clipsToBounds = YES;
        _coverView.layer.cornerRadius = SW(8);

        _infoLabel = [UILabel new];
        _infoLabel.numberOfLines = 2;
        _infoLabel.font = SWFontS(12, UIFontWeightMedium);
        _infoLabel.textColor = UIColor.whiteColor;

        _selectIcon = [UIImageView new];
        _selectIcon.contentMode = UIViewContentModeScaleAspectFit;

        _selectBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _selectBtn.backgroundColor = UIColor.clearColor;

        _previewBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _previewBtn.backgroundColor = UIColor.clearColor;

        _bestBadge = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_best"]];
        _bestBadge.contentMode = UIViewContentModeScaleAspectFit;
        _bestBadge.hidden = YES;

        [self.contentView addSubview:_coverView];
        [self.contentView addSubview:_previewBtn];
        [self.contentView addSubview:_infoLabel];
        [self.contentView addSubview:_bestBadge];
        [self.contentView addSubview:_selectIcon];
        [self.contentView addSubview:_selectBtn];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.coverView.frame = self.contentView.bounds;
    self.previewBtn.frame = self.contentView.bounds;
    CGRect b = self.contentView.bounds;
    CGFloat pad = SW(10);

    CGFloat infoW = self.contentView.bounds.size.width - pad*2 - SW(24) - SW(6);
    self.infoLabel.frame = CGRectMake(pad, pad, MAX(SW(40), infoW), SW(34));

    CGFloat s = SW(24);
    self.selectIcon.frame = CGRectMake(self.contentView.bounds.size.width - pad - s, pad, s, s);
    self.selectBtn.frame = CGRectInset(self.selectIcon.frame, -SW(8), -SW(8));

    CGFloat bw = SW(60), bh = SW(24);
    self.bestBadge.frame = CGRectMake(pad,CGRectGetHeight(b) - pad - bh,bw, bh);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedLocalId = @"";
    self.coverView.image = nil;
    self.infoLabel.text = @"";
    self.bestBadge.hidden = YES;
    [self applySelected:NO];
}

- (void)applyBest:(BOOL)isBest { self.bestBadge.hidden = !isBest; }

- (void)applySelected:(BOOL)sel {
    self.selectIcon.image = [UIImage imageNamed:(sel ? @"ic_select_s" : @"ic_select_n")];
}
@end

@interface ASVideoGroupCardCell : UICollectionViewCell <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic) NSInteger sectionIndex;

@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UIButton *selectAllBtn;

@property (nonatomic, strong) UICollectionView *thumbCV;

@property (nonatomic, strong) NSArray<ASAssetModel *> *models;
@property (nonatomic, strong) NSDictionary<NSString*, PHAsset*> *assetById;
@property (nonatomic, strong) PHCachingImageManager *imgMgr;
@property (nonatomic, strong) NSSet<NSString*> *selectedIds;
@property (nonatomic, copy) NSString *unitText;

@property (nonatomic, copy) void (^onTapSelectAll)(NSInteger sectionIndex);
@property (nonatomic, copy) void (^onToggleIndex)(NSInteger sectionIndex, NSInteger modelIndex);
@property (nonatomic, copy) void (^onPreviewIndex)(NSInteger sectionIndex, NSInteger modelIndex);

- (void)bindModels:(NSArray<ASAssetModel *> *)models
      sectionIndex:(NSInteger)sectionIndex
          unitText:(NSString *)unitText
        selectedIds:(NSSet<NSString*> *)selectedIds
         assetById:(NSDictionary<NSString*, PHAsset*> *)assetById
            imgMgr:(PHCachingImageManager *)imgMgr;

- (void)refreshSelectionUI;
@end

@implementation ASVideoGroupCardCell

- (CGFloat)as_textW:(NSString *)t font:(UIFont *)f h:(CGFloat)h {
    if (t.length == 0) return 0;
    return ceil([t boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, h)
                               options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
                            attributes:@{NSFontAttributeName:f}
                               context:nil].size.width);
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self=[super initWithFrame:frame]) {

        _card = [UIView new];
        _card.backgroundColor = UIColor.whiteColor;
        _card.layer.cornerRadius = SW(20);
        _card.clipsToBounds = YES;

        _countLabel = [UILabel new];
        _countLabel.font = SWFontS(20, UIFontWeightMedium);
        _countLabel.textColor = UIColor.blackColor;

        _sizeLabel = [UILabel new];
        _sizeLabel.font = SWFontS(12, UIFontWeightSemibold);
        _sizeLabel.textColor = [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];

        _selectAllBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _selectAllBtn.adjustsImageWhenHighlighted = NO;
        _selectAllBtn.showsTouchWhenHighlighted = NO;
        _selectAllBtn.titleLabel.font = SWFontS(13, UIFontWeightMedium);
        _selectAllBtn.backgroundColor = UIColor.clearColor;
        _selectAllBtn.layer.cornerRadius = SW(18);
        _selectAllBtn.layer.borderWidth = SW(1);
        _selectAllBtn.contentEdgeInsets = SWInsets(8, 8, 8, 8);

        [_selectAllBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
        [_selectAllBtn setTitleColor:UIColor.blackColor forState:UIControlStateHighlighted];
        [_selectAllBtn addTarget:self action:@selector(onTapSelectAllBtn) forControlEvents:UIControlEventTouchUpInside];

        UICollectionViewFlowLayout *l = [UICollectionViewFlowLayout new];
        l.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        l.minimumLineSpacing = SW(10);
        l.minimumInteritemSpacing = SW(10);

        _thumbCV = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:l];
        _thumbCV.backgroundColor = UIColor.clearColor;
        _thumbCV.showsHorizontalScrollIndicator = NO;
        _thumbCV.dataSource = self;
        _thumbCV.delegate = self;
        _thumbCV.allowsSelection = NO;
        _thumbCV.contentInset = UIEdgeInsetsZero;
        [_thumbCV registerClass:ASVideoGroupThumbCell.class forCellWithReuseIdentifier:@"ASVideoGroupThumbCell"];

        [_card addSubview:_countLabel];
        [_card addSubview:_sizeLabel];
        [_card addSubview:_selectAllBtn];
        [_card addSubview:_thumbCV];

        [self.contentView addSubview:_card];
        self.contentView.backgroundColor = UIColor.clearColor;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.card.frame = self.contentView.bounds;

    CGFloat pad = SW(20);
    CGFloat twoLineGap = SW(4);

    CGFloat countH = ceil(self.countLabel.font.lineHeight);
    CGFloat sizeH  = ceil(self.sizeLabel.font.lineHeight);
    CGFloat leftBlockH = countH + twoLineGap + sizeH;

    CGFloat btnH = SW(36);
    UIFont *bf = self.selectAllBtn.titleLabel.font ?: SWFontS(13, UIFontWeightMedium);
    UIEdgeInsets in = self.selectAllBtn.contentEdgeInsets;

    CGFloat t1 = [self as_textW:NSLocalizedString(@"Select All", nil) font:bf h:btnH];
    CGFloat t2 = [self as_textW:NSLocalizedString(@"Deselect All", nil) font:bf h:btnH];
    CGFloat wText = MAX(t1, t2);

    CGFloat btnW = ceil(in.left + wText + in.right);
    btnW = MIN(btnW, self.card.bounds.size.width - pad*2);

    CGFloat btnY = pad + floor((leftBlockH - btnH)/2.0);
    self.selectAllBtn.frame = CGRectMake(self.card.bounds.size.width - pad - btnW, btnY, btnW, btnH);

    CGFloat leftW = CGRectGetMinX(self.selectAllBtn.frame) - pad - SW(12);
    self.countLabel.frame = CGRectMake(pad, pad, MAX(SW(60), leftW), countH);
    self.sizeLabel.frame  = CGRectMake(pad, CGRectGetMaxY(self.countLabel.frame) + twoLineGap, MAX(SW(60), leftW), sizeH);

    CGFloat listY = CGRectGetMaxY(self.sizeLabel.frame) + SW(10);

    self.thumbCV.frame = CGRectMake(pad,
                                    listY,
                                    self.card.bounds.size.width - pad,
                                    SW(160));
}

- (uint64_t)cleanableBytes {
    uint64_t s = 0;
    for (NSInteger i=1; i<(NSInteger)self.models.count; i++) s += self.models[i].fileSizeBytes;
    return s;
}

- (BOOL)isAllCleanablesSelected {
    if (self.models.count == 0) return NO;
    for (NSInteger i=1; i<(NSInteger)self.models.count; i++) {
        NSString *lid = self.models[i].localId ?: @"";
        if (lid.length && ![self.selectedIds containsObject:lid]) return NO;
    }
    return YES;
}

- (void)bindModels:(NSArray<ASAssetModel *> *)models
      sectionIndex:(NSInteger)sectionIndex
          unitText:(NSString *)unitText
        selectedIds:(NSSet<NSString*> *)selectedIds
         assetById:(NSDictionary<NSString*, PHAsset*> *)assetById
            imgMgr:(PHCachingImageManager *)imgMgr {

    self.sectionIndex = sectionIndex;
    self.models = models ?: @[];
    self.unitText = unitText ?: NSLocalizedString(@"Videos", nil);
    self.selectedIds = selectedIds ?: [NSSet set];
    self.assetById = assetById ?: @{};
    self.imgMgr = imgMgr;

    self.countLabel.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)self.models.count, self.unitText];
    self.sizeLabel.text = ASHumanSize([self cleanableBytes]);

    [UIView performWithoutAnimation:^{ [self.thumbCV reloadData]; }];
    [self refreshSelectionUI];
}

- (void)refreshSelectionUI {
    UIColor *blue = [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];
    UIColor *grayBorder = [UIColor colorWithRed:0x66/255.0 green:0x66/255.0 blue:0x66/255.0 alpha:1.0];

    BOOL all = [self isAllCleanablesSelected];

    [UIView performWithoutAnimation:^{
        if (all) {
            [self.selectAllBtn setTitle:NSLocalizedString(@"Deselect All", nil) forState:UIControlStateNormal];
            [self.selectAllBtn setTitleColor:blue forState:UIControlStateNormal];
            [self.selectAllBtn setTitleColor:blue forState:UIControlStateHighlighted];
            self.selectAllBtn.layer.borderColor = blue.CGColor;
        } else {
            [self.selectAllBtn setTitle:NSLocalizedString(@"Select All", nil) forState:UIControlStateNormal];
            [self.selectAllBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
            [self.selectAllBtn setTitleColor:UIColor.blackColor forState:UIControlStateHighlighted];
            self.selectAllBtn.layer.borderColor = grayBorder.CGColor;
        }
    }];

    [UIView performWithoutAnimation:^{
        for (ASVideoGroupThumbCell *c in self.thumbCV.visibleCells) {
            NSIndexPath *ip = [self.thumbCV indexPathForCell:c];
            if (!ip || ip.item >= (NSInteger)self.models.count) continue;
            ASAssetModel *m = self.models[ip.item];
            NSString *lid = m.localId ?: @"";
            [c applyBest:(ip.item == 0)];
            [c applySelected:(lid.length && [self.selectedIds containsObject:lid])];
        }
    }];
}


- (void)onTapSelectAllBtn {
    if (self.onTapSelectAll) self.onTapSelectAll(self.sectionIndex);
}

#pragma mark - thumb cv
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.models.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ASVideoGroupThumbCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ASVideoGroupThumbCell" forIndexPath:indexPath];

    ASAssetModel *m = self.models[indexPath.item];
    NSString *lid = m.localId ?: @"";
    cell.representedLocalId = lid;
    cell.coverView.image = nil;

    BOOL isBest = (indexPath.item == 0);
    [cell applyBest:isBest];
    [cell applySelected:(lid.length && [self.selectedIds containsObject:lid])];

    PHAsset *a = (lid.length ? self.assetById[lid] : nil);
    cell.infoLabel.text = [NSString stringWithFormat:@"%@\n%@", ASHumanSize(m.fileSizeBytes), (a ? ASDurationText(a.duration) : @"")];

    cell.previewBtn.tag = indexPath.item;
    [cell.previewBtn removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [cell.previewBtn addTarget:self action:@selector(onTapPreviewBtn:) forControlEvents:UIControlEventTouchUpInside];

    cell.selectBtn.tag = indexPath.item;
    [cell.selectBtn removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [cell.selectBtn addTarget:self action:@selector(onTapSelectBtn:) forControlEvents:UIControlEventTouchUpInside];

    if (!a || !self.imgMgr) return cell;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.synchronous = NO;

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize target = CGSizeMake(SW(120)*scale, SW(160)*scale);

    __weak typeof(cell) weakCell = cell;
    NSString *expect = lid;

    [self.imgMgr requestImageForAsset:a
                           targetSize:target
                          contentMode:PHImageContentModeAspectFill
                              options:opt
                        resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            ASVideoGroupThumbCell *c = weakCell;
            if (!c) return;
            if (![c.representedLocalId isEqualToString:expect]) return;
            c.coverView.image = result;
        });
    }];

    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(SW(120), SW(160));
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsZero;
}

- (void)onTapSelectBtn:(UIButton *)btn {
    NSInteger idx = btn.tag;
    if (self.onToggleIndex) self.onToggleIndex(self.sectionIndex, idx);
}
- (void)onTapPreviewBtn:(UIButton *)btn {
    NSInteger idx = btn.tag;
    if (self.onPreviewIndex) self.onPreviewIndex(self.sectionIndex, idx);
}
@end


#pragma mark - Section model
@interface ASNoHighlightButton : UIButton
@end
@implementation ASNoHighlightButton
- (void)setHighlighted:(BOOL)highlighted { /* no-op */ }
@end
static inline void ASNoAnim(dispatch_block_t block) {
    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (block) block();
        [CATransaction commit];
    }];
}

@interface ASAssetSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSMutableArray<ASAssetModel *> *assets;
@property (nonatomic, strong) NSDate *groupDate; // 组排序
@property (nonatomic) BOOL isGrouped; // 相似/重复的那种分组 section
@end
@implementation ASAssetSection @end

#pragma mark - Cell

@interface ASAssetGridCell : UICollectionViewCell
@property (nonatomic, copy) NSString *representedLocalId;
@property (nonatomic, strong) UIImageView *img;
@property (nonatomic, strong) UILabel *badge;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UIImageView *selectIcon;
@property (nonatomic, strong) UIButton *selectBtn;
- (void)applySelected:(BOOL)sel;
@end

@implementation ASAssetGridCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (self=[super initWithFrame:frame]) {
        self.contentView.backgroundColor = UIColor.clearColor;
        self.contentView.layer.cornerRadius = 0;
        self.contentView.clipsToBounds = YES;

        _img = [UIImageView new];
        _img.contentMode = UIViewContentModeScaleAspectFill;
        _img.clipsToBounds = YES;

        _badge = [UILabel new];
        _badge.hidden = YES;

        _sizeLabel = [UILabel new];
        _sizeLabel.hidden = YES;

        _selectIcon = [UIImageView new];
        _selectIcon.contentMode = UIViewContentModeScaleAspectFit;

        _selectBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _selectBtn.backgroundColor = UIColor.clearColor;
        _selectBtn.adjustsImageWhenHighlighted = NO;
        _selectBtn.showsTouchWhenHighlighted = NO;
        _selectBtn.exclusiveTouch = YES;
        _selectBtn.userInteractionEnabled = YES;

        [self.contentView addSubview:_img];
        [self.contentView addSubview:_badge];
        [self.contentView addSubview:_sizeLabel];
        [self.contentView addSubview:_selectIcon];
        [self.contentView addSubview:_selectBtn];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.img.frame = self.contentView.bounds;

    CGFloat pad = SW(10);
    CGFloat s = SW(24);
    self.selectIcon.frame = CGRectMake(self.contentView.bounds.size.width - pad - s, pad, s, s);
    self.selectBtn.frame = CGRectInset(self.selectIcon.frame, -SW(8), -SW(8));
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedLocalId = @"";
    self.img.image = nil;
    self.badge.text = @"";
    self.sizeLabel.text = @"";
    self.selectIcon.image = nil;
    [self applySelected:NO];
}

- (void)applySelected:(BOOL)sel {
    self.selectIcon.image = [UIImage imageNamed:(sel ? @"ic_select_s" : @"ic_select_n")];
}

@end


#pragma mark - Section header

@interface ASAssetSectionHeader : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *selectAllBtn;
@property (nonatomic, copy) void (^tapSelectAll)(void);
@end

@implementation ASAssetSectionHeader
- (instancetype)initWithFrame:(CGRect)frame {
    if (self=[super initWithFrame:frame]) {

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont boldSystemFontOfSize:SW(15)];

        _selectAllBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _selectAllBtn.adjustsImageWhenHighlighted = NO;
        _selectAllBtn.showsTouchWhenHighlighted = NO;
        _selectAllBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [_selectAllBtn setTitle:NSLocalizedString(@"Select All", nil) forState:UIControlStateNormal];
        [_selectAllBtn addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];

        [self addSubview:_titleLabel];
        [self addSubview:_selectAllBtn];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat pad = SW(10);
    self.titleLabel.frame = CGRectMake(pad, 0, self.bounds.size.width - pad*2 - SW(80), self.bounds.size.height);
    self.selectAllBtn.frame = CGRectMake(self.bounds.size.width - pad - SW(80), 0, SW(80), self.bounds.size.height);
}
- (void)onTap { if (self.tapSelectAll) self.tapSelectAll(); }
@end

#pragma mark - Group Card Thumb Cell

@interface ASGroupThumbCell : UICollectionViewCell
@property (nonatomic, copy) NSString *representedLocalId;
@property (nonatomic, strong) UIImageView *imgView;
@property (nonatomic, strong) UIImageView *checkView;
@property (nonatomic, strong) UIButton *checkBtn;
@property (nonatomic, strong) UIButton *previewBtn;
@property (nonatomic, strong) UIImageView *bestBadge;
- (void)applySelected:(BOOL)sel;
- (void)applyBest:(BOOL)isBest;
@end

@implementation ASGroupThumbCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {

        _imgView = [UIImageView new];
        _imgView.contentMode = UIViewContentModeScaleAspectFill;
        _imgView.clipsToBounds = YES;
        _imgView.layer.cornerRadius = SW(20);
        _imgView.layer.borderWidth = SW(1);
        _imgView.layer.borderColor = UIColor.whiteColor.CGColor;

        _previewBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _previewBtn.backgroundColor = UIColor.clearColor;

        _checkView = [UIImageView new];
        _checkView.contentMode = UIViewContentModeScaleAspectFit;

        _checkBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _checkBtn.backgroundColor = UIColor.clearColor;

        _bestBadge = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_best"]];
        _bestBadge.contentMode = UIViewContentModeScaleAspectFit;
        _bestBadge.hidden = YES;

        [self.contentView addSubview:_imgView];
        [self.contentView addSubview:_previewBtn];
        [self.contentView addSubview:_bestBadge];
        [self.contentView addSubview:_checkView];
        [self.contentView addSubview:_checkBtn];

        self.contentView.backgroundColor = UIColor.clearColor;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.imgView.frame = self.contentView.bounds;
    self.previewBtn.frame = self.contentView.bounds;

    CGFloat s = SW(12);
    self.checkView.frame = CGRectMake(self.contentView.bounds.size.width - s,
                                      0,
                                      s, s);
    self.checkBtn.frame = CGRectInset(self.checkView.frame, -SW(8), -SW(8));

    CGFloat bw = SW(34), bh = SW(14);
    self.bestBadge.frame = CGRectMake((self.contentView.bounds.size.width - bw)/2.0,
                                      self.contentView.bounds.size.height - bh + SW(2),
                                      bw, bh);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedLocalId = @"";
    self.imgView.image = nil;
    self.bestBadge.hidden = YES;
    self.checkView.hidden = NO;
    self.checkBtn.hidden = NO;
}

- (void)applyBest:(BOOL)isBest {
    self.bestBadge.hidden = !isBest;
}

- (void)applySelected:(BOOL)sel {
    UIImage *img = [UIImage imageNamed:(sel ? @"ic_select_s" : @"ic_small_select_n")];
    self.checkView.image = img;
}
@end

#pragma mark - Group Card Cell

@interface ASAssetGroupCardCell : UICollectionViewCell <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic) NSInteger sectionIndex;

@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIView *leftPanel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UIButton *selectAllBtn;

@property (nonatomic, strong) UIView *rightPanel;
@property (nonatomic, strong) UIImageView *bestBg;
@property (nonatomic, strong) UICollectionView *thumbCV;

@property (nonatomic, strong) NSArray<ASAssetModel *> *models;
@property (nonatomic, strong) NSDictionary<NSString*, PHAsset*> *assetById;
@property (nonatomic, strong) PHCachingImageManager *imgMgr;
@property (nonatomic, strong) NSSet<NSString*> *selectedIds;
@property (nonatomic, copy) NSString *unitText;

@property (nonatomic, copy) void (^onTapSelectAll)(NSInteger sectionIndex);
@property (nonatomic, copy) void (^onToggleIndex)(NSInteger sectionIndex, NSInteger modelIndex);
@property (nonatomic, copy) void (^onPreviewIndex)(NSInteger sectionIndex, NSInteger modelIndex);

@property (nonatomic) CGFloat cachedLeftW;
@property (nonatomic) CGFloat fixedLeftW;

@property (nonatomic, copy) NSString *representedBestId;
@property (nonatomic) CGSize lastBestTarget;

- (void)bindModels:(NSArray<ASAssetModel *> *)models
      sectionIndex:(NSInteger)sectionIndex
          unitText:(NSString *)unitText
        selectedIds:(NSSet<NSString*> *)selectedIds
         assetById:(NSDictionary<NSString*, PHAsset*> *)assetById
            imgMgr:(PHCachingImageManager *)imgMgr
        fixedLeftW:(CGFloat)fixedLeftW;

- (void)refreshSelectionUI;
@end

@implementation ASAssetGroupCardCell

- (BOOL)collectionView:(UICollectionView *)collectionView shouldHighlightItemAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (CGFloat)as_textWidth:(NSString *)t font:(UIFont *)f {
    if (t.length == 0) return 0;
    return ceil([t boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, SW(100))
                                options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
                             attributes:@{NSFontAttributeName:f}
                                context:nil].size.width);
}

- (void)updateCachedLeftWidth {
    CGFloat pad = SW(14);

    CGFloat wCount = [self as_textWidth:self.countLabel.text font:self.countLabel.font];
    CGFloat wSize  = [self as_textWidth:self.sizeLabel.text  font:self.sizeLabel.font];

    CGFloat wT1 = [self as_textWidth:NSLocalizedString(@"Select All", nil)   font:self.selectAllBtn.titleLabel.font];
    CGFloat wT2 = [self as_textWidth:NSLocalizedString(@"Deselect All", nil) font:self.selectAllBtn.titleLabel.font];
    CGFloat wTitleMax = MAX(wT1, wT2);

    UIEdgeInsets in = self.selectAllBtn.contentEdgeInsets;
    CGFloat wBtn = wTitleMax + in.left + in.right;

    CGFloat contentW = MAX(MAX(wCount, wSize), wBtn);
    CGFloat leftW = contentW + pad * 2;

    self.cachedLeftW = MIN(SW(180), MAX(SW(110), leftW));
}

- (void)refreshVisibleThumbSelectionOnly {
    ASNoAnim(^{
        for (ASGroupThumbCell *c in self.thumbCV.visibleCells) {
            NSIndexPath *ip = [self.thumbCV indexPathForCell:c];
            if (!ip) continue;
            if (ip.item < 0 || ip.item >= (NSInteger)self.models.count) continue;

            ASAssetModel *m = self.models[ip.item];
            NSString *lid = m.localId ?: @"";

            [c applyBest:(ip.item == 0)];

            BOOL sel = (lid.length && [self.selectedIds containsObject:lid]);
            [c applySelected:sel];
        }
    });
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self=[super initWithFrame:frame]) {

        _card = [UIView new];
        _card.backgroundColor = UIColor.whiteColor;
        _card.layer.cornerRadius = SW(22);
        _card.clipsToBounds = YES;

        _leftPanel = [UIView new];
        _leftPanel.backgroundColor = UIColor.whiteColor;

        _countLabel = [UILabel new];
        _countLabel.font = SWFontS(20, UIFontWeightMedium);
        _countLabel.textColor = UIColor.blackColor;

        _sizeLabel = [UILabel new];
        _sizeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _sizeLabel.textColor = [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];

        _selectAllBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _selectAllBtn.adjustsImageWhenHighlighted = NO;
        _selectAllBtn.titleLabel.font = SWFontS(13, UIFontWeightMedium);
        _selectAllBtn.backgroundColor = UIColor.clearColor;
        _selectAllBtn.layer.cornerRadius = SW(18);
        _selectAllBtn.layer.borderWidth = SW(1);
        _selectAllBtn.contentEdgeInsets = SWInsets(8, 8, 8, 8);
        _selectAllBtn.titleLabel.lineBreakMode = NSLineBreakByClipping;
        _selectAllBtn.titleLabel.adjustsFontSizeToFitWidth = NO;
        _selectAllBtn.titleLabel.minimumScaleFactor = 1.0;
        [_selectAllBtn addTarget:self action:@selector(onTapSelectAllBtn) forControlEvents:UIControlEventTouchUpInside];

        [_leftPanel addSubview:_countLabel];
        [_leftPanel addSubview:_sizeLabel];
        [_leftPanel addSubview:_selectAllBtn];

        _rightPanel = [UIView new];
        _rightPanel.backgroundColor = UIColor.clearColor;

        _bestBg = [UIImageView new];
        _bestBg.contentMode = UIViewContentModeScaleAspectFill;
        _bestBg.clipsToBounds = YES;

        UICollectionViewFlowLayout *l = [UICollectionViewFlowLayout new];
        l.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        l.minimumLineSpacing = SW(10);
        l.minimumInteritemSpacing = SW(10);

        _thumbCV = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:l];
        _thumbCV.backgroundColor = UIColor.clearColor;
        _thumbCV.showsHorizontalScrollIndicator = NO;
        _thumbCV.delaysContentTouches = NO;
        _thumbCV.canCancelContentTouches = YES;
        _thumbCV.dataSource = self;
        _thumbCV.delegate = self;
        _thumbCV.allowsSelection = NO;
        [_thumbCV registerClass:ASGroupThumbCell.class forCellWithReuseIdentifier:@"ASGroupThumbCell"];

        [_rightPanel addSubview:_bestBg];
        [_rightPanel addSubview:_thumbCV];

        [_card addSubview:_leftPanel];
        [_card addSubview:_rightPanel];
        [self.contentView addSubview:_card];

        self.contentView.backgroundColor = UIColor.clearColor;
        _lastBestTarget = CGSizeZero;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.card.frame = self.contentView.bounds;

    CGFloat leftW = (self.fixedLeftW > 0 ? self.fixedLeftW
                    : (self.cachedLeftW > 0 ? self.cachedLeftW : SW(120)));

    self.leftPanel.frame  = CGRectMake(0, 0, leftW, self.card.bounds.size.height);
    self.rightPanel.frame = CGRectMake(leftW, 0, self.card.bounds.size.width - leftW, self.card.bounds.size.height);

    CGFloat pad = SW(14);
    CGFloat topY = SW(18);
    CGFloat lineGap = SW(2);

    CGFloat y = topY;
    self.countLabel.frame = CGRectMake(pad, y, leftW - pad*2, SW(26));
    y += SW(26) + lineGap;
    self.sizeLabel.frame  = CGRectMake(pad, y, leftW - pad*2, SW(16));

    NSString *t1 = NSLocalizedString(@"Select All", nil);
    NSString *t2 = NSLocalizedString(@"Deselect All", nil);
    CGFloat wT = MAX([self as_textWidth:t1 font:self.selectAllBtn.titleLabel.font],
                     [self as_textWidth:t2 font:self.selectAllBtn.titleLabel.font]);
    UIEdgeInsets in = self.selectAllBtn.contentEdgeInsets;
    CGFloat pillW = ceil(wT + in.left + in.right);
    pillW = MIN(pillW, leftW - pad*2);

    CGFloat btnH = SW(36);
    CGFloat btnY = self.card.bounds.size.height - SW(18) - btnH;
    CGFloat btnX = floor((leftW - pillW)/2.0);
    self.selectAllBtn.frame = CGRectMake(btnX, btnY, pillW, btnH);

    self.bestBg.frame = self.rightPanel.bounds;

    CGFloat listH = SW(56);
    self.thumbCV.frame = CGRectMake(0,
                                    self.rightPanel.bounds.size.height - listH - SW(10),
                                    self.rightPanel.bounds.size.width,
                                    listH);

    [self reloadBestBgIfNeeded];
}

- (void)reloadBestBgIfNeeded {
    if (!self.imgMgr) return;
    if (self.representedBestId.length == 0) return;

    PHAsset *a = self.assetById[self.representedBestId];
    if (!a) return;

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize sz = self.rightPanel.bounds.size;
    if (sz.width < 2 || sz.height < 2) return;

    CGSize target = CGSizeMake(sz.width * scale, sz.height * scale);
    if (CGSizeEqualToSize(target, self.lastBestTarget) && self.bestBg.image != nil) return;

    self.lastBestTarget = target;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.synchronous = NO;

    __weak typeof(self) weakSelf = self;
    NSString *expect = self.representedBestId;

    [self.imgMgr requestImageForAsset:a
                           targetSize:target
                          contentMode:PHImageContentModeAspectFill
                              options:opt
                        resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![weakSelf.representedBestId isEqualToString:expect]) return;
            weakSelf.bestBg.image = result;
        });
    }];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedBestId = @"";
    self.bestBg.image = nil;
    self.models = @[];
    self.selectedIds = [NSSet set];
    self.assetById = @{};
    self.imgMgr = nil;
    self.fixedLeftW = 0;
    self.cachedLeftW = 0;
    self.lastBestTarget = CGSizeZero;
    [self.thumbCV reloadData];
}

- (uint64_t)cleanableBytes {
    uint64_t s = 0;
    for (NSInteger i = 1; i < (NSInteger)self.models.count; i++) {
        s += self.models[i].fileSizeBytes;
    }
    return s;
}

- (BOOL)isAllCleanablesSelected {
    if (self.models.count == 0) return NO;
    for (NSInteger i=1; i<(NSInteger)self.models.count; i++) {
        NSString *lid = self.models[i].localId ?: @"";
        if (lid.length && ![self.selectedIds containsObject:lid]) return NO;
    }
    return YES;
}

- (void)refreshSelectionUI {
    BOOL all = [self isAllCleanablesSelected];

    ASNoAnim(^{
        if (all) {
            [self.selectAllBtn setTitle:NSLocalizedString(@"Deselect All", nil) forState:UIControlStateNormal];
            UIColor *blue = [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];
            [self.selectAllBtn setTitleColor:blue forState:UIControlStateNormal];
            self.selectAllBtn.layer.borderColor = blue.CGColor;
        } else {
            [self.selectAllBtn setTitle:NSLocalizedString(@"Select All", nil) forState:UIControlStateNormal];
            [self.selectAllBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
            self.selectAllBtn.layer.borderColor = [UIColor colorWithRed:0x66/255.0 green:0x66/255.0 blue:0x66/255.0 alpha:1.0].CGColor;
        }
        [self setNeedsLayout];
        [self layoutIfNeeded];
    });

    [self refreshVisibleThumbSelectionOnly];
}

- (void)bindModels:(NSArray<ASAssetModel *> *)models
      sectionIndex:(NSInteger)sectionIndex
          unitText:(NSString *)unitText
        selectedIds:(NSSet<NSString*> *)selectedIds
         assetById:(NSDictionary<NSString*, PHAsset*> *)assetById
            imgMgr:(PHCachingImageManager *)imgMgr
        fixedLeftW:(CGFloat)fixedLeftW {

    self.sectionIndex = sectionIndex;
    self.models = models ?: @[];
    self.unitText = unitText ?: NSLocalizedString(@"Photos", nil);
    self.selectedIds = selectedIds ?: [NSSet set];
    self.assetById = assetById ?: @{};
    self.imgMgr = imgMgr;
    self.fixedLeftW = fixedLeftW;

    self.countLabel.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)self.models.count, self.unitText];
    self.sizeLabel.text  = ASHumanSize([self cleanableBytes]);

    [self updateCachedLeftWidth];

    ASAssetModel *best = (self.models.count > 0 ? self.models[0] : nil);
    self.representedBestId = best.localId ?: @"";
    self.bestBg.image = nil;
    self.lastBestTarget = CGSizeZero;

    ASNoAnim(^{
        [self.thumbCV reloadData];
    });

    [self refreshSelectionUI];
}

- (void)onTapSelectAllBtn {
    if (self.onTapSelectAll) self.onTapSelectAll(self.sectionIndex);
}

#pragma mark - thumb cv

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.models.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ASGroupThumbCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ASGroupThumbCell" forIndexPath:indexPath];

    ASAssetModel *m = self.models[indexPath.item];
    NSString *lid = m.localId ?: @"";
    cell.representedLocalId = lid;
    cell.imgView.image = nil;

    BOOL isBest = (indexPath.item == 0);
    [cell applyBest:isBest];

    BOOL sel = (lid.length && [self.selectedIds containsObject:lid]);
    [cell applySelected:sel];

    // actions
    cell.previewBtn.tag = indexPath.item;
    [cell.previewBtn removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [cell.previewBtn addTarget:self action:@selector(onTapPreviewBtn:) forControlEvents:UIControlEventTouchUpInside];

    cell.checkBtn.tag = indexPath.item;
    [cell.checkBtn removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [cell.checkBtn addTarget:self action:@selector(onTapCheckBtn:) forControlEvents:UIControlEventTouchUpInside];

    // image load
    PHAsset *a = (lid.length ? self.assetById[lid] : nil);
    if (!a || !self.imgMgr) return cell;

    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    opt.resizeMode = PHImageRequestOptionsResizeModeFast;
    opt.synchronous = NO;

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize target = CGSizeMake(SW(40) * scale, SW(40) * scale);

    __weak typeof(cell) weakCell = cell;
    NSString *expect = lid;

    [self.imgMgr requestImageForAsset:a
                           targetSize:target
                          contentMode:PHImageContentModeAspectFill
                              options:opt
                        resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            ASGroupThumbCell *c = weakCell;
            if (!c) return;
            if (![c.representedLocalId isEqualToString:expect]) return;
            c.imgView.image = result;
        });
    }];

    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(SW(40), SW(40));
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsMake(SW(8), SW(14), SW(8), SW(14));
}

- (void)onTapCheckBtn:(UIButton *)btn {
    NSInteger idx = btn.tag;
    if (idx < 0 || idx >= (NSInteger)self.models.count) return;
    if (self.onToggleIndex) self.onToggleIndex(self.sectionIndex, idx);
}


- (void)onTapPreviewBtn:(UIButton *)btn {
    NSInteger idx = btn.tag;
    if (idx < 0 || idx >= (NSInteger)self.models.count) return;

    if (self.onToggleIndex) self.onToggleIndex(self.sectionIndex, idx);
}
@end

static inline CGFloat ASTextW(NSString *t, UIFont *f) {
    if (t.length == 0) return 0;
    return ceil([t boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, SW(100))
                                options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
                             attributes:@{NSFontAttributeName:f}
                                context:nil].size.width);
}

static inline CGFloat ASPillW(NSString *title, UIFont *font, CGFloat imgW, CGFloat spacing, UIEdgeInsets insets) {
    return insets.left + imgW + (title.length ? spacing : 0) + ASTextW(title, font) + insets.right;
}

#pragma mark - VC

@interface ASAssetListViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UIView *as_sortMask;
@property (nonatomic, strong) UIView *as_sortSheet;
@property (nonatomic, assign) ASAssetSortMode as_pendingSortMode;
@property (nonatomic, strong) NSMutableDictionary<NSNumber*, UIImageView*> *as_sortCheckByMode;
@property (nonatomic) ASAssetSortMode sortMode;
@property (nonatomic, strong) CAGradientLayer *topGradient;
@property (nonatomic, strong) UIView *listBgView;
@property (nonatomic, strong) UILabel *topSummaryLabel;
@property (nonatomic, strong) UIButton *topSelectAllBtn;
@property (nonatomic, strong) UIButton *topSortBtn;
@property (nonatomic) CGFloat groupCardLeftW;

@property (nonatomic) NSUInteger totalItemCount;      // 当前列表总数
@property (nonatomic) NSUInteger cleanableItemCount;  // 当前“可清理”数量（分组模式会排除每组第1张）

@property (nonatomic, strong) ASCustomNavBar *navBar;
@property (nonatomic, strong) UIView *topToolbar;

@property (nonatomic) ASAssetListMode mode;

@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *totalLabel;
@property (nonatomic, strong) UIButton *deleteBtn;
@property (nonatomic) CGFloat bottomBarH;

@property (nonatomic, strong) PHCachingImageManager *imgMgr;
@property (nonatomic, strong) ASPhotoScanManager *scanMgr;

@property (nonatomic, strong) NSMutableArray<ASAssetSection *> *sections;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedIds;

@property (nonatomic) uint64_t totalCleanableBytes;
@property (nonatomic) uint64_t selectedBytes;

@property (nonatomic, strong) NSDictionary<NSString*, PHAsset*> *assetById;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UILabel *emptyLabel;

@end

@implementation ASAssetListViewController

- (CGFloat)measurePillWidthWithTitle:(NSString *)title imageName:(NSString *)imgName height:(CGFloat)h {
    UIButton *tmp = [UIButton buttonWithType:UIButtonTypeSystem];
    [self configPillButtonBase:tmp];

    UIImage *img = [[UIImage imageNamed:imgName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [tmp setImage:img forState:UIControlStateNormal];
    [tmp setTitle:title forState:UIControlStateNormal];

    CGSize s = [tmp sizeThatFits:CGSizeMake(CGFLOAT_MAX, h)];
    return ceil(s.width);
}

- (void)as_noAnim:(dispatch_block_t)block {
    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (block) block();
        [CATransaction commit];
    }];
}

- (BOOL)useVideoGroupStyle {
    return (self.mode == ASAssetListModeSimilarVideo ||
            self.mode == ASAssetListModeDuplicateVideo);
}

- (instancetype)initWithMode:(ASAssetListMode)mode {
    if (self=[super init]) {
        _sortMode = ASAssetSortModeNewest;
        _mode = mode;
        _sections = [NSMutableArray array];
        _selectedIds = [NSMutableSet set];
        _assetById = @{};
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 隐藏系统的导航栏
    self.navigationController.navigationBar.hidden = YES;
}

- (void)recomputeGroupCardLeftWidth {
    if (![self isGroupMode]) { self.groupCardLeftW = 0; return; }

    UIFont *countFont = SWFontS(20, UIFontWeightMedium);
    UIFont *sizeFont  = SWFontS(12, UIFontWeightSemibold);
    UIFont *btnFont   = SWFontS(13, UIFontWeightMedium);

    NSString *unit = [self isVideoMode] ? NSLocalizedString(@"Videos", nil) : NSLocalizedString(@"Photos", nil);

    CGFloat sidePad = SW(14);

    UIEdgeInsets btnInsets = SWInsets(8, 8, 8, 8);
    CGFloat btnImgW = 0;
    CGFloat btnSpacing = 0;

    CGFloat btnWMax = MAX(ASPillW(NSLocalizedString(@"Select All", nil), btnFont, btnImgW, btnSpacing, btnInsets),
                          ASPillW(NSLocalizedString(@"Deselect All", nil), btnFont, btnImgW, btnSpacing, btnInsets));

    CGFloat maxContentW = 0;

    for (ASAssetSection *sec in self.sections) {
        NSString *countText = [NSString stringWithFormat:@"%lu %@", (unsigned long)sec.assets.count, unit];
        NSString *sizeText  = ASHumanSize([self cleanableBytesForSection:sec]);

        CGFloat w1 = ASTextW(countText, countFont);
        CGFloat w2 = ASTextW(sizeText,  sizeFont);

        CGFloat contentW = MAX(MAX(w1, w2), btnWMax);
        if (contentW > maxContentW) maxContentW = contentW;
    }

    CGFloat leftW = maxContentW + sidePad * 2;

    self.groupCardLeftW = MIN(SW(180), MAX(SW(110), leftW));
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:246/255.0 green:246/255.0 blue:246/255.0 alpha:1.0];
    self.topGradient = [CAGradientLayer layer];
    self.topGradient.startPoint = CGPointMake(0.5, 0.0);
    self.topGradient.endPoint   = CGPointMake(0.5, 1.0);

    UIColor *c1 = [UIColor colorWithRed:224/255.0 green:224/255.0 blue:224/255.0 alpha:1.0];
    UIColor *c2 = [UIColor colorWithRed:0/255.0   green:141/255.0 blue:255/255.0 alpha:0.0];

    self.topGradient.colors = @[ (id)c1.CGColor, (id)c2.CGColor ];
    [self.view.layer insertSublayer:self.topGradient atIndex:0];

    self.navigationController.navigationBarHidden = YES;

    // 外部 title 统一从 mode 计算
    NSString *title = [self titleForMode:self.mode];
    self.navBar = [[ASCustomNavBar alloc] initWithTitle:title];
    __weak typeof(self) weakSelf = self;
    self.navBar.onBack = ^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };

    [self.view addSubview:self.navBar];

    [self setupTopToolbar];

    self.imgMgr = [PHCachingImageManager new];
    self.scanMgr = [ASPhotoScanManager shared];

    [self setupUI];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self rebuildDataFromManager];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyDefaultSelectionRule];
            [self recomputeGroupCardLeftWidth];
            [self applyCurrentSortAndReload];
//            [self.cv reloadData];
            [self recomputeBytesAndRefreshUI];
            [self syncNavSelectAllState];
            [self updateEmptyState];
        });
    });
}

#pragma mark - 自定义布局调整

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat gradientH = 0 + SW(402.0);
    self.topGradient.frame = CGRectMake(0, 0, w, gradientH);

    CGFloat topSafe = self.view.safeAreaInsets.top;
    CGFloat bottomSafe = self.view.safeAreaInsets.bottom;

    CGFloat navH = SW(44) + topSafe;
    CGFloat toolbarH = SW(88);
    CGFloat floatBtnH = SW(70);
    CGFloat floatBtnX = SW(15);
    CGFloat floatBtnW = self.view.bounds.size.width - SW(30);

    self.navBar.frame = CGRectMake(0, 0, self.view.bounds.size.width, navH);

    self.topToolbar.frame = CGRectMake(0, navH, self.view.bounds.size.width, toolbarH);

    CGFloat pad = SW(16);
    self.topSummaryLabel.frame = CGRectMake(pad, 0, self.topToolbar.bounds.size.width - pad*2, SW(44));

    CGFloat rowY = SW(44) + (SW(44) - SW(36))/2.0;
    CGFloat btnH = SW(40);
    CGFloat gap = SW(10);

    CGFloat w1 = [self pillWidthForButton:self.topSelectAllBtn height:btnH];
    CGFloat w2 = [self pillWidthForButton:self.topSortBtn height:btnH];

    w1 = MAX(SW(96), w1);
    w2 = MAX(SW(96), w2);

    CGFloat maxTotal = self.topToolbar.bounds.size.width - pad*2;
    CGFloat totalNeed = w1 + gap + w2;

    if (totalNeed > maxTotal) {
        CGFloat minGap = SW(6);
        gap = MAX(minGap, gap - (totalNeed - maxTotal));
        totalNeed = w1 + gap + w2;

        if (totalNeed > maxTotal) {
            self.topSelectAllBtn.titleLabel.adjustsFontSizeToFitWidth = YES;
            self.topSelectAllBtn.titleLabel.minimumScaleFactor = 0.75;

            self.topSortBtn.titleLabel.adjustsFontSizeToFitWidth = YES;
            self.topSortBtn.titleLabel.minimumScaleFactor = 0.75;

            CGFloat remain = maxTotal - gap;
            CGFloat w2Max = MIN(w2, remain * 0.5);
            CGFloat w1Max = remain - w2Max;

            w1 = MIN(w1, w1Max);
            w2 = MIN(w2, w2Max);
        }
    }

    self.topSelectAllBtn.frame = CGRectMake(pad, rowY, w1, btnH);
    self.topSortBtn.frame = CGRectMake(self.topToolbar.bounds.size.width - pad - w2, rowY, w2, btnH);

    CGFloat cvY = navH + toolbarH + SW(10); // Added 10pt gap
    CGRect listFrame = CGRectMake(0,
                                  cvY,
                                  self.view.bounds.size.width,
                                  self.view.bounds.size.height - cvY);

    if ([self isGroupMode]) {
        self.cv.frame = listFrame;
    } else {
        self.listBgView.frame = listFrame;
        self.cv.frame = self.listBgView.bounds;
    }

    CGRect hostRect = CGRectZero;
    if ([self isGroupMode]) {
        hostRect = self.cv.frame;
    } else {
        hostRect = self.listBgView.frame;
    }

    self.emptyView.frame = hostRect;

    CGFloat labelH = ceil(self.emptyLabel.font.lineHeight);
    CGFloat labelW = MIN(hostRect.size.width - SW(40), SW(320));
    self.emptyLabel.frame = CGRectMake((hostRect.size.width - labelW) / 2.0,
                                      (hostRect.size.height - labelH) / 2.0,
                                      labelW,
                                      labelH);

    if (!self.bottomBar.superview) [self.view addSubview:self.bottomBar];

    CGFloat floatBtnY = self.view.bounds.size.height - bottomSafe - floatBtnH;

    self.bottomBar.frame = CGRectMake(floatBtnX, floatBtnY, floatBtnW, floatBtnH);
    self.deleteBtn.frame = self.bottomBar.bounds;

    CGFloat insetBottom = bottomSafe + (self.deleteBtn.hidden ? 0 : floatBtnH);
    self.cv.contentInset = UIEdgeInsetsMake(0, 0, insetBottom, 0);
    self.cv.scrollIndicatorInsets = self.cv.contentInset;
    
    [self.view bringSubviewToFront:self.navBar];
    [self.view bringSubviewToFront:self.topToolbar];
    [self.view bringSubviewToFront:self.bottomBar];
}

- (void)syncNavSelectAllState {
    NSMutableSet<NSString *> *shouldAll = [NSMutableSet set];

    if ([self isGroupMode]) {
        for (ASAssetSection *sec in self.sections)
            for (NSInteger i = 1; i < sec.assets.count; i++)
                [shouldAll addObject:sec.assets[i].localId];
    } else {
        for (ASAssetSection *sec in self.sections)
            for (ASAssetModel *m in sec.assets)
                [shouldAll addObject:m.localId];
    }

    BOOL all = shouldAll.count > 0;
    for (NSString *lid in shouldAll) {
        if (![self.selectedIds containsObject:lid]) {
            all = NO;
            break;
        }
    }

    self.navBar.allSelected = all;
    [self updateTopSelectAllButtonUIWithAll:all];
}

- (void)setupTopToolbar {
    self.topToolbar = [[UIView alloc] initWithFrame:CGRectZero];

    UILabel *summary = [UILabel new];
    summary.textAlignment = NSTextAlignmentCenter;
    summary.numberOfLines = 1;
    summary.adjustsFontSizeToFitWidth = YES;
    summary.minimumScaleFactor = 0.8;
    summary.font = SWFontS(16, UIFontWeightMedium);
    self.topSummaryLabel = summary;

    ASNoHighlightButton *selectAllBtn = [ASNoHighlightButton buttonWithType:UIButtonTypeCustom];
    [self configPillButtonBase:selectAllBtn];
    [selectAllBtn addTarget:self action:@selector(toggleSelectAll) forControlEvents:UIControlEventTouchUpInside];
    self.topSelectAllBtn = selectAllBtn;

    ASNoHighlightButton *sortBtn = [ASNoHighlightButton buttonWithType:UIButtonTypeCustom];
    [self configPillButtonBase:sortBtn];
    [sortBtn addTarget:self action:@selector(onTapSort) forControlEvents:UIControlEventTouchUpInside];
    self.topSortBtn = sortBtn;

    [self updateTopSortButtonUI];
    [self updateTopSelectAllButtonUIWithAll:NO];

    [self.topToolbar addSubview:summary];
    [self.topToolbar addSubview:selectAllBtn];
    [self.topToolbar addSubview:sortBtn];

    [self.view addSubview:self.topToolbar];
}

- (void)updatePillButton:(UIButton *)btn imageName:(NSString *)imgName title:(NSString *)title {
    UIImage *img = [[UIImage imageNamed:imgName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [self as_noAnim:^{
        [btn setImage:img forState:UIControlStateNormal];
        [btn setTitle:title forState:UIControlStateNormal];
        [btn invalidateIntrinsicContentSize];
    }];
    [self.view setNeedsLayout];
}

- (void)onTapSort {
    [self as_showSortSheet];
}

#pragma mark - Sort Sheet (custom)

- (void)as_hideSortSheet {
    if (!self.as_sortSheet) return;

    UIView *mask = self.as_sortMask;
    UIView *sheet = self.as_sortSheet;

    UIView *panel = [sheet viewWithTag:9001];
    [UIView animateWithDuration:0.18 animations:^{
        mask.alpha = 0.0;
        if (panel) {
            panel.alpha = 0.0;
            panel.transform = CGAffineTransformMakeTranslation(0, 10);
        } else {
            sheet.alpha = 0.0;
        }
    } completion:^(__unused BOOL finished) {
        [sheet removeFromSuperview];
        [mask removeFromSuperview];
        self.as_sortSheet = nil;
        self.as_sortMask = nil;
        self.as_sortCheckByMode = nil;
    }];
}

- (void)as_sortMaskTapped {
    [self as_hideSortSheet];
}

- (UIControl *)as_sortRowWithTitle:(NSString *)title mode:(ASAssetSortMode)mode {

    UIControl *row = [UIControl new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = ASHexRGBA(0xF6F6F6FF);
    row.layer.cornerRadius = SW(8);
    row.layer.masksToBounds = YES;
    row.tag = mode;

    [row addTarget:self action:@selector(as_sortRowTapped:) forControlEvents:UIControlEventTouchUpInside];

    UILabel *lab = [UILabel new];
    lab.translatesAutoresizingMaskIntoConstraints = NO;
    lab.text = title;
    lab.textColor = UIColor.blackColor;
    lab.font = SWFontS(17, UIFontWeightMedium);
    [row addSubview:lab];

    UIImageView *check = [UIImageView new];
    check.translatesAutoresizingMaskIntoConstraints = NO;
    check.contentMode = UIViewContentModeScaleAspectFit;
    check.image = [UIImage imageNamed:@"ic_checked"];
    [row addSubview:check];

    if (!self.as_sortCheckByMode) self.as_sortCheckByMode = [NSMutableDictionary dictionary];
    self.as_sortCheckByMode[@(mode)] = check;

    [NSLayoutConstraint activateConstraints:@[
        [lab.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:SW(20)],
        [lab.topAnchor constraintEqualToAnchor:row.topAnchor constant:SW(14)],
        [lab.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-SW(14)],
        [lab.trailingAnchor constraintLessThanOrEqualToAnchor:check.leadingAnchor constant:-SW(12)],

        [check.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-SW(20)],
        [check.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [check.widthAnchor constraintEqualToConstant:SW(24)],
        [check.heightAnchor constraintEqualToConstant:SW(24)],
    ]];

    return row;
}

- (void)as_applyPendingSortUI {
    for (NSNumber *k in self.as_sortCheckByMode.allKeys) {
        UIImageView *v = self.as_sortCheckByMode[k];
        v.hidden = (k.integerValue != self.as_pendingSortMode);
    }
}

- (void)as_sortRowTapped:(UIControl *)row {
    self.as_pendingSortMode = (ASAssetSortMode)row.tag;
    [self as_applyPendingSortUI];
}

- (void)as_sortConfirmTapped {
    self.sortMode = self.as_pendingSortMode;
    [self as_hideSortSheet];
    [self applyCurrentSortAndReload];
}

- (UIWindow *)as_keyWindow {
    UIWindow *w = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *win in ((UIWindowScene *)scene).windows) {
                if (win.isKeyWindow) { w = win; break; }
            }
            if (w) break;
        }
    }
    if (!w) w = UIApplication.sharedApplication.keyWindow;
    if (!w) w = UIApplication.sharedApplication.windows.firstObject;
    return w;
}

- (void)as_sortCancelTapped {
    [self as_hideSortSheet];
}

- (void)as_showSortSheet {

    if (self.as_sortSheet) { [self as_hideSortSheet]; return; }

    self.as_pendingSortMode = self.sortMode;

    UIWindow *host = [self as_keyWindow];
    if (!host) return;

    UIView *mask = [UIView new];
    mask.translatesAutoresizingMaskIntoConstraints = NO;
    mask.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
    mask.alpha = 0.0;
    [host addSubview:mask];

    [NSLayoutConstraint activateConstraints:@[
        [mask.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [mask.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [mask.topAnchor constraintEqualToAnchor:host.topAnchor],
        [mask.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
    ]];

    self.as_sortMask = mask;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(as_sortMaskTapped)];
    [mask addGestureRecognizer:tap];

    UIView *sheet = [UIView new];
    sheet.translatesAutoresizingMaskIntoConstraints = NO;
    sheet.backgroundColor = UIColor.clearColor;
    [host addSubview:sheet];

    [NSLayoutConstraint activateConstraints:@[
        [sheet.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [sheet.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [sheet.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
    ]];

    self.as_sortSheet = sheet;

    UILayoutGuide *safe = sheet.safeAreaLayoutGuide;

    UIView *panel = [UIView new];
    panel.tag = 9001;
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = UIColor.whiteColor;
    panel.layer.cornerRadius = SW(16);
    panel.layer.masksToBounds = YES;
    if (@available(iOS 11.0, *)) {
        panel.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    panel.alpha = 0.0;
    panel.transform = CGAffineTransformMakeTranslation(0, 10);
    [sheet addSubview:panel];

    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintEqualToAnchor:sheet.leadingAnchor],
        [panel.trailingAnchor constraintEqualToAnchor:sheet.trailingAnchor],
        [panel.topAnchor constraintEqualToAnchor:sheet.topAnchor],
        [panel.bottomAnchor constraintEqualToAnchor:sheet.bottomAnchor],
    ]];

    UIView *content = [UIView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:content];

    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:SW(20)],
        [content.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-SW(20)],

        [content.topAnchor constraintEqualToAnchor:safe.topAnchor constant:SW(20)],

        [content.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-SW(20)],
    ]];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = NSLocalizedString(@"Sort", nil);
    title.textColor = UIColor.blackColor;
    title.font = SWFontS(17, UIFontWeightMedium);
    title.textAlignment = NSTextAlignmentCenter;
    [content addSubview:title];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = SW(15);
    [content addSubview:stack];

    UIControl *r0 = [self as_sortRowWithTitle:NSLocalizedString(@"Newest", nil) mode:ASAssetSortModeNewest];
    UIControl *r1 = [self as_sortRowWithTitle:NSLocalizedString(@"Oldest", nil) mode:ASAssetSortModeOldest];
    UIControl *r2 = [self as_sortRowWithTitle:NSLocalizedString(@"Largest", nil) mode:ASAssetSortModeLargest];
    UIControl *r3 = [self as_sortRowWithTitle:NSLocalizedString(@"Smallest", nil) mode:ASAssetSortModeSmallest];

    [stack addArrangedSubview:r0];
    [stack addArrangedSubview:r1];
    [stack addArrangedSubview:r2];
    [stack addArrangedSubview:r3];

    UIButton *confirm = [UIButton buttonWithType:UIButtonTypeCustom];
    confirm.translatesAutoresizingMaskIntoConstraints = NO;
    confirm.backgroundColor = ASHexRGBA(0x024DFFFF);
    confirm.layer.cornerRadius = SW(26);
    confirm.layer.masksToBounds = YES;
    confirm.titleLabel.font = SWFontS(20, UIFontWeightRegular);
    [confirm setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [confirm setTitle:NSLocalizedString(@"Confirm", nil) forState:UIControlStateNormal];
    [confirm addTarget:self action:@selector(as_sortConfirmTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:confirm];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    cancel.backgroundColor = ASHexRGBA(0xF6F6F6FF);
    cancel.layer.cornerRadius = SW(26);
    cancel.layer.masksToBounds = YES;
    cancel.titleLabel.font = SWFontS(20, UIFontWeightRegular);
    [cancel setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    [cancel setTitle:NSLocalizedString(@"Cancel", nil) forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(as_sortCancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:cancel];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:content.topAnchor],
        [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [stack.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:SW(15)],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [confirm.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:SW(15)],
        [confirm.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [confirm.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [confirm.heightAnchor constraintEqualToConstant:SW(52)],

        [cancel.topAnchor constraintEqualToAnchor:confirm.bottomAnchor constant:SW(15)],
        [cancel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [cancel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [cancel.heightAnchor constraintEqualToConstant:SW(52)],
        [cancel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];

    [self as_applyPendingSortUI];

    [UIView animateWithDuration:0.18 animations:^{
        mask.alpha = 1.0;
        panel.alpha = 1.0;
        panel.transform = CGAffineTransformIdentity;
    }];
}

#pragma mark - UI 设置

- (BOOL)isVideoMode {
    return (self.mode == ASAssetListModeSimilarVideo ||
            self.mode == ASAssetListModeDuplicateVideo ||
            self.mode == ASAssetListModeBigVideos ||
            self.mode == ASAssetListModeScreenRecordings);
}

- (void)recomputeCountsOnly {
    NSUInteger total = 0;
    NSUInteger cleanable = 0;

    if ([self isGroupMode]) {
        for (ASAssetSection *sec in self.sections) {
            total += sec.assets.count;
            if (sec.assets.count > 1) cleanable += (sec.assets.count - 1);
        }
    } else {
        for (ASAssetSection *sec in self.sections) total += sec.assets.count;
        cleanable = total;
    }

    self.totalItemCount = total;
    self.cleanableItemCount = cleanable;
}

- (NSAttributedString *)topSummaryAttributedText {
    NSString *freeStr = ASHumanSize(self.totalCleanableBytes);
    NSString *cleanableStr = [NSString stringWithFormat:@"%lu", (unsigned long)self.cleanableItemCount];
    NSString *totalStr = [NSString stringWithFormat:@"%lu", (unsigned long)self.totalItemCount];
    NSString *unit = [self isVideoMode] ? NSLocalizedString(@"Videos", nil) : NSLocalizedString(@"Photos", nil);

    NSString *full = [NSString stringWithFormat:NSLocalizedString(@"%@ Free Up |  %@ / %@ %@", nil), freeStr, cleanableStr, totalStr, unit];

    UIColor *blue = [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0]; // #024DFFFF
    UIColor *gray = [UIColor colorWithRed:0x66/255.0 green:0x66/255.0 blue:0x66/255.0 alpha:1.0]; // #666666FF
    UIFont *font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];

    NSMutableAttributedString *att = [[NSMutableAttributedString alloc] initWithString:full attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: gray
    }];

    NSRange r1 = [full rangeOfString:freeStr];
    if (r1.location != NSNotFound) [att addAttribute:NSForegroundColorAttributeName value:blue range:r1];

    NSRange r2 = [full rangeOfString:cleanableStr];
    if (r2.location != NSNotFound) [att addAttribute:NSForegroundColorAttributeName value:blue range:r2];

    return att;
}

- (void)updateTopSummaryUI {
    self.topSummaryLabel.attributedText = [self topSummaryAttributedText];
}

- (void)setupUI {
    self.bottomBarH = 64;

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];

    if ([self isGroupMode]) {
        layout.minimumInteritemSpacing = 0;
        layout.minimumLineSpacing = SW(10);
        layout.sectionInset = [self useVideoGroupStyle] ? SWInsets(10, 20, 0, 20)
                                                        : SWInsets(10, 20, 0, 20);
        layout.headerReferenceSize = CGSizeZero;
    } else {
        layout.minimumInteritemSpacing = SW(2);
        layout.minimumLineSpacing = SW(2);
        layout.sectionInset = SWInsets(10, 10, 10, 10);
        layout.headerReferenceSize = CGSizeMake(self.view.bounds.size.width, SW(44));
    }

    self.cv = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.cv.dataSource = self;
    self.cv.delegate = self;

    if ([self isGroupMode]) {
        [self.cv registerClass:ASAssetGroupCardCell.class forCellWithReuseIdentifier:@"ASAssetGroupCardCell"];
        [self.cv registerClass:ASVideoGroupCardCell.class forCellWithReuseIdentifier:@"ASVideoGroupCardCell"];
    } else {
        [self.cv registerClass:ASAssetGridCell.class forCellWithReuseIdentifier:@"ASAssetGridCell"];
        [self.cv registerClass:ASAssetSectionHeader.class
    forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
           withReuseIdentifier:@"ASAssetSectionHeader"];
    }

    if ([self isGroupMode]) {
        self.cv.backgroundColor = UIColor.clearColor;
        self.cv.backgroundView = nil;
        self.cv.opaque = NO;
        [self.view addSubview:self.cv];
    } else {
        UIView *bg = [UIView new];
        bg.backgroundColor = UIColor.whiteColor;
        bg.layer.cornerRadius = SW(16);
        bg.layer.masksToBounds = YES;
        if (@available(iOS 11.0, *)) {
            bg.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        }
        self.listBgView = bg;
        [self.view addSubview:bg];

        self.cv.backgroundColor = UIColor.clearColor;
        [bg addSubview:self.cv];
    }

    // Empty state
    self.emptyView = [UIView new];
    self.emptyView.backgroundColor = UIColor.clearColor;
    self.emptyView.hidden = YES;
    [self.view addSubview:self.emptyView];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.text = NSLocalizedString(@"No items to clean", nil);
    self.emptyLabel.textColor = UIColor.blackColor;
    self.emptyLabel.font = SWFontS(20, UIFontWeightMedium);
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 1;
    [self.emptyView addSubview:self.emptyLabel];

    UIView *bar = [UIView new];
    bar.backgroundColor = UIColor.clearColor;
    bar.userInteractionEnabled = YES;

    ASNoHighlightButton *btn = [ASNoHighlightButton buttonWithType:UIButtonTypeCustom];
    btn.userInteractionEnabled = YES;

    btn.layer.cornerRadius = SW(35);
    btn.layer.masksToBounds = YES;
    btn.backgroundColor = [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];

    btn.layer.shadowOpacity = 0;
    btn.layer.shadowRadius = 0;
    btn.layer.shadowPath = nil;

    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = SWFontS(16, UIFontWeightMedium);
    [btn addTarget:self action:@selector(onDelete) forControlEvents:UIControlEventTouchUpInside];

    [bar addSubview:btn];
    [self.view addSubview:bar];

    self.bottomBar = bar;
    self.deleteBtn = btn;
    
    // 初始隐藏按钮
    self.deleteBtn.hidden = YES;
    self.deleteBtn.enabled = NO;
    
    [self.view bringSubviewToFront:self.bottomBar];
}

- (BOOL)hasAnyItemsToShow {
    if (self.sections.count == 0) return NO;

    if ([self isGroupMode]) {
        for (ASAssetSection *sec in self.sections) {
            if (sec.assets.count >= 2) return YES;
        }
        return NO;
    } else {
        for (ASAssetSection *sec in self.sections) {
            if (sec.assets.count > 0) return YES;
        }
        return NO;
    }
}

- (void)updateEmptyState {
    BOOL empty = ![self hasAnyItemsToShow];

    self.emptyView.hidden = !empty;

    self.cv.hidden = empty;

    if (!empty) return;

    [self as_noAnim:^{
        self.bottomBar.hidden = YES;
        self.deleteBtn.hidden = YES;
        self.deleteBtn.enabled = NO;
    }];
}

#pragma mark - 全选功能

- (void)toggleSelectAll {
    NSMutableSet<NSString *> *shouldAll = [NSMutableSet set];

    // 根据模式选择全选的内容
    if ([self isGroupMode]) {
        for (ASAssetSection *sec in self.sections) {
            for (NSInteger i = 1; i < sec.assets.count; i++) {
                ASAssetModel *m = sec.assets[i];
                if (m.localId.length) [shouldAll addObject:m.localId];
            }
        }
    } else {
        for (ASAssetSection *sec in self.sections) {
            for (ASAssetModel *m in sec.assets) if (m.localId.length) [shouldAll addObject:m.localId];
        }
    }

    // 检查当前是否已经全选，如果已全选则取消选择，否则全选
    BOOL alreadyAll = YES;
    for (NSString *lid in shouldAll) {
        if (![self.selectedIds containsObject:lid]) { alreadyAll = NO; break; }
    }

    if (alreadyAll) {
        [self.selectedIds minusSet:shouldAll];
    } else {
        [self.selectedIds unionSet:shouldAll];
    }

    [self recomputeBytesAndRefreshUI];
    [self syncNavSelectAllState];
}

- (CGFloat)pillWidthForButton:(UIButton *)btn height:(CGFloat)h {
    NSString *t = [btn titleForState:UIControlStateNormal] ?: @"";
    UIFont *f = btn.titleLabel.font ?: SWFontS(13, UIFontWeightMedium);

    CGFloat textW = ceil([t boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, h)
                                        options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
                                     attributes:@{NSFontAttributeName:f}
                                        context:nil].size.width);

    CGFloat imgW = 0;
    UIImage *img = [btn imageForState:UIControlStateNormal];
    if (img) imgW = ceil(img.size.width);

    UIEdgeInsets in = btn.contentEdgeInsets;
    CGFloat spacing = (img && t.length) ? SW(6) : 0;

    return ceil(in.left + imgW + spacing + textW + in.right);
}

- (void)configPillButtonBase:(UIButton *)btn {
    btn.backgroundColor = UIColor.whiteColor;
    btn.layer.cornerRadius = SW(20);
    btn.layer.masksToBounds = YES;

    btn.titleLabel.font = SWFontS(13, UIFontWeightMedium);
    btn.titleLabel.numberOfLines = 1;
    btn.titleLabel.lineBreakMode = NSLineBreakByClipping;
    btn.titleLabel.adjustsFontSizeToFitWidth = NO;

    [btn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];

    btn.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;

    btn.contentEdgeInsets = SWInsets(6, 8, 6, 15);

    btn.imageEdgeInsets = UIEdgeInsetsZero;
    btn.titleEdgeInsets = SWInsets(0, 6, 0, 0);
}

- (NSString *)sortTitle {
    switch (self.sortMode) {
        case ASAssetSortModeNewest:   return NSLocalizedString(@"Newest", nil);
        case ASAssetSortModeOldest:   return NSLocalizedString(@"Oldest", nil);
        case ASAssetSortModeLargest:  return NSLocalizedString(@"Largest", nil);
        case ASAssetSortModeSmallest: return NSLocalizedString(@"Smallest", nil);
    }
    return NSLocalizedString(@"Newest", nil);
}

- (void)updateTopSelectAllButtonUIWithAll:(BOOL)all {
    [self updatePillButton:self.topSelectAllBtn
                 imageName:(all ? @"ic_select_s" : @"ic_select_gray_n")
                     title:(all ? NSLocalizedString(@"Deselect All", nil) : NSLocalizedString(@"Select All", nil))];
}

- (void)updateTopSortButtonUI {
    [self updatePillButton:self.topSortBtn imageName:@"ic_sort" title:[self sortTitle]];
}

#pragma mark - Build data

- (NSString *)titleForMode:(ASAssetListMode)mode {
    switch (mode) {
        case ASAssetListModeSimilarImage: return NSLocalizedString(@"Similar Photos", nil);
        case ASAssetListModeSimilarVideo: return NSLocalizedString(@"Similar Videos", nil);
        case ASAssetListModeDuplicateImage: return NSLocalizedString(@"Duplicate Photos", nil);
        case ASAssetListModeDuplicateVideo: return NSLocalizedString(@"Duplicate Videos", nil);
        case ASAssetListModeScreenshots: return NSLocalizedString(@"Screenshots", nil);
        case ASAssetListModeScreenRecordings: return NSLocalizedString(@"Screen Recoeding", nil);
        case ASAssetListModeBigVideos: return NSLocalizedString(@"Big Videos", nil);
        case ASAssetListModeBlurryPhotos: return NSLocalizedString(@"Blurry Photos", nil);
        case ASAssetListModeOtherPhotos: return NSLocalizedString(@"Other Photos", nil);
    }
    return NSLocalizedString(@"List", nil);
}

- (NSDate *)dateForModel:(ASAssetModel *)m {
    return m.creationDate ?: m.modificationDate;
}

- (NSDate *)dateForGroupAssets:(NSArray<ASAssetModel *> *)assets {
    NSDate *best = nil;
    for (ASAssetModel *m in assets) {
        NSDate *d = [self dateForModel:m];
        if (!d) continue;
        if (!best || [d compare:best] == NSOrderedDescending) best = d;
    }
    return best ?: [NSDate dateWithTimeIntervalSince1970:0];
}

- (BOOL)isGroupMode {
    return (self.mode == ASAssetListModeSimilarImage ||
            self.mode == ASAssetListModeSimilarVideo ||
            self.mode == ASAssetListModeDuplicateImage ||
            self.mode == ASAssetListModeDuplicateVideo);
}

- (ASGroupType)wantedGroupType {
    switch (self.mode) {
        case ASAssetListModeSimilarImage:   return ASGroupTypeSimilarImage;
        case ASAssetListModeSimilarVideo:   return ASGroupTypeSimilarVideo;
        case ASAssetListModeDuplicateImage: return ASGroupTypeDuplicateImage;
        case ASAssetListModeDuplicateVideo: return ASGroupTypeDuplicateVideo;
        default: return ASGroupTypeDuplicateImage;
    }
}

- (void)rebuildDataFromManager {
    [self.sections removeAllObjects];
    self.assetById = @{}; // 先清空

    if ([self isGroupMode]) {
        NSArray<ASAssetGroup *> *src = (self.mode == ASAssetListModeSimilarImage ||
                                        self.mode == ASAssetListModeSimilarVideo)
                                        ? (self.scanMgr.similarGroups ?: @[])
                                        : (self.scanMgr.duplicateGroups ?: @[]);

        ASGroupType t = [self wantedGroupType];

        for (ASAssetGroup *g in src) {
            if (g.type != t) continue;

            NSMutableArray<ASAssetModel *> *valid = [NSMutableArray array];
            for (ASAssetModel *m in g.assets) {
                if (m.localId.length) [valid addObject:m];
            }
            if (valid.count < 2) continue;

            ASAssetSection *s = [ASAssetSection new];
            s.isGrouped = YES;
            s.assets = valid;
            s.groupDate = [self dateForGroupAssets:s.assets];
            [self.sections addObject:s];
        }

        [self.sections sortUsingComparator:^NSComparisonResult(ASAssetSection *a, ASAssetSection *b) {
            return [b.groupDate compare:a.groupDate];
        }];

        NSInteger idx = 1;
        for (ASAssetSection *sec in self.sections) {
            sec.title = [NSString stringWithFormat:@"%ld（%lu）", (long)idx, (unsigned long)sec.assets.count];
            idx++;
        }
    } else {
        NSArray<ASAssetModel *> *arr = @[];
        switch (self.mode) {
            case ASAssetListModeScreenshots:       arr = self.scanMgr.screenshots ?: @[]; break;
            case ASAssetListModeScreenRecordings:  arr = self.scanMgr.screenRecordings ?: @[]; break;
            case ASAssetListModeBigVideos:         arr = self.scanMgr.bigVideos ?: @[]; break;
            case ASAssetListModeBlurryPhotos:      arr = self.scanMgr.blurryPhotos ?: @[]; break;
            case ASAssetListModeOtherPhotos:       arr = self.scanMgr.otherPhotos ?: @[]; break;
            default: break;
        }

        NSMutableArray<ASAssetModel *> *valid = [NSMutableArray array];
        for (ASAssetModel *m in arr) {
            if (m.localId.length) [valid addObject:m];
        }

        [valid sortUsingComparator:^NSComparisonResult(ASAssetModel *a, ASAssetModel *b) {
            NSDate *da = [self dateForModel:a];
            NSDate *db = [self dateForModel:b];

            if (!da && !db) return NSOrderedSame;
            if (!da) return NSOrderedDescending;
            if (!db) return NSOrderedAscending;

            return [db compare:da];
        }];

        ASAssetSection *s = [ASAssetSection new];
        s.isGrouped = NO;
        s.title = @"";
        s.assets = valid;

        [self.sections addObject:s];
    }

    NSMutableArray<NSString *> *allIds = [NSMutableArray array];

    for (ASAssetSection *sec in self.sections) {
        for (ASAssetModel *m in sec.assets) {
            if (m.localId.length) [allIds addObject:m.localId];
        }
    }

    if (allIds.count == 0) {
        self.assetById = @{};
        return;
    }

    NSOrderedSet<NSString *> *uniq = [NSOrderedSet orderedSetWithArray:allIds];
    NSArray<NSString *> *uniqIds = uniq.array;

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:uniqIds options:nil];
    NSMutableDictionary<NSString*, PHAsset*> *map = [NSMutableDictionary dictionaryWithCapacity:fr.count];

    [fr enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.localIdentifier.length) {
            map[obj.localIdentifier] = obj;
        }
    }];

    self.assetById = map;

    for (NSInteger si = self.sections.count - 1; si >= 0; si--) {
        ASAssetSection *sec = self.sections[si];

        NSMutableArray<ASAssetModel *> *kept = [NSMutableArray arrayWithCapacity:sec.assets.count];
        for (ASAssetModel *m in sec.assets) {
            if (!m.localId.length) continue;
            if (!self.assetById[m.localId]) continue;
            [kept addObject:m];
        }

        sec.assets = kept;

        if (sec.isGrouped && sec.assets.count < 2) {
            [self.sections removeObjectAtIndex:si];
        }
    }
}

- (uint64_t)cleanableBytesForSection:(ASAssetSection *)sec {
    uint64_t s = 0;
    for (NSInteger i = 0; i < (NSInteger)sec.assets.count; i++) { 
        s += sec.assets[i].fileSizeBytes;
    }
    return s;
}

- (void)applyCurrentSortAndReload {

    if ([self isGroupMode]) {

        switch (self.sortMode) {

            case ASAssetSortModeNewest: {
                [self.sections sortUsingComparator:^NSComparisonResult(ASAssetSection *a, ASAssetSection *b) {
                    return [b.groupDate compare:a.groupDate];
                }];
            } break;

            case ASAssetSortModeOldest: {
                [self.sections sortUsingComparator:^NSComparisonResult(ASAssetSection *a, ASAssetSection *b) {
                    return [a.groupDate compare:b.groupDate];
                }];
            } break;

            case ASAssetSortModeLargest: {
                [self.sections sortUsingComparator:^NSComparisonResult(ASAssetSection *a, ASAssetSection *b) {
                    uint64_t sa = [self cleanableBytesForSection:a];
                    uint64_t sb = [self cleanableBytesForSection:b];
                    if (sa == sb) return NSOrderedSame;
                    return (sa > sb) ? NSOrderedAscending : NSOrderedDescending;
                }];
            } break;

            case ASAssetSortModeSmallest: {
                [self.sections sortUsingComparator:^NSComparisonResult(ASAssetSection *a, ASAssetSection *b) {
                    uint64_t sa = [self cleanableBytesForSection:a];
                    uint64_t sb = [self cleanableBytesForSection:b];
                    if (sa == sb) return NSOrderedSame;
                    return (sa < sb) ? NSOrderedAscending : NSOrderedDescending;
                }];
            } break;
        }

        NSInteger idx = 1;
        for (ASAssetSection *sec in self.sections) {
            sec.title = [NSString stringWithFormat:@"%ld（%lu）", (long)idx, (unsigned long)sec.assets.count];
            idx++;
        }

    } else {

        ASAssetSection *sec = self.sections.firstObject;
        if (!sec) return;

        switch (self.sortMode) {

            case ASAssetSortModeNewest: {
                [sec.assets sortUsingComparator:^NSComparisonResult(ASAssetModel *a, ASAssetModel *b) {
                    NSDate *da = [self dateForModel:a];
                    NSDate *db = [self dateForModel:b];
                    if (!da && !db) return NSOrderedSame;
                    if (!da) return NSOrderedDescending;
                    if (!db) return NSOrderedAscending;
                    return [db compare:da]; // 新->旧
                }];
            } break;

            case ASAssetSortModeOldest: {
                [sec.assets sortUsingComparator:^NSComparisonResult(ASAssetModel *a, ASAssetModel *b) {
                    NSDate *da = [self dateForModel:a];
                    NSDate *db = [self dateForModel:b];
                    if (!da && !db) return NSOrderedSame;
                    if (!da) return NSOrderedDescending;
                    if (!db) return NSOrderedAscending;
                    return [da compare:db]; // 旧->新
                }];
            } break;

            case ASAssetSortModeLargest: {
                [sec.assets sortUsingComparator:^NSComparisonResult(ASAssetModel *a, ASAssetModel *b) {
                    if (a.fileSizeBytes == b.fileSizeBytes) return NSOrderedSame;
                    return (a.fileSizeBytes > b.fileSizeBytes) ? NSOrderedAscending : NSOrderedDescending;
                }];
            } break;

            case ASAssetSortModeSmallest: {
                [sec.assets sortUsingComparator:^NSComparisonResult(ASAssetModel *a, ASAssetModel *b) {
                    if (a.fileSizeBytes == b.fileSizeBytes) return NSOrderedSame;
                    return (a.fileSizeBytes < b.fileSizeBytes) ? NSOrderedAscending : NSOrderedDescending;
                }];
            } break;
        }
    }

    [self recomputeGroupCardLeftWidth];
    [self updateTopSortButtonUI];
    [self.cv reloadData];
    [self updateEmptyState];
}

#pragma mark - Default selection rule

- (void)applyDefaultSelectionRule {
    [self.selectedIds removeAllObjects];

    if ([self isGroupMode]) {
        for (ASAssetSection *sec in self.sections) {
            for (NSInteger i = 1; i < sec.assets.count; i++) {
                ASAssetModel *m = sec.assets[i];
                if (m.localId.length) [self.selectedIds addObject:m.localId];
            }
        }
    } else {
        for (ASAssetSection *sec in self.sections) {
            for (ASAssetModel *m in sec.assets) {
                if (m.localId.length) [self.selectedIds addObject:m.localId];
            }
        }
    }
}

#pragma mark - Bytes + UI refresh

- (uint64_t)bytesForModel:(ASAssetModel *)m { return m.fileSizeBytes; }

- (void)recomputeBytesAndRefreshUI {
    uint64_t total = 0;
    uint64_t selected = 0;

    [self recomputeBytesAndRefreshTopOnly];

    if ([self isGroupMode]) {
        for (ASAssetSection *sec in self.sections) {
            for (NSInteger i=1; i<sec.assets.count; i++) total += [self bytesForModel:sec.assets[i]];
        }
    } else {
        for (ASAssetSection *sec in self.sections)
            for (ASAssetModel *m in sec.assets) total += [self bytesForModel:m];
    }

    for (ASAssetSection *sec in self.sections) {
        for (ASAssetModel *m in sec.assets) {
            if ([self.selectedIds containsObject:m.localId]) selected += [self bytesForModel:m];
        }
    }

    self.totalCleanableBytes = total;
    self.selectedBytes = selected;

    for (NSIndexPath *ip in self.cv.indexPathsForVisibleItems) {
        if (ip.section >= self.sections.count) continue;

        if ([self isGroupMode]) {
            UICollectionViewCell *raw = [self.cv cellForItemAtIndexPath:ip];
            if ([raw isKindOfClass:ASVideoGroupCardCell.class]) {
                ASVideoGroupCardCell *cell = (ASVideoGroupCardCell *)raw;
                cell.selectedIds = self.selectedIds;
                [cell refreshSelectionUI];
            } else if ([raw isKindOfClass:ASAssetGroupCardCell.class]) {
                ASAssetGroupCardCell *cell = (ASAssetGroupCardCell *)raw;
                cell.selectedIds = self.selectedIds;
                [cell refreshSelectionUI];
            }
        } else {
            ASAssetSection *sec = self.sections[ip.section];
            if (ip.item >= sec.assets.count) continue;

            ASAssetGridCell *cell = (ASAssetGridCell *)[self.cv cellForItemAtIndexPath:ip];
            if (!cell) continue;

            ASAssetModel *m = sec.assets[ip.item];
            [cell applySelected:[self.selectedIds containsObject:m.localId]];
        }
    }
}

#pragma mark - Per section select all

- (void)toggleSectionAll:(NSInteger)sectionIndex {
    if (sectionIndex >= self.sections.count) return;
    ASAssetSection *sec = self.sections[sectionIndex];

    NSMutableArray<ASAssetModel *> *targets = [NSMutableArray array];
    if ([self isGroupMode] && sec.isGrouped) {
        for (NSInteger i = 1; i < sec.assets.count; i++) [targets addObject:sec.assets[i]];
    } else {
        [targets addObjectsFromArray:sec.assets];
    }

    BOOL allSel = YES;
    for (ASAssetModel *m in targets) {
        if (![self.selectedIds containsObject:m.localId]) { allSel = NO; break; }
    }

    if (allSel) {
        for (ASAssetModel *m in targets) [self.selectedIds removeObject:m.localId];
    } else {
        for (ASAssetModel *m in targets) if (m.localId.length) [self.selectedIds addObject:m.localId];
    }

    [self recomputeBytesAndRefreshUI];
    [self syncNavSelectAllState];
}

#pragma mark - Delete

- (void)onDelete {
    if (self.selectedIds.count == 0) return;

    NSUInteger count = self.selectedIds.count;

    BOOL isVideo = [self isVideoMode];
    NSString *typePlural = isVideo ? NSLocalizedString(@"videos",nil) : NSLocalizedString(@"photos",nil);
    NSString *typeSingle = isVideo ? NSLocalizedString(@"video",nil)  : NSLocalizedString(@"photo",nil);

    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"This action will delete the selected %@ from your system album.",nil), typePlural];

    NSString *actionTitle = nil;
    if (count == 1) {
        actionTitle = [NSString stringWithFormat:NSLocalizedString(@"Delete %@ (%lu)",nil), typeSingle, (unsigned long)count];
    } else {
        actionTitle = [NSString stringWithFormat:NSLocalizedString(@"Delete %@ (%lu)",nil), typePlural, (unsigned long)count];
    }

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;

    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil)
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];

    [ac addAction:[UIAlertAction actionWithTitle:actionTitle
                                          style:UIAlertActionStyleDestructive
                                        handler:^(__unused UIAlertAction * _Nonnull action) {

        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (self.selectedIds.count == 0) return;

        NSSet<NSString *> *toDelete = [self.selectedIds copy];
        NSArray<NSString *> *ids = toDelete.allObjects;

        PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
        if (fr.count == 0) return;

        __weak typeof(self) weakSelf2 = self;

        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest deleteAssets:fr];
        } completionHandler:^(BOOL success, NSError * _Nullable error) {

            dispatch_async(dispatch_get_main_queue(), ^{
                if (!success) return;

                NSUInteger deletedCount = toDelete.count;
                uint64_t freedBytes = weakSelf2.selectedBytes;

                ResultViewController *r =
                [[ResultViewController alloc] initWithDeletedCount:deletedCount
                                                         freedBytes:freedBytes];
                [weakSelf2.navigationController pushViewController:r animated:YES];

                [weakSelf2.selectedIds removeAllObjects];
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [weakSelf2 rebuildDataFromManager];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [weakSelf2 applyDefaultSelectionRule];
                        [weakSelf2.cv reloadData];
                        [weakSelf2 recomputeBytesAndRefreshUI];
                        [weakSelf2 syncNavSelectAllState];
                        [weakSelf2 updateEmptyState];
                    });
                });
            });
        }];
    }]];

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        UIPopoverPresentationController *pop = ac.popoverPresentationController;
        pop.sourceView = self.deleteBtn ?: self.view;
        pop.sourceRect = (self.deleteBtn ? self.deleteBtn.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds), SW(1), SW(1)));
        pop.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }

    [self presentViewController:ac animated:YES completion:nil];
}

- (void)onTapGridSelectBtn:(UIButton *)btn {
    CGPoint p = [btn convertPoint:CGPointMake(CGRectGetMidX(btn.bounds), CGRectGetMidY(btn.bounds))
                           toView:self.cv];
    NSIndexPath *ip = [self.cv indexPathForItemAtPoint:p];
    if (!ip) return;

    ASAssetModel *m = self.sections[ip.section].assets[ip.item];
    if (!m.localId.length) return;

    if ([self.selectedIds containsObject:m.localId]) [self.selectedIds removeObject:m.localId];
    else [self.selectedIds addObject:m.localId];

    [self updateOneCell:ip];
    [self recomputeBytesAndRefreshTopOnly];
    [self syncNavSelectAllState];
}

#pragma mark - Collection DS

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if ([self isGroupMode]) return 1;
    return self.sections[section].assets.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {

    if ([self isGroupMode]) {
        ASAssetSection *sec = self.sections[indexPath.section];
        NSString *unit = [self isVideoMode] ? NSLocalizedString(@"Videos", nil) : NSLocalizedString(@"Photos", nil);
        __weak typeof(self) weakSelf = self;

        if ([self useVideoGroupStyle]) {
            ASVideoGroupCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ASVideoGroupCardCell"
                                                                                   forIndexPath:indexPath];
            [cell bindModels:sec.assets
                sectionIndex:indexPath.section
                    unitText:unit
                  selectedIds:self.selectedIds
                   assetById:self.assetById
                      imgMgr:self.imgMgr];

            cell.onTapSelectAll = ^(NSInteger sectionIndex) { [weakSelf toggleSectionAll:sectionIndex]; };
            cell.onToggleIndex  = ^(NSInteger sectionIndex, NSInteger modelIndex) { [weakSelf toggleOneModelAtSection:sectionIndex modelIndex:modelIndex]; };
            cell.onPreviewIndex = ^(NSInteger sectionIndex, NSInteger modelIndex) { [weakSelf goPreviewSection:sectionIndex initialIndex:modelIndex]; };
            return cell;
        }

        ASAssetGroupCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ASAssetGroupCardCell"
                                                                              forIndexPath:indexPath];
        [cell bindModels:sec.assets
            sectionIndex:indexPath.section
                unitText:unit
              selectedIds:self.selectedIds
               assetById:self.assetById
                  imgMgr:self.imgMgr
              fixedLeftW:self.groupCardLeftW];

        cell.onTapSelectAll = ^(NSInteger sectionIndex) { [weakSelf toggleSectionAll:sectionIndex]; };
        cell.onToggleIndex  = ^(NSInteger sectionIndex, NSInteger modelIndex) { [weakSelf toggleOneModelAtSection:sectionIndex modelIndex:modelIndex]; };
        cell.onPreviewIndex = ^(NSInteger sectionIndex, NSInteger modelIndex) { [weakSelf goPreviewSection:sectionIndex initialIndex:modelIndex]; };
        return cell;
    }

    ASAssetGridCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ASAssetGridCell"
                                                                      forIndexPath:indexPath];
    ASAssetModel *m = self.sections[indexPath.section].assets[indexPath.item];
    [cell.selectBtn removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [cell.selectBtn addTarget:self action:@selector(onTapGridSelectBtn:) forControlEvents:UIControlEventTouchUpInside];

//    cell.badge.text = ASTypeText(m.mediaType);
//    cell.sizeLabel.text = ASHumanSize(m.fileSizeBytes);
    cell.badge.text = @"";
    cell.sizeLabel.text = @"";

    BOOL sel = [self.selectedIds containsObject:m.localId];
    [cell applySelected:sel];

    cell.img.image = nil;
    cell.representedLocalId = m.localId ?: @"";

    PHAsset *a = (m.localId.length ? self.assetById[m.localId] : nil);
    if (!a) return cell;

    
    PHImageRequestOptions *opt = [PHImageRequestOptions new];
    opt.networkAccessAllowed = YES;
    opt.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    opt.resizeMode = PHImageRequestOptionsResizeModeExact;
    opt.synchronous = NO;

    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize viewSize = cell.img.bounds.size;
    if (viewSize.width <= 1 || viewSize.height <= 1) viewSize = cell.contentView.bounds.size;
    CGSize target = CGSizeMake(viewSize.width * scale, viewSize.height * scale);

    __weak typeof(cell) weakCell = cell;
    NSString *expectId = cell.representedLocalId;

    [self.imgMgr requestImageForAsset:a
                           targetSize:target
                          contentMode:PHImageContentModeAspectFill
                              options:opt
                        resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (!result) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            ASAssetGridCell *c = weakCell;
            if (!c) return;
            if (![c.representedLocalId isEqualToString:expectId]) return;
            c.img.image = result;
        });
    }];

    return cell;
}

- (NSArray<PHAsset *> *)phAssetsForSection:(ASAssetSection *)sec {
    NSMutableArray<PHAsset *> *arr = [NSMutableArray array];
    for (ASAssetModel *m in sec.assets) {
        PHAsset *a = (m.localId.length ? self.assetById[m.localId] : nil);
        if (a) [arr addObject:a];
    }
    return arr;
}

- (NSIndexSet *)selectedIndexSetForSection:(ASAssetSection *)sec {
    NSMutableIndexSet *set = [NSMutableIndexSet indexSet];
    for (NSInteger i = 0; i < (NSInteger)sec.assets.count; i++) {
        ASAssetModel *m = sec.assets[i];
        if (m.localId.length && [self.selectedIds containsObject:m.localId]) {
            [set addIndex:i];
        }
    }
    return set;
}

- (void)applySelectedFromPreviewIndexes:(NSIndexSet *)idxSet forSection:(ASAssetSection *)sec {

    BOOL grouped = ([self isGroupMode] && sec.isGrouped);

    for (NSInteger i = 0; i < (NSInteger)sec.assets.count; i++) {
        ASAssetModel *m = sec.assets[i];
        if (m.localId.length) [self.selectedIds removeObject:m.localId];
    }

    [idxSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx >= (NSUInteger)sec.assets.count) return;

        ASAssetModel *m = sec.assets[idx];
        if (m.localId.length) [self.selectedIds addObject:m.localId];
    }];
}


- (void)goPreviewSection:(NSInteger)sectionIndex initialIndex:(NSInteger)initialIndex {
    if (sectionIndex < 0 || sectionIndex >= (NSInteger)self.sections.count) return;
    ASAssetSection *sec = self.sections[sectionIndex];

    NSArray<PHAsset *> *assets = [self phAssetsForSection:sec];
    if (assets.count == 0) return;

    NSIndexSet *preSel = [self selectedIndexSetForSection:sec];

    ASMediaPreviewViewController *p =
    [[ASMediaPreviewViewController alloc] initWithAssets:assets
                                           initialIndex:MAX(0, MIN((NSInteger)assets.count - 1, initialIndex))
                                        selectedIndexes:preSel];

    p.bestIndex = 0;
    p.showsBestBadge = YES;

    __weak typeof(self) weakSelf = self;
    p.onBack = ^(NSArray<PHAsset *> *selectedAssets, NSIndexSet *selectedIndexes) {
        [weakSelf applySelectedFromPreviewIndexes:selectedIndexes forSection:sec];
        [weakSelf recomputeBytesAndRefreshUI];
        [weakSelf syncNavSelectAllState];
    };

    [self.navigationController pushViewController:p animated:YES];
}

- (void)toggleOneModelAtSection:(NSInteger)section modelIndex:(NSInteger)idx {
    if (section < 0 || section >= (NSInteger)self.sections.count) return;
    ASAssetSection *sec = self.sections[section];
    if (idx < 0 || idx >= (NSInteger)sec.assets.count) return;

    ASAssetModel *m = sec.assets[idx];
    if (!m.localId.length) return;

    if ([self.selectedIds containsObject:m.localId]) [self.selectedIds removeObject:m.localId];
    else [self.selectedIds addObject:m.localId];

    [self recomputeBytesAndRefreshUI];
    [self syncNavSelectAllState];
}

#pragma mark - Selection (tap)

- (void)recomputeBytesAndRefreshTopOnly {
    uint64_t total = 0;
    uint64_t selected = 0;

    if ([self isGroupMode]) {
        for (ASAssetSection *sec in self.sections)
            for (NSInteger i=1; i<sec.assets.count; i++) total += sec.assets[i].fileSizeBytes;
    } else {
        for (ASAssetSection *sec in self.sections)
            for (ASAssetModel *m in sec.assets) total += m.fileSizeBytes;
    }

    for (ASAssetSection *sec in self.sections)
        for (ASAssetModel *m in sec.assets)
            if ([self.selectedIds containsObject:m.localId]) selected += m.fileSizeBytes;

    self.totalCleanableBytes = total;
    self.selectedBytes = selected;

    [self recomputeCountsOnly];
    [self updateTopSummaryUI];

    NSUInteger selCount = self.selectedIds.count;
    BOOL show = (selCount > 0);
    
    NSString *title = @"";
    if (show) {
        if ([self isVideoMode]) {
            title = [NSString stringWithFormat:NSLocalizedString(@"Delete %lu Videos (%@)", nil),
                     (unsigned long)selCount,
                     ASHumanSize(self.selectedBytes)];
        } else {
            title = [NSString stringWithFormat:NSLocalizedString(@"Delete %lu Photos (%@)", nil),
                     (unsigned long)selCount,
                     ASHumanSize(self.selectedBytes)];
        }
    }

    [self as_noAnim:^{
        self.bottomBar.hidden = !show;
        self.deleteBtn.hidden = !show;
        self.deleteBtn.enabled = show;
        [self.deleteBtn setTitle:title forState:UIControlStateNormal];
    }];

    [self as_noAnim:^{
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];

    if ([self isGroupMode]) {
        [self goPreviewSection:indexPath.section initialIndex:0];
        return;
    }

    [self goPreviewSingle:indexPath];
}

- (void)goPreviewSingle:(NSIndexPath *)ip {
    if (ip.section < 0 || ip.section >= (NSInteger)self.sections.count) return;
    ASAssetSection *sec = self.sections[ip.section];
    if (ip.item < 0 || ip.item >= (NSInteger)sec.assets.count) return;

    ASAssetModel *m = sec.assets[ip.item];
    if (!m.localId.length) return;

    PHAsset *a = self.assetById[m.localId];
    if (!a) return;

    NSIndexSet *preSel = ([self.selectedIds containsObject:m.localId]
                          ? [NSIndexSet indexSetWithIndex:0]
                          : [NSIndexSet indexSet]);

    ASMediaPreviewViewController *p =
    [[ASMediaPreviewViewController alloc] initWithAssets:@[a]
                                           initialIndex:0
                                        selectedIndexes:preSel];

    p.bestIndex = 0;
    p.showsBestBadge = NO;

    __weak typeof(self) weakSelf = self;
    p.onBack = ^(NSArray<PHAsset *> *selectedAssets, NSIndexSet *selectedIndexes) {
        if ([selectedIndexes containsIndex:0]) [weakSelf.selectedIds addObject:m.localId];
        else [weakSelf.selectedIds removeObject:m.localId];

        [weakSelf updateOneCell:ip];
        [weakSelf recomputeBytesAndRefreshUI];
        [weakSelf syncNavSelectAllState];
    };

    [self.navigationController pushViewController:p animated:YES];
}


- (void)updateOneCell:(NSIndexPath *)ip {
    if ([self isGroupMode]) {
        ASAssetGroupCardCell *cell = (ASAssetGroupCardCell *)[self.cv cellForItemAtIndexPath:ip];
        if (![cell isKindOfClass:ASAssetGroupCardCell.class]) return;
        cell.selectedIds = self.selectedIds;
        [cell refreshSelectionUI];
        return;
    }

    ASAssetGridCell *cell = (ASAssetGridCell *)[self.cv cellForItemAtIndexPath:ip];
    if (!cell) return;
    ASAssetModel *m = self.sections[ip.section].assets[ip.item];
    [cell applySelected:[self.selectedIds containsObject:m.localId]];
}

#pragma mark - Layout (3 columns)

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {

    if ([self isGroupMode]) {
        UIEdgeInsets inset = ((UICollectionViewFlowLayout *)layout).sectionInset;
        CGFloat w = collectionView.bounds.size.width - inset.left - inset.right;
        CGFloat h = [self useVideoGroupStyle] ? 262 : 214;
        return CGSizeMake(floor(w), h);
    }

    UIEdgeInsets inset = ((UICollectionViewFlowLayout *)layout).sectionInset;
    CGFloat gap = ((UICollectionViewFlowLayout *)layout).minimumInteritemSpacing;
    CGFloat w = collectionView.bounds.size.width - inset.left - inset.right;
    CGFloat itemW = floor((w - gap*2) / 3.0);
    return CGSizeMake(itemW, itemW);
}

#pragma mark - Header (group section select all)

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    if ([self isGroupMode]) return [UICollectionReusableView new];

    if (![kind isEqualToString:UICollectionElementKindSectionHeader]) return [UICollectionReusableView new];

    ASAssetSectionHeader *h = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                withReuseIdentifier:@"ASAssetSectionHeader"
                                                                       forIndexPath:indexPath];
    ASAssetSection *sec = self.sections[indexPath.section];
    h.titleLabel.text = sec.isGrouped ? sec.title : @"";

    BOOL showBtn = YES;
    h.selectAllBtn.hidden = !showBtn;

    __weak typeof(self) weakSelf = self;
    h.tapSelectAll = ^{
        [weakSelf toggleSectionAll:indexPath.section];
    };
    return h;
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)layout
referenceSizeForHeaderInSection:(NSInteger)section {
    if ([self isGroupMode]) return CGSizeZero;
    return [self isGroupMode] ? CGSizeMake(collectionView.bounds.size.width, SW(44)) : CGSizeZero;
}

@end
