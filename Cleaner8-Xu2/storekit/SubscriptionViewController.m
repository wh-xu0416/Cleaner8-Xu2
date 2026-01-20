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

@interface SubscriptionViewController ()
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) UIButton *restoreBtn;
@property(nonatomic,strong) UILabel *loadingLab;
@property(nonatomic,strong) UIButton *backBtn;
@property(nonatomic,assign) BOOL allowDismiss;
@property(nonatomic,strong) UILabel *netTipLab;
@property(nonatomic,strong) NSLayoutConstraint *stackTopCst;
@end

@implementation SubscriptionViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.allowDismiss = YES;

    [[StoreKit2Manager shared] start];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onStoreSnapshotChanged:)
                                                 name:@"storeSnapshotChanged"
                                               object:nil];

    [self buildUI];
    [self render];
    [[StoreKit2Manager shared] uploadIAPIdentifiersOnEnterPaywall];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onStoreSnapshotChanged:(NSNotification *)note {
    [self render];
}

#pragma mark - Render

- (void)render {
    // 清空列表
    for (UIView *v in self.stack.arrangedSubviews) {
        [self.stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    StoreSnapshot *snap = [StoreKit2Manager shared].snapshot;
    BOOL hasNet = snap.networkAvailable;
    
    BOOL busy = (snap.purchaseState == PurchaseFlowStatePurchasing ||
                 snap.purchaseState == PurchaseFlowStateRestoring ||
                 snap.purchaseState == PurchaseFlowStatePending);

    // 无网提示
    if (!hasNet) {
        NSString *tip = L(@"common.network_tip_to_settings");
        NSMutableAttributedString *att = [[NSMutableAttributedString alloc] initWithString:tip];
        [att addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle)
                   range:NSMakeRange(0, tip.length)];
        self.netTipLab.attributedText = att;
        self.netTipLab.hidden = NO;
    } else {
        self.netTipLab.hidden = YES;
    }

    // 顶部 loading / error
    if (!hasNet) {
        self.loadingLab.hidden = NO;
        self.loadingLab.text = L(@"common.waiting_connection");
        self.restoreBtn.enabled = NO;
        return;
    }

    if (snap.productsState == ProductsLoadStateIdle ||
        snap.productsState == ProductsLoadStateLoading) {
        self.loadingLab.hidden = NO;
        self.loadingLab.text = L(@"common.loading");
        self.restoreBtn.enabled = NO;
        return;
    }

    if (snap.productsState == ProductsLoadStateFailed && snap.products.count == 0) {
        self.loadingLab.hidden = NO;
        self.loadingLab.text = (snap.lastErrorMessage.length > 0) ? snap.lastErrorMessage : L(@"common.loading");
        self.restoreBtn.enabled = hasNet && !busy;
        return;
    }

    self.loadingLab.hidden = YES;

    // 列表
    NSInteger idx = 0;
    for (SK2ProductModel *p in snap.products) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];

        NSString *line = LF(@"subscription.plan_item_format", p.displayName, p.displayPrice);
        [btn setTitle:line forState:UIControlStateNormal];

        btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        btn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        btn.tag = idx++;
        btn.layer.cornerRadius = 10;
        btn.layer.borderWidth = 1;
        btn.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.12].CGColor;
        btn.contentEdgeInsets = UIEdgeInsetsMake(14, 14, 14, 14);

        // 有网 + 不忙 才能点
        btn.enabled = hasNet && !busy;

        [btn addTarget:self action:@selector(tapProduct:) forControlEvents:UIControlEventTouchUpInside];
        [self.stack addArrangedSubview:btn];
    }

    self.restoreBtn.enabled = hasNet && !busy;

    // 已订阅 => 自动关闭
    if (snap.subscriptionState == SubscriptionStateActive) {
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
    title.text = L(@"subscription.choose_plan");
    title.font = [UIFont boldSystemFontOfSize:26];
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    self.loadingLab = [[UILabel alloc] init];
    self.loadingLab.textAlignment = NSTextAlignmentCenter;
    self.loadingLab.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    self.loadingLab.textColor = [UIColor darkGrayColor];
    self.loadingLab.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.loadingLab];

    self.netTipLab = [[UILabel alloc] init];
    self.netTipLab.translatesAutoresizingMaskIntoConstraints = NO;
    self.netTipLab.textAlignment = NSTextAlignmentCenter;
    self.netTipLab.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.netTipLab.textColor = [UIColor systemBlueColor];
    self.netTipLab.numberOfLines = 2;
    self.netTipLab.userInteractionEnabled = YES;
    self.netTipLab.hidden = YES;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapNetworkTip)];
    [self.netTipLab addGestureRecognizer:tap];

    [self.view addSubview:self.netTipLab];

    self.stack = [[UIStackView alloc] init];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 12;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.stack];

    self.restoreBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.restoreBtn setTitle:L(@"common.restore_purchase") forState:UIControlStateNormal];
    [self.restoreBtn addTarget:self action:@selector(tapRestore) forControlEvents:UIControlEventTouchUpInside];
    self.restoreBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.restoreBtn];
    
    self.stackTopCst = [self.stack.topAnchor constraintEqualToAnchor:self.netTipLab.bottomAnchor constant:14];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:40],
        [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.loadingLab.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12],
        [self.loadingLab.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // netTipLab 位置：在 loadingLab 下方
        [self.netTipLab.topAnchor constraintEqualToAnchor:self.loadingLab.bottomAnchor constant:8],
        [self.netTipLab.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.netTipLab.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.netTipLab.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],

        // stack 跟在 netTipLab 下方（用可变约束）
        [self.stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        self.stackTopCst,
        
        [self.restoreBtn.topAnchor constraintEqualToAnchor:self.stack.bottomAnchor constant:30],
        [self.restoreBtn.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    ]];
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

#pragma mark - Actions

- (void)tapBack {
    if (!self.allowDismiss) return;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)tapProduct:(UIButton *)sender {
    StoreSnapshot *snap = [StoreKit2Manager shared].snapshot;
    if (!snap.networkAvailable) return;
    if (snap.productsState != ProductsLoadStateReady) return;

    NSArray<SK2ProductModel *> *products = snap.products;
    if (sender.tag < 0 || sender.tag >= products.count) return;

    SK2ProductModel *model = products[sender.tag];
    sender.enabled = NO;

    [[StoreKit2Manager shared] purchaseWithProductID:model.productID completion:^(PurchaseFlowState st) {
        dispatch_async(dispatch_get_main_queue(), ^{
               [self render];

               switch (st) {
                   case PurchaseFlowStatePending:
                       [self showToast:L(@"paywall.purchase_pending")];
                       break;

                   case PurchaseFlowStateCancelled:
                       [self showToast:L(@"paywall.purchase_cancelled")];
                       break;

                   case PurchaseFlowStateSucceeded:
                       // 注意：你有 subscriptionState==Active 自动 dismiss，
                       // 这里弹窗可能一闪而过。建议用 toast 或者不提示。
                       [self showToast:L(@"paywall.purchase_success")];
                       break;

                   case PurchaseFlowStateFailed: {
                       NSString *msg = [StoreKit2Manager shared].snapshot.lastErrorMessage;
                       [self showToast:(msg.length ? msg : L(@"paywall.purchase_failed"))];
                       break;
                   }

                   default:
                       break;
               }
           });
    }];
}

- (void)tapRestore {
    StoreSnapshot *snap = [StoreKit2Manager shared].snapshot;
    if (!snap.networkAvailable) return;

    self.restoreBtn.enabled = NO;

    [[StoreKit2Manager shared] restoreWithCompletion:^(PurchaseFlowState st) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self render];
            
            switch (st) {
                        case PurchaseFlowStateRestored:
                            [self showToast:L(@"paywall.restore_success")];
                            break;
                        case PurchaseFlowStateFailed: {
                            NSString *msg = [StoreKit2Manager shared].snapshot.lastErrorMessage;
                            [self showToast:(msg.length ? msg : L(@"paywall.restore_failed"))];
                            break;
                        }
                        default:
                            break;
                    }

        });
    }];
}

- (void)showToast:(NSString *)msg {
    if (msg.length == 0) return;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:ac animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [ac dismissViewControllerAnimated:YES completion:nil];
    });
}


@end
