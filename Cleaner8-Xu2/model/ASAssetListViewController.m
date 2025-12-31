#import "ASAssetListViewController.h"
#import <Photos/Photos.h>
#import "ASPhotoScanManager.h"
#import "ASCustomNavBar.h"
#import "ASMediaPreviewViewController.h"

#pragma mark - UI helpers
typedef NS_ENUM(NSInteger, ASAssetSortMode) {
    ASAssetSortModeNewest = 0,   // 新 -> 旧（默认）
    ASAssetSortModeOldest,
    ASAssetSortModeLargest,
    ASAssetSortModeSmallest
};

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
    return (t == PHAssetMediaTypeVideo) ? @"video" : @"photo";
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
@property (nonatomic, strong) UILabel *infoLabel;       // size + duration
@property (nonatomic, strong) UIImageView *selectIcon;  // 24x24
@property (nonatomic, strong) UIButton *selectBtn;
@property (nonatomic, strong) UIButton *previewBtn;

@property (nonatomic, strong) UIImageView *bestBadge;   // 60x24 ic_best

- (void)applySelected:(BOOL)sel;
- (void)applyBest:(BOOL)isBest;
@end

@implementation ASVideoGroupThumbCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (self=[super initWithFrame:frame]) {
        _coverView = [UIImageView new];
        _coverView.contentMode = UIViewContentModeScaleAspectFill;
        _coverView.clipsToBounds = YES;
        _coverView.layer.cornerRadius = 8;

        _infoLabel = [UILabel new];
        _infoLabel.numberOfLines = 2;
        _infoLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
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
    CGFloat pad = 10;

    CGFloat infoW = self.contentView.bounds.size.width - pad*2 - 24 - 6;
    self.infoLabel.frame = CGRectMake(pad, pad, MAX(40, infoW), 34);

    CGFloat s = 24;
    self.selectIcon.frame = CGRectMake(self.contentView.bounds.size.width - pad - s, pad, s, s);
    self.selectBtn.frame = CGRectInset(self.selectIcon.frame, -8, -8);

    CGFloat bw = 60, bh = 24;
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
@property (nonatomic, strong) UILabel *countLabel;   // “4 Videos”
@property (nonatomic, strong) UILabel *sizeLabel;    // “654.89MB”
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
        _card.layer.cornerRadius = 20;
        _card.clipsToBounds = YES;

        _countLabel = [UILabel new];
        _countLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightMedium];
        _countLabel.textColor = UIColor.blackColor;

        _sizeLabel = [UILabel new];
        _sizeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _sizeLabel.textColor = [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];

        _selectAllBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _selectAllBtn.adjustsImageWhenHighlighted = NO;
        _selectAllBtn.showsTouchWhenHighlighted = NO;
        _selectAllBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _selectAllBtn.backgroundColor = UIColor.clearColor;
        _selectAllBtn.layer.cornerRadius = 18;
        _selectAllBtn.layer.borderWidth = 1;
        _selectAllBtn.contentEdgeInsets = UIEdgeInsetsMake(8, 8, 8, 8);

        [_selectAllBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
        [_selectAllBtn setTitleColor:UIColor.blackColor forState:UIControlStateHighlighted];
        [_selectAllBtn addTarget:self action:@selector(onTapSelectAllBtn) forControlEvents:UIControlEventTouchUpInside];

        UICollectionViewFlowLayout *l = [UICollectionViewFlowLayout new];
        l.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        l.minimumLineSpacing = 10;
        l.minimumInteritemSpacing = 10;

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

    CGFloat pad = 20;
    CGFloat twoLineGap = 4;

    CGFloat countH = ceil(self.countLabel.font.lineHeight); // ~24
    CGFloat sizeH  = ceil(self.sizeLabel.font.lineHeight);  // ~14
    CGFloat leftBlockH = countH + twoLineGap + sizeH;

    CGFloat btnH = 36;
    UIFont *bf = self.selectAllBtn.titleLabel.font ?: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    UIEdgeInsets in = self.selectAllBtn.contentEdgeInsets;

    CGFloat t1 = [self as_textW:@"Select All" font:bf h:btnH];
    CGFloat t2 = [self as_textW:@"Deselect All" font:bf h:btnH];
    CGFloat wText = MAX(t1, t2);

    CGFloat btnW = ceil(in.left + wText + in.right);
    btnW = MIN(btnW, self.card.bounds.size.width - pad*2);

    CGFloat btnY = pad + floor((leftBlockH - btnH)/2.0);
    self.selectAllBtn.frame = CGRectMake(self.card.bounds.size.width - pad - btnW, btnY, btnW, btnH);

    CGFloat leftW = CGRectGetMinX(self.selectAllBtn.frame) - pad - 12;
    self.countLabel.frame = CGRectMake(pad, pad, MAX(60, leftW), countH);
    self.sizeLabel.frame  = CGRectMake(pad, CGRectGetMaxY(self.countLabel.frame) + twoLineGap, MAX(60, leftW), sizeH);

    CGFloat listY = CGRectGetMaxY(self.sizeLabel.frame) + 10;

    // 列表左边距 20（你说的）
    self.thumbCV.frame = CGRectMake(pad,
                                    listY,
                                    self.card.bounds.size.width - pad, // 右侧贴满或你也可以减 pad
                                    160);
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
    self.unitText = unitText ?: @"Videos";
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
            [self.selectAllBtn setTitle:@"Deselect All" forState:UIControlStateNormal];
            [self.selectAllBtn setTitleColor:blue forState:UIControlStateNormal];
            [self.selectAllBtn setTitleColor:blue forState:UIControlStateHighlighted];
            self.selectAllBtn.layer.borderColor = blue.CGColor;
        } else {
            [self.selectAllBtn setTitle:@"Select All" forState:UIControlStateNormal];
            [self.selectAllBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
            [self.selectAllBtn setTitleColor:UIColor.blackColor forState:UIControlStateHighlighted];
            self.selectAllBtn.layer.borderColor = grayBorder.CGColor;
        }
    }];

    // 刷 visible item 勾选+best
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
    CGSize target = CGSizeMake(120*scale, 160*scale);

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
    return CGSizeMake(120, 160);
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
@property (nonatomic, strong) UILabel *badge;     // 右下角：类型
@property (nonatomic, strong) UILabel *sizeLabel; // 右下角：大小（在 badge 下）
@property (nonatomic, strong) UIImageView *selectIcon; // 右上角 24x24
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

        // ✅ 关键：创建按钮（之前缺这个）
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
        [self.contentView addSubview:_selectBtn]; // ✅ 现在不是 nil 了
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.img.frame = self.contentView.bounds;

    CGFloat pad = 10;
    CGFloat s = 24;
    self.selectIcon.frame = CGRectMake(self.contentView.bounds.size.width - pad - s, pad, s, s);
    self.selectBtn.frame = CGRectInset(self.selectIcon.frame, -8, -8);
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
        _titleLabel.font = [UIFont boldSystemFontOfSize:15];

        _selectAllBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _selectAllBtn.adjustsImageWhenHighlighted = NO;
        _selectAllBtn.showsTouchWhenHighlighted = NO;
        _selectAllBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [_selectAllBtn setTitle:@"Select All" forState:UIControlStateNormal];
        [_selectAllBtn addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];

        [self addSubview:_titleLabel];
        [self addSubview:_selectAllBtn];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat pad = 10;
    self.titleLabel.frame = CGRectMake(pad, 0, self.bounds.size.width - pad*2 - 80, self.bounds.size.height);
    self.selectAllBtn.frame = CGRectMake(self.bounds.size.width - pad - 80, 0, 80, self.bounds.size.height);
}
- (void)onTap { if (self.tapSelectAll) self.tapSelectAll(); }
@end

