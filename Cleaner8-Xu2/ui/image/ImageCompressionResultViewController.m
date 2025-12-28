#import "ImageCompressionResultViewController.h"
#import <Photos/Photos.h>

static inline UIColor *ASBlue(void) { return [UIColor colorWithRed:2/255.0 green:77/255.0 blue:255/255.0 alpha:1.0]; }
static inline UIFont *ASSB(CGFloat s){ return [UIFont systemFontOfSize:s weight:UIFontWeightSemibold]; }
static inline UIFont *ASBD(CGFloat s){ return [UIFont systemFontOfSize:s weight:UIFontWeightBold]; }
static inline UIFont *ASRG(CGFloat s){ return [UIFont systemFontOfSize:s weight:UIFontWeightRegular]; }
static NSString *ASMB1(uint64_t bytes){ double mb=(double)bytes/(1024.0*1024.0); return [NSString stringWithFormat:@"%.1fMB",mb]; }

@interface ImageCompressionResultViewController ()
@property (nonatomic, strong) ASImageCompressionSummary *summary;

@property (nonatomic, strong) UIButton *backBtn;

@property (nonatomic, strong) UILabel *greatLabel;
@property (nonatomic, strong) UILabel *descLabel;

@property (nonatomic, strong) UIView *tableCard;

@property (nonatomic, strong) UIView *sheet;
@property (nonatomic, strong) NSLayoutConstraint *sheetBottomC;
@end

@implementation ImageCompressionResultViewController

- (instancetype)initWithSummary:(ASImageCompressionSummary *)summary {
    if (self = [super init]) {
        _summary = summary;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBarHidden = YES;
    self.view.backgroundColor = UIColor.whiteColor;

    [self buildUI];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self showDeleteSheet];
}

#pragma mark - UI

