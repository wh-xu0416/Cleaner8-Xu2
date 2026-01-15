#import "PaywallViewController.h"
#import "SubscriptionViewController.h"
#import "Cleaner8_Xu2-Swift.h"
#import "LTEventTracker.h"

static inline NSString *L(NSString *key) { return NSLocalizedString(key, nil); }
static inline NSString *LF(NSString *key, ...) {
    va_list args; va_start(args, key);
    NSString *format = NSLocalizedString(key, nil);
    NSString *str = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args); return str;
}

@interface PaywallViewController ()
@property(nonatomic,strong) UIButton *subscribeBtn;
@property(nonatomic,strong) UIButton *restoreBtn;
@property(nonatomic,strong) UIButton *morePlansBtn;
@property(nonatomic,strong) UILabel *priceLab;
@property(nonatomic,strong) UIButton *backBtn;
@property(nonatomic,assign) BOOL allowDismiss;
@property(nonatomic,strong) UILabel *netTipLab;
@end

@implementation PaywallViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.allowDismiss = YES;

    [[StoreKit2Manager shared] start];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onSubscriptionChanged)
                                                 name:@"subscriptionStateChanged"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onProductsUpdated)
                                                 name:@"storeProductsUpdated"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onNetworkChanged)
                                                 name:@"storeNetworkChanged"
                                               object:nil];

    [self buildUI];
    [self refreshWeeklyUI];

//    [[LTEventTracker shared] track:(@"sub_show") properties:@{@"IAP": @"c_af_init"}];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onNetworkChanged {
    [self refreshWeeklyUI];
}

- (SK2ProductModel *)weeklyProduct {
    for (SK2ProductModel *p in [StoreKit2Manager shared].products) {
        if ([p.productID containsString:@"weekly"]) return p;
    }
    return nil;
}

- (void)refreshWeeklyUI {
    BOOL hasNet = [StoreKit2Manager shared].networkAvailable;
    SK2ProductModel *weekly = [self weeklyProduct];

    if (!hasNet) {
        NSString *tip = L(@"common.network_tip_to_settings");
        NSMutableAttributedString *att = [[NSMutableAttributedString alloc] initWithString:tip];
        [att addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:NSMakeRange(0, tip.length)];
        self.netTipLab.attributedText = att;
        self.netTipLab.hidden = NO;
    } else {
        self.netTipLab.hidden = YES;
    }

    if (weekly) {
        [self.subscribeBtn setTitle:LF(@"paywall.subscribe_weekly_with_price", weekly.displayPrice)
                           forState:UIControlStateNormal];
        self.subscribeBtn.enabled = hasNet;
        self.priceLab.text = weekly.displayName ?: L(@"paywall.weekly_fallback");
    } else {
        [self.subscribeBtn setTitle:L(@"paywall.subscribe_weekly") forState:UIControlStateNormal];
        self.subscribeBtn.enabled = NO;
        self.priceLab.text = hasNet ? L(@"common.loading") : L(@"common.waiting_connection");
    }

    self.restoreBtn.enabled = hasNet;
}


- (void)onProductsUpdated {
    [self refreshWeeklyUI];
}

- (void)onSubscriptionChanged {
    if ([StoreKit2Manager shared].state == SubscriptionStateActive) {
        if (self.presentingViewController) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }
}

#pragma mark - UI

- (void)buildUI {
    self.backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.backBtn setTitle:L(@"common.back") forState:UIControlStateNormal];
    self.backBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [self.backBtn addTarget:self action:@selector(tapBack) forControlEvents:UIControlEventTouchUpInside];
    self.backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.backBtn];

    [NSLayoutConstraint activateConstraints:@[
        [self.backBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.backBtn.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.backBtn.heightAnchor constraintEqualToConstant:36],
    ]];
    self.backBtn.hidden = !self.allowDismiss;

    UILabel *title = [[UILabel alloc] init];
    title.text = L(@"paywall.unlock_pro");
    title.font = [UIFont boldSystemFontOfSize:28];
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    self.priceLab = [[UILabel alloc] init];
    self.priceLab.textAlignment = NSTextAlignmentCenter;
    self.priceLab.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    self.priceLab.textColor = [UIColor darkGrayColor];
    self.priceLab.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.priceLab];

    self.netTipLab = [[UILabel alloc] init];
    self.netTipLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.netTipLab.textAlignment = NSTextAlignmentCenter;
    self.netTipLab.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.netTipLab.textColor = [UIColor systemBlueColor];
    self.netTipLab.userInteractionEnabled = YES;
    self.netTipLab.hidden = YES;

    // 整行可点
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapNetworkTip)];
    [self.netTipLab addGestureRecognizer:tap];

    [self.view addSubview:self.netTipLab];

    self.subscribeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.subscribeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.subscribeBtn addTarget:self action:@selector(tapSubscribe) forControlEvents:UIControlEventTouchUpInside];
    self.subscribeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.subscribeBtn];

    self.morePlansBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.morePlansBtn setTitle:L(@"paywall.see_all_plans") forState:UIControlStateNormal];
    [self.morePlansBtn addTarget:self action:@selector(tapMorePlans) forControlEvents:UIControlEventTouchUpInside];
    self.morePlansBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.morePlansBtn];

    self.restoreBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.restoreBtn setTitle:L(@"common.restore_purchase") forState:UIControlStateNormal];
    [self.restoreBtn addTarget:self action:@selector(tapRestore) forControlEvents:UIControlEventTouchUpInside];
    self.restoreBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.restoreBtn];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:80],
        [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.priceLab.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:16],
        [self.priceLab.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.netTipLab.topAnchor constraintEqualToAnchor:self.priceLab.bottomAnchor constant:10],
        [self.netTipLab.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.subscribeBtn.topAnchor constraintEqualToAnchor:self.netTipLab.bottomAnchor constant:20],
        [self.subscribeBtn.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.subscribeBtn.widthAnchor constraintEqualToConstant:260],
        [self.subscribeBtn.heightAnchor constraintEqualToConstant:48],

        [self.morePlansBtn.topAnchor constraintEqualToAnchor:self.subscribeBtn.bottomAnchor constant:14],
        [self.morePlansBtn.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.restoreBtn.topAnchor constraintEqualToAnchor:self.morePlansBtn.bottomAnchor constant:24],
        [self.restoreBtn.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    ]];
}

#pragma mark - Actions

- (void)tapBack {
    if (!self.allowDismiss) return;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)tapSubscribe {
    if (![StoreKit2Manager shared].networkAvailable) return;

    SK2ProductModel *weekly = [self weeklyProduct];
    if (!weekly) return;

    self.subscribeBtn.enabled = NO;

    [[StoreKit2Manager shared] purchaseWithProductID:weekly.productID completion:^(BOOL ok) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.subscribeBtn.enabled = !ok && [StoreKit2Manager shared].networkAvailable;
        });
    }];
}

- (void)tapMorePlans {
    SubscriptionViewController *vc = [SubscriptionViewController new];
    vc.source = self.source;
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)tapRestore {
    if (![StoreKit2Manager shared].networkAvailable) return;

    self.restoreBtn.enabled = NO;
    [[StoreKit2Manager shared] restoreWithCompletion:^(BOOL ok) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.restoreBtn.enabled = [StoreKit2Manager shared].networkAvailable;
        });
    }];
}

- (void)tapNetworkTip {
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if (!url) return;

    if (@available(iOS 10.0, *)) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        [[UIApplication sharedApplication] openURL:url];
    }
}

@end