#pragma mark - Group Card Thumb Cell

@interface ASGroupThumbCell : UICollectionViewCell
@property (nonatomic, copy) NSString *representedLocalId;
@property (nonatomic, strong) UIImageView *imgView;     // 圆图
@property (nonatomic, strong) UIImageView *checkView;   // 右上角 12x12
@property (nonatomic, strong) UIButton *checkBtn;       // 点击勾选/取消
@property (nonatomic, strong) UIButton *previewBtn;     // 点击预览（覆盖整块）
@property (nonatomic, strong) UIImageView *bestBadge;   // ic_best（仅第一个显示）
- (void)applySelected:(BOOL)sel;
- (void)applyBest:(BOOL)isBest;
@end

@implementation ASGroupThumbCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {

        _imgView = [UIImageView new];
        _imgView.contentMode = UIViewContentModeScaleAspectFill;
        _imgView.clipsToBounds = YES;
        _imgView.layer.cornerRadius = 20;
        _imgView.layer.borderWidth = 1;
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

    // 右上角 check 12x12
    CGFloat s = 12;
    self.checkView.frame = CGRectMake(self.contentView.bounds.size.width - s,
                                      0,
                                      s, s);
    self.checkBtn.frame = CGRectInset(self.checkView.frame, -8, -8); // 放大点击区域

    // best badge：底部覆盖（大概居中）
    CGFloat bw = 34, bh = 14;
    self.bestBadge.frame = CGRectMake((self.contentView.bounds.size.width - bw)/2.0,
                                      self.contentView.bounds.size.height - bh + 2,
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

@property (nonatomic) CGFloat cachedLeftW;   // fallback
@property (nonatomic) CGFloat fixedLeftW;    // VC 传下来的统一宽度

@property (nonatomic, copy) NSString *representedBestId;
@property (nonatomic) CGSize lastBestTarget; // 防止反复请求

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
    return ceil([t boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, 100)
                                options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
                             attributes:@{NSFontAttributeName:f}
                                context:nil].size.width);
}