- (void)buildUI {
    self.backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.backBtn.tintColor = ASBlue();
    if (@available(iOS 13.0,*)) [self.backBtn setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    [self.backBtn addTarget:self action:@selector(onBack) forControlEvents:UIControlEventTouchUpInside];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.backBtn];

    // illustration placeholder (你有资源可替换)
    UIView *illus = [UIView new];
    illus.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:illus];

    self.greatLabel = [UILabel new];
    self.greatLabel.text = @"Great!";
    self.greatLabel.font = ASBD(48);
    self.greatLabel.textColor = UIColor.blackColor;
    self.greatLabel.textAlignment = NSTextAlignmentCenter;
    self.greatLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.descLabel = [UILabel new];
    self.descLabel.font = ASRG(18);
    self.descLabel.textColor = [UIColor colorWithWhite:0.15 alpha:1];
    self.descLabel.numberOfLines = 0;
    self.descLabel.textAlignment = NSTextAlignmentCenter;
    self.descLabel.text = [NSString stringWithFormat:@"%ld photos have been compressed and saved to\nyour system album", (long)self.summary.inputCount];
    self.descLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:self.greatLabel];
    [self.view addSubview:self.descLabel];

    // summary table card (blue border)
    self.tableCard = [UIView new];
    self.tableCard.layer.cornerRadius = 22;
    self.tableCard.layer.borderWidth = 2;
    self.tableCard.layer.borderColor = ASBlue().CGColor;
    self.tableCard.backgroundColor = [UIColor colorWithRed:231/255.0 green:240/255.0 blue:255/255.0 alpha:1];
    self.tableCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableCard];

    UIView *sep1 = [UIView new]; sep1.backgroundColor = [UIColor colorWithRed:168/255.0 green:196/255.0 blue:255/255.0 alpha:1];
    UIView *sep2 = [UIView new]; sep2.backgroundColor = sep1.backgroundColor;
    sep1.translatesAutoresizingMaskIntoConstraints = NO;
    sep2.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableCard addSubview:sep1];
    [self.tableCard addSubview:sep2];

    UILabel *(^colTitle)(NSString*) = ^UILabel*(NSString *t){
        UILabel *l=[UILabel new];
        l.text=t; l.font=ASSB(20); l.textColor=UIColor.blackColor; l.textAlignment=NSTextAlignmentCenter;
        l.translatesAutoresizingMaskIntoConstraints=NO;
        return l;
    };
    UILabel *(^colSub)(NSString*) = ^UILabel*(NSString *t){
        UILabel *l=[UILabel new];
        l.text=t; l.font=ASRG(16); l.textColor=[UIColor colorWithWhite:0 alpha:0.65]; l.textAlignment=NSTextAlignmentCenter;
        l.translatesAutoresizingMaskIntoConstraints=NO;
        return l;
    };
    UILabel *(^colVal)(NSString*, BOOL) = ^UILabel*(NSString *t, BOOL blue){
        UILabel *l=[UILabel new];
        l.text=t; l.font=ASSB(28); l.textColor=blue?ASBlue():UIColor.blackColor; l.textAlignment=NSTextAlignmentCenter;
        l.translatesAutoresizingMaskIntoConstraints=NO;
        return l;
    };

    UIView *c1=[UIView new], *c2=[UIView new], *c3=[UIView new];
    for (UIView *v in @[c1,c2,c3]) { v.translatesAutoresizingMaskIntoConstraints=NO; [self.tableCard addSubview:v]; }

    UILabel *t1=colTitle(@"Before"); UILabel *s1=colSub(@"Compression"); UILabel *v1=colVal(ASMB1(self.summary.beforeBytes), NO);
    UILabel *t2=colTitle(@"After");  UILabel *s2=colSub(@"Compression"); UILabel *v2=colVal(ASMB1(self.summary.afterBytes), YES);
    UILabel *t3=colTitle(@"Space Saved"); UILabel *v3=colVal(ASMB1(self.summary.savedBytes), YES);

    for (UILabel *l in @[t1,s1,v1]) [c1 addSubview:l];
    for (UILabel *l in @[t2,s2,v2]) [c2 addSubview:l];
    for (UILabel *l in @[t3,v3]) [c3 addSubview:l];

    [NSLayoutConstraint activateConstraints:@[
        [self.backBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.backBtn.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],
        [self.backBtn.widthAnchor constraintEqualToConstant:44],
        [self.backBtn.heightAnchor constraintEqualToConstant:44],

        [illus.topAnchor constraintEqualToAnchor:self.backBtn.bottomAnchor constant:40],
        [illus.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [illus.widthAnchor constraintEqualToConstant:220],
        [illus.heightAnchor constraintEqualToConstant:180],

        [self.greatLabel.topAnchor constraintEqualToAnchor:illus.bottomAnchor constant:10],
        [self.greatLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.greatLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.descLabel.topAnchor constraintEqualToAnchor:self.greatLabel.bottomAnchor constant:10],
        [self.descLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:30],
        [self.descLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-30],

        [self.tableCard.topAnchor constraintEqualToAnchor:self.descLabel.bottomAnchor constant:26],
        [self.tableCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.tableCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [self.tableCard.heightAnchor constraintEqualToConstant:140],
    ]];

    // columns layout
    [NSLayoutConstraint activateConstraints:@[
        [c1.leadingAnchor constraintEqualToAnchor:self.tableCard.leadingAnchor],
        [c1.topAnchor constraintEqualToAnchor:self.tableCard.topAnchor],
        [c1.bottomAnchor constraintEqualToAnchor:self.tableCard.bottomAnchor],

        [c2.topAnchor constraintEqualToAnchor:self.tableCard.topAnchor],
        [c2.bottomAnchor constraintEqualToAnchor:self.tableCard.bottomAnchor],

        [c3.trailingAnchor constraintEqualToAnchor:self.tableCard.trailingAnchor],
        [c3.topAnchor constraintEqualToAnchor:self.tableCard.topAnchor],
        [c3.bottomAnchor constraintEqualToAnchor:self.tableCard.bottomAnchor],

        [c1.widthAnchor constraintEqualToAnchor:self.tableCard.widthAnchor multiplier:1.0/3.0],
        [c2.widthAnchor constraintEqualToAnchor:self.tableCard.widthAnchor multiplier:1.0/3.0],
        [c3.widthAnchor constraintEqualToAnchor:self.tableCard.widthAnchor multiplier:1.0/3.0],

        [c2.leadingAnchor constraintEqualToAnchor:c1.trailingAnchor],
        [c3.leadingAnchor constraintEqualToAnchor:c2.trailingAnchor],

        [sep1.widthAnchor constraintEqualToConstant:1],
        [sep1.topAnchor constraintEqualToAnchor:self.tableCard.topAnchor],
        [sep1.bottomAnchor constraintEqualToAnchor:self.tableCard.bottomAnchor],
        [sep1.leadingAnchor constraintEqualToAnchor:c2.leadingAnchor],

        [sep2.widthAnchor constraintEqualToConstant:1],
        [sep2.topAnchor constraintEqualToAnchor:self.tableCard.topAnchor],
        [sep2.bottomAnchor constraintEqualToAnchor:self.tableCard.bottomAnchor],
        [sep2.leadingAnchor constraintEqualToAnchor:c3.leadingAnchor],
    ]];

    // c1 content
    [NSLayoutConstraint activateConstraints:@[
        [t1.topAnchor constraintEqualToAnchor:c1.topAnchor constant:18],
        [t1.leadingAnchor constraintEqualToAnchor:c1.leadingAnchor],
        [t1.trailingAnchor constraintEqualToAnchor:c1.trailingAnchor],
        [s1.topAnchor constraintEqualToAnchor:t1.bottomAnchor constant:2],
        [s1.leadingAnchor constraintEqualToAnchor:c1.leadingAnchor],
        [s1.trailingAnchor constraintEqualToAnchor:c1.trailingAnchor],
        [v1.bottomAnchor constraintEqualToAnchor:c1.bottomAnchor constant:-18],
        [v1.leadingAnchor constraintEqualToAnchor:c1.leadingAnchor],
        [v1.trailingAnchor constraintEqualToAnchor:c1.trailingAnchor],
    ]];
    // c2 content
    [NSLayoutConstraint activateConstraints:@[
        [t2.topAnchor constraintEqualToAnchor:c2.topAnchor constant:18],
        [t2.leadingAnchor constraintEqualToAnchor:c2.leadingAnchor],
        [t2.trailingAnchor constraintEqualToAnchor:c2.trailingAnchor],
        [s2.topAnchor constraintEqualToAnchor:t2.bottomAnchor constant:2],
        [s2.leadingAnchor constraintEqualToAnchor:c2.leadingAnchor],
        [s2.trailingAnchor constraintEqualToAnchor:c2.trailingAnchor],
        [v2.bottomAnchor constraintEqualToAnchor:c2.bottomAnchor constant:-18],
        [v2.leadingAnchor constraintEqualToAnchor:c2.leadingAnchor],
        [v2.trailingAnchor constraintEqualToAnchor:c2.trailingAnchor],
    ]];
    // c3 content
    [NSLayoutConstraint activateConstraints:@[
        [t3.topAnchor constraintEqualToAnchor:c3.topAnchor constant:24],
        [t3.leadingAnchor constraintEqualToAnchor:c3.leadingAnchor],
        [t3.trailingAnchor constraintEqualToAnchor:c3.trailingAnchor],
        [v3.bottomAnchor constraintEqualToAnchor:c3.bottomAnchor constant:-18],
        [v3.leadingAnchor constraintEqualToAnchor:c3.leadingAnchor],
        [v3.trailingAnchor constraintEqualToAnchor:c3.trailingAnchor],
    ]];

    // bottom sheet
    self.sheet = [UIView new];
    self.sheet.backgroundColor = UIColor.whiteColor;
    self.sheet.layer.cornerRadius = 28;
    if (@available(iOS 11.0,*)) self.sheet.layer.maskedCorners = kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner;
    self.sheet.layer.masksToBounds = YES;
    self.sheet.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.sheet];

    UILabel *sheetTitle = [UILabel new];
    sheetTitle.text = @"Delete original Image ?";
    sheetTitle.font = ASSB(28);
    sheetTitle.textColor = UIColor.blackColor;
    sheetTitle.textAlignment = NSTextAlignmentCenter;
    sheetTitle.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *reserve = [UIButton buttonWithType:UIButtonTypeSystem];
    [reserve setTitle:@"Reserve" forState:UIControlStateNormal];
    reserve.titleLabel.font = ASSB(22);
    [reserve setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    reserve.backgroundColor = ASBlue();
    reserve.layer.cornerRadius = 28;
    reserve.layer.masksToBounds = YES;
    reserve.translatesAutoresizingMaskIntoConstraints = NO;
    [reserve addTarget:self action:@selector(onReserve) forControlEvents:UIControlEventTouchUpInside];

    UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
    [del setTitle:@"Delete" forState:UIControlStateNormal];
    del.titleLabel.font = ASSB(22);
    [del setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    del.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1];
    del.layer.cornerRadius = 28;
    del.layer.masksToBounds = YES;
    del.translatesAutoresizingMaskIntoConstraints = NO;
    [del addTarget:self action:@selector(onDelete) forControlEvents:UIControlEventTouchUpInside];

    [self.sheet addSubview:sheetTitle];
    [self.sheet addSubview:reserve];
    [self.sheet addSubview:del];

    [NSLayoutConstraint activateConstraints:@[
        [self.sheet.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.sheet.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.sheet.heightAnchor constraintEqualToConstant:260],

        [sheetTitle.topAnchor constraintEqualToAnchor:self.sheet.topAnchor constant:26],
        [sheetTitle.leadingAnchor constraintEqualToAnchor:self.sheet.leadingAnchor constant:20],
        [sheetTitle.trailingAnchor constraintEqualToAnchor:self.sheet.trailingAnchor constant:-20],

        [reserve.topAnchor constraintEqualToAnchor:sheetTitle.bottomAnchor constant:22],
        [reserve.leadingAnchor constraintEqualToAnchor:self.sheet.leadingAnchor constant:28],
        [reserve.trailingAnchor constraintEqualToAnchor:self.sheet.trailingAnchor constant:-28],
        [reserve.heightAnchor constraintEqualToConstant:72],

        [del.topAnchor constraintEqualToAnchor:reserve.bottomAnchor constant:16],
        [del.leadingAnchor constraintEqualToAnchor:self.sheet.leadingAnchor constant:28],
        [del.trailingAnchor constraintEqualToAnchor:self.sheet.trailingAnchor constant:-28],
        [del.heightAnchor constraintEqualToConstant:72],
    ]];

    // start hidden (below)
    self.sheetBottomC = [self.sheet.topAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    self.sheetBottomC.active = YES;
}

- (void)showDeleteSheet {
    if (self.sheetBottomC) self.sheetBottomC.active = NO;
    self.sheetBottomC = [self.sheet.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    self.sheetBottomC.active = YES;

    [UIView animateWithDuration:0.25 animations:^{
        [self.view layoutIfNeeded];
    }];
}

#pragma mark - Actions

- (void)onBack {
    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)onReserve {
    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)onDelete {
    NSArray<PHAsset *> *orig = self.summary.originalAssets ?: @[];
    if (orig.count == 0) {
        [self.navigationController popToRootViewControllerAnimated:YES];
        return;
    }

    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest deleteAssets:orig];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.navigationController popToRootViewControllerAnimated:YES];
        });
    }];
}

@end