- (void)updateCachedLeftWidth {
    CGFloat pad = 14;

    CGFloat wCount = [self as_textWidth:self.countLabel.text font:self.countLabel.font];
    CGFloat wSize  = [self as_textWidth:self.sizeLabel.text  font:self.sizeLabel.font];

    CGFloat wT1 = [self as_textWidth:@"Select All"   font:self.selectAllBtn.titleLabel.font];
    CGFloat wT2 = [self as_textWidth:@"Deselect All" font:self.selectAllBtn.titleLabel.font];
    CGFloat wTitleMax = MAX(wT1, wT2);

    UIEdgeInsets in = self.selectAllBtn.contentEdgeInsets;
    CGFloat wBtn = wTitleMax + in.left + in.right;

    CGFloat contentW = MAX(MAX(wCount, wSize), wBtn);
    CGFloat leftW = contentW + pad * 2;

    self.cachedLeftW = MIN(180, MAX(110, leftW));
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
        _card.layer.cornerRadius = 22;
        _card.clipsToBounds = YES;

        _leftPanel = [UIView new];
        _leftPanel.backgroundColor = UIColor.whiteColor;

        _countLabel = [UILabel new];
        _countLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightMedium];
        _countLabel.textColor = UIColor.blackColor;

        _sizeLabel = [UILabel new];
        _sizeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _sizeLabel.textColor = [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];

        _selectAllBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _selectAllBtn.adjustsImageWhenHighlighted = NO;
        _selectAllBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _selectAllBtn.backgroundColor = UIColor.clearColor;
        _selectAllBtn.layer.cornerRadius = 18;
        _selectAllBtn.layer.borderWidth = 1;
        _selectAllBtn.contentEdgeInsets = UIEdgeInsetsMake(8, 8, 8, 8);
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
        l.minimumLineSpacing = 10;
        l.minimumInteritemSpacing = 10;

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
                    : (self.cachedLeftW > 0 ? self.cachedLeftW : 120));

    self.leftPanel.frame  = CGRectMake(0, 0, leftW, self.card.bounds.size.height);
    self.rightPanel.frame = CGRectMake(leftW, 0, self.card.bounds.size.width - leftW, self.card.bounds.size.height);

    CGFloat pad = 14;
    CGFloat topY = 18;
    CGFloat lineGap = 2;

    CGFloat y = topY;
    self.countLabel.frame = CGRectMake(pad, y, leftW - pad*2, 26);
    y += 26 + lineGap;
    self.sizeLabel.frame  = CGRectMake(pad, y, leftW - pad*2, 16);

    NSString *t1 = @"Select All";
    NSString *t2 = @"Deselect All";
    CGFloat wT = MAX([self as_textWidth:t1 font:self.selectAllBtn.titleLabel.font],
                     [self as_textWidth:t2 font:self.selectAllBtn.titleLabel.font]);
    UIEdgeInsets in = self.selectAllBtn.contentEdgeInsets;
    CGFloat pillW = ceil(wT + in.left + in.right);
    pillW = MIN(pillW, leftW - pad*2);

    CGFloat btnH = 36;
    CGFloat btnY = self.card.bounds.size.height - 18 - btnH;
    CGFloat btnX = floor((leftW - pillW)/2.0);
    self.selectAllBtn.frame = CGRectMake(btnX, btnY, pillW, btnH);

    self.bestBg.frame = self.rightPanel.bounds;

    CGFloat listH = 56;
    self.thumbCV.frame = CGRectMake(0,
                                    self.rightPanel.bounds.size.height - listH - 10,
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
            [self.selectAllBtn setTitle:@"Deselect All" forState:UIControlStateNormal];
            UIColor *blue = [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];
            [self.selectAllBtn setTitleColor:blue forState:UIControlStateNormal];
            self.selectAllBtn.layer.borderColor = blue.CGColor;
        } else {
            [self.selectAllBtn setTitle:@"Select All" forState:UIControlStateNormal];
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
    self.unitText = unitText ?: @"Photos";
    self.selectedIds = selectedIds ?: [NSSet set];
    self.assetById = assetById ?: @{};
    self.imgMgr = imgMgr;
    self.fixedLeftW = fixedLeftW;

    self.countLabel.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)self.models.count, self.unitText];
    self.sizeLabel.text  = ASHumanSize([self cleanableBytes]);

    [self updateCachedLeftWidth];

    // ✅ bestId 只记录，真正加载交给 layoutSubviews 的 reloadBestBgIfNeeded（有正确 size）
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
    CGSize target = CGSizeMake(40 * scale, 40 * scale);

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
    return CGSizeMake(40, 40);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsMake(8, 14, 8, 14);
}

- (void)onTapCheckBtn:(UIButton *)btn {
    NSInteger idx = btn.tag;
    if (idx < 0 || idx >= (NSInteger)self.models.count) return;
    if (self.onToggleIndex) self.onToggleIndex(self.sectionIndex, idx);
}

- (void)onTapPreviewBtn:(UIButton *)btn {
    NSInteger idx = btn.tag;
    if (idx < 0 || idx >= (NSInteger)self.models.count) return;
    if (self.onPreviewIndex) self.onPreviewIndex(self.sectionIndex, idx);
}

@end

static inline CGFloat ASTextW(NSString *t, UIFont *f) {
    if (t.length == 0) return 0;
    return ceil([t boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, 100)
                                options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
                             attributes:@{NSFontAttributeName:f}
                                context:nil].size.width);
}

static inline CGFloat ASPillW(NSString *title, UIFont *font, CGFloat imgW, CGFloat spacing, UIEdgeInsets insets) {
    return insets.left + imgW + (title.length ? spacing : 0) + ASTextW(title, font) + insets.right;
}

#pragma mark - VC

@interface ASAssetListViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic) ASAssetSortMode sortMode;
@property (nonatomic, strong) UIImageView *homeBgImageView;
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

    UIFont *countFont = [UIFont systemFontOfSize:20 weight:UIFontWeightMedium];
    UIFont *sizeFont  = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    UIFont *btnFont   = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];

    NSString *unit = [self isVideoMode] ? @"Videos" : @"Photos";

    // 卡片左侧 padding（你想更窄就减小）
    CGFloat sidePad = 14;

    // 分组全选胶囊的内边距（和 cell 里保持一致）
    UIEdgeInsets btnInsets = UIEdgeInsetsMake(8, 8, 8, 8);
    CGFloat btnImgW = 0;        // 分组全选按钮没有左图
    CGFloat btnSpacing = 0;

    // ⚠️ 关键：取两种标题里最大宽度，避免 Select/Deselect 切换抖动
    CGFloat btnWMax = MAX(ASPillW(@"Select All", btnFont, btnImgW, btnSpacing, btnInsets),
                          ASPillW(@"Deselect All", btnFont, btnImgW, btnSpacing, btnInsets));

    CGFloat maxContentW = 0;

    for (ASAssetSection *sec in self.sections) {
        NSString *countText = [NSString stringWithFormat:@"%lu %@", (unsigned long)sec.assets.count, unit];
        NSString *sizeText  = ASHumanSize([self cleanableBytesForSection:sec]); // 仍然排除 best 的逻辑

        CGFloat w1 = ASTextW(countText, countFont);
        CGFloat w2 = ASTextW(sizeText,  sizeFont);

        CGFloat contentW = MAX(MAX(w1, w2), btnWMax);
        if (contentW > maxContentW) maxContentW = contentW;
    }

    CGFloat leftW = maxContentW + sidePad * 2;

    // 给一个合理范围（避免太宽/太窄）
    self.groupCardLeftW = MIN(180, MAX(110, leftW));
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = ASBgColor(); // #F6F8FBFF

    UIImageView *bgTop = [UIImageView new];
    bgTop.translatesAutoresizingMaskIntoConstraints = NO;
    bgTop.image = [UIImage imageNamed:@"ic_home_bg"];
    bgTop.contentMode = UIViewContentModeScaleAspectFill;
    bgTop.clipsToBounds = YES;
    bgTop.userInteractionEnabled = NO;
    [self.view addSubview:bgTop];
    [self.view sendSubviewToBack:bgTop];
    self.homeBgImageView = bgTop;

    [NSLayoutConstraint activateConstraints:@[
        [bgTop.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bgTop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bgTop.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bgTop.heightAnchor constraintEqualToConstant:236],
    ]];

    // 只隐藏系统 nav，不影响手势
    self.navigationController.navigationBarHidden = YES;

    // 外部 title 统一从 mode 计算
    NSString *title = [self titleForMode:self.mode];
    self.navBar = [[ASCustomNavBar alloc] initWithTitle:title];
    __weak typeof(self) weakSelf = self;
    self.navBar.onBack = ^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };

    [self.view addSubview:self.navBar];

    // 添加全选按钮到顶部工具栏
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
        });
    });
}


#pragma mark - 自定义布局调整

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat topSafe = self.view.safeAreaInsets.top;
    CGFloat bottomSafe = self.view.safeAreaInsets.bottom;

    CGFloat navH = 44 + topSafe;
    CGFloat toolbarH = 88;      // 两行：44 + 44
    CGFloat floatBtnH = 70;     // 圆角35 => 高度70
    CGFloat floatBtnX = 15;
    CGFloat floatBtnW = self.view.bounds.size.width - 30;

    // navBar
    self.navBar.frame = CGRectMake(0, 0, self.view.bounds.size.width, navH);

    // topToolbar
    self.topToolbar.frame = CGRectMake(0, navH, self.view.bounds.size.width, toolbarH);

    // topToolbar 子视图布局
    CGFloat pad = 16;
    self.topSummaryLabel.frame = CGRectMake(pad, 0, self.topToolbar.bounds.size.width - pad*2, 44);

    CGFloat rowY = 44 + (44 - 36)/2.0;
    CGFloat btnH = 36;
    CGFloat gap = 10;

    CGFloat w1 = [self pillWidthForButton:self.topSelectAllBtn height:btnH];
    CGFloat w2 = [self pillWidthForButton:self.topSortBtn height:btnH];

    w1 = MAX(96, w1);
    w2 = MAX(96, w2);

    CGFloat maxTotal = self.topToolbar.bounds.size.width - pad*2;
    CGFloat totalNeed = w1 + gap + w2;

    if (totalNeed > maxTotal) {
        CGFloat minGap = 6;
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

    CGFloat cvY = navH + toolbarH;
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

    // 第一行：居中 summary
    UILabel *summary = [UILabel new];
    summary.textAlignment = NSTextAlignmentCenter;
    summary.numberOfLines = 1;
    summary.adjustsFontSizeToFitWidth = YES;
    summary.minimumScaleFactor = 0.8;
    summary.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.topSummaryLabel = summary;

    ASNoHighlightButton *selectAllBtn = [ASNoHighlightButton buttonWithType:UIButtonTypeCustom];
    [self configPillButtonBase:selectAllBtn];
    [selectAllBtn addTarget:self action:@selector(toggleSelectAll) forControlEvents:UIControlEventTouchUpInside];
    self.topSelectAllBtn = selectAllBtn;

    ASNoHighlightButton *sortBtn = [ASNoHighlightButton buttonWithType:UIButtonTypeCustom];
    [self configPillButtonBase:sortBtn];
    [sortBtn addTarget:self action:@selector(onTapSort) forControlEvents:UIControlEventTouchUpInside];
    self.topSortBtn = sortBtn;

    // 初始 UI
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
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Sort"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;

    void (^apply)(ASAssetSortMode) = ^(ASAssetSortMode m) {
        weakSelf.sortMode = m;
        [weakSelf applyCurrentSortAndReload];
    };

    [ac addAction:[UIAlertAction actionWithTitle:@"Newest"
                                          style:UIAlertActionStyleDefault
                                        handler:^(__unused UIAlertAction * _Nonnull action) {
        apply(ASAssetSortModeNewest);
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"Oldest"
                                          style:UIAlertActionStyleDefault
                                        handler:^(__unused UIAlertAction * _Nonnull action) {
        apply(ASAssetSortModeOldest);
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"Largest"
                                          style:UIAlertActionStyleDefault
                                        handler:^(__unused UIAlertAction * _Nonnull action) {
        apply(ASAssetSortModeLargest);
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"Smallest"
                                          style:UIAlertActionStyleDefault
                                        handler:^(__unused UIAlertAction * _Nonnull action) {
        apply(ASAssetSortModeSmallest);
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];

    [self presentViewController:ac animated:YES completion:nil];
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
    NSString *unit = [self isVideoMode] ? @"Videos" : @"Photos";

    NSString *full = [NSString stringWithFormat:@"%@ Free Up |  %@ / %@ %@", freeStr, cleanableStr, totalStr, unit];

    UIColor *blue = [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0]; // #024DFFFF
    UIColor *gray = [UIColor colorWithRed:0x66/255.0 green:0x66/255.0 blue:0x66/255.0 alpha:1.0]; // #666666FF
    UIFont *font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];

    NSMutableAttributedString *att = [[NSMutableAttributedString alloc] initWithString:full attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: gray
    }];

    // 把 “freeStr” 和 “cleanableStr” 染成蓝色
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
        layout.minimumLineSpacing = 10;
        layout.sectionInset = [self useVideoGroupStyle] ? UIEdgeInsetsMake(10, 20, 0, 20)
                                                        : UIEdgeInsetsMake(10, 20, 0, 20);
        layout.headerReferenceSize = CGSizeZero;
    } else {
        layout.minimumInteritemSpacing = 2;
        layout.minimumLineSpacing = 2;
        layout.sectionInset = UIEdgeInsetsMake(10, 10, 10, 10);
        layout.headerReferenceSize = CGSizeMake(self.view.bounds.size.width, 44);
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
        self.cv.opaque = NO; // 更彻底，避免系统当成不透明渲染
        [self.view addSubview:self.cv];
    } else {
        UIView *bg = [UIView new];
        bg.backgroundColor = UIColor.whiteColor;
        bg.layer.cornerRadius = 16;
        bg.layer.masksToBounds = YES;
        if (@available(iOS 11.0, *)) {
            bg.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        }
        self.listBgView = bg;
        [self.view addSubview:bg];

        self.cv.backgroundColor = UIColor.clearColor;
        [bg addSubview:self.cv];
    }

    UIView *bar = [UIView new];
    bar.backgroundColor = UIColor.clearColor;
    bar.userInteractionEnabled = YES;

    ASNoHighlightButton *btn = [ASNoHighlightButton buttonWithType:UIButtonTypeCustom];
    btn.userInteractionEnabled = YES;

    btn.layer.cornerRadius = 35;
    btn.layer.masksToBounds = YES;
    btn.backgroundColor = [UIColor colorWithRed:0x02/255.0 green:0x4D/255.0 blue:0xFF/255.0 alpha:1.0];

    btn.layer.shadowOpacity = 0;
    btn.layer.shadowRadius = 0;
    btn.layer.shadowPath = nil;

    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
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
    UIFont *f = btn.titleLabel.font ?: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];

    CGFloat textW = ceil([t boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, h)
                                        options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
                                     attributes:@{NSFontAttributeName:f}
                                        context:nil].size.width);

    CGFloat imgW = 0;
    UIImage *img = [btn imageForState:UIControlStateNormal];
    if (img) imgW = ceil(img.size.width);

    UIEdgeInsets in = btn.contentEdgeInsets;
    CGFloat spacing = (img && t.length) ? 6 : 0;

    return ceil(in.left + imgW + spacing + textW + in.right);
}

- (void)configPillButtonBase:(UIButton *)btn {
    btn.backgroundColor = UIColor.whiteColor;
    btn.layer.cornerRadius = 18;
    btn.layer.masksToBounds = YES;

    btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    btn.titleLabel.numberOfLines = 1;
    btn.titleLabel.lineBreakMode = NSLineBreakByClipping;
    btn.titleLabel.adjustsFontSizeToFitWidth = NO;

    [btn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];

    btn.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;

    btn.contentEdgeInsets = UIEdgeInsetsMake(6, 8, 6, 8);

    btn.imageEdgeInsets = UIEdgeInsetsZero;
    btn.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 0);
}

- (NSString *)sortTitle {
    switch (self.sortMode) {
        case ASAssetSortModeNewest:   return @"Newest";
        case ASAssetSortModeOldest:   return @"Oldest";
        case ASAssetSortModeLargest:  return @"Largest";
        case ASAssetSortModeSmallest: return @"Smallest";
    }
    return @"Newest";
}

- (void)updateTopSelectAllButtonUIWithAll:(BOOL)all {
    [self updatePillButton:self.topSelectAllBtn
                 imageName:(all ? @"ic_select_s" : @"ic_select_gray_n")
                     title:(all ? @"Deselect All" : @"Select All")];
}

- (void)updateTopSortButtonUI {
    [self updatePillButton:self.topSortBtn imageName:@"ic_sort" title:[self sortTitle]];
}

#pragma mark - Build data

- (NSString *)titleForMode:(ASAssetListMode)mode {
    switch (mode) {
        case ASAssetListModeSimilarImage: return @"Similar Photos";
        case ASAssetListModeSimilarVideo: return @"Similar Videos";
        case ASAssetListModeDuplicateImage: return @"Duplicate Photos";
        case ASAssetListModeDuplicateVideo: return @"Duplicate Videos";
        case ASAssetListModeScreenshots: return @"Screenshots";
        case ASAssetListModeScreenRecordings: return @"Screen Recoeding";
        case ASAssetListModeBigVideos: return @"Big Videos";
        case ASAssetListModeBlurryPhotos: return @"Blurry Photos";
        case ASAssetListModeOtherPhotos: return @"Other Photos";
    }
    return @"List";
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

        // 先建 section（这一步只处理 ASAssetModel，不触碰 PHAsset）
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
            sec.title = [NSString stringWithFormat:@"第 %ld 组（%lu）", (long)idx, (unsigned long)sec.assets.count];
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

    // 去重（避免 fetch 重复 id）
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

    // ✅ 过滤掉 asset 不存在的 model（避免列表里出现空格子/闪）
    for (NSInteger si = self.sections.count - 1; si >= 0; si--) {
        ASAssetSection *sec = self.sections[si];

        NSMutableArray<ASAssetModel *> *kept = [NSMutableArray arrayWithCapacity:sec.assets.count];
        for (ASAssetModel *m in sec.assets) {
            if (!m.localId.length) continue;
            if (!self.assetById[m.localId]) continue;
            [kept addObject:m];
        }

        sec.assets = kept;

        // 分组：不足 2 就整组丢掉
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

        // 分组标题序号重排
        NSInteger idx = 1;
        for (ASAssetSection *sec in self.sections) {
            sec.title = [NSString stringWithFormat:@"第 %ld 组（%lu）", (long)idx, (unsigned long)sec.assets.count];
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

    NSSet<NSString *> *toDelete = [self.selectedIds copy];
    NSArray<NSString *> *ids = toDelete.allObjects;

    PHFetchResult<PHAsset *> *fr = [PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
    if (fr.count == 0) return;

    __weak typeof(self) weakSelf = self;

    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest deleteAssets:fr];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!success) return;

            [weakSelf.selectedIds removeAllObjects];

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [weakSelf rebuildDataFromManager];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf applyDefaultSelectionRule];
                    [weakSelf.cv reloadData];
                    [weakSelf recomputeBytesAndRefreshUI];
                    [weakSelf syncNavSelectAllState];
                });
            });
        });
    }];
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
    if ([self isGroupMode]) return 1;          // ✅ 一组一个卡片
    return self.sections[section].assets.count; // 非分组保持原样
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {

    if ([self isGroupMode]) {
        ASAssetSection *sec = self.sections[indexPath.section];
        NSString *unit = [self isVideoMode] ? @"Videos" : @"Photos";
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

        // ✅ 非视频：保持你原来的样式完全不变
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
    NSInteger start = grouped ? 1 : 0;

    // 先清掉该 section 所有可选项
    for (NSInteger i = start; i < (NSInteger)sec.assets.count; i++) {
        ASAssetModel *m = sec.assets[i];
        if (m.localId.length) [self.selectedIds removeObject:m.localId];
    }

    // 再把 idxSet 里勾选的加回来（分组会自动忽略 0）
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
        // 用 indexSet 回写 selectedIds（保持 best 不选）
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
            title = [NSString stringWithFormat:@"Delete %lu Videos (%@)",
                     (unsigned long)selCount,
                     ASHumanSize(self.selectedBytes)];
        } else {
            title = [NSString stringWithFormat:@"Delete %lu Photos (%@)",
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
    p.showsBestBadge = NO; // ✅ 单个预览不显示 best

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
    return [self isGroupMode] ? CGSizeMake(collectionView.bounds.size.width, 44) : CGSizeZero;
}

@end
