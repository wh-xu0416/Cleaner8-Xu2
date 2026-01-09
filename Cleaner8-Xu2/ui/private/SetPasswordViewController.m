#import "SetPasswordViewController.h"
#import "UIViewController+ASPrivateBackground.h"
#import "ASColors.h"
#import "ASPasscodeManager.h"
#import "ASCustomNavBar.h"
#import "Common.h"
#import "UIViewController+ASRootNav.h"

#pragma mark - Adapt Helpers

static inline CGFloat ASDesignWidth(void) { return 402.0; }
static inline CGFloat ASScale(void) {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    return MIN(1.0, w / ASDesignWidth());
}
static inline CGFloat AS(CGFloat v) { return round(v * ASScale()); }
static inline UIFont *ASFontS(CGFloat s, UIFontWeight w) { return [UIFont systemFontOfSize:round(s * ASScale()) weight:w]; }
static inline UIEdgeInsets ASEdgeInsets(CGFloat t, CGFloat l, CGFloat b, CGFloat r) { return UIEdgeInsetsMake(AS(t), AS(l), AS(b), AS(r)); }

@interface SetPasswordViewController () <UITextFieldDelegate>
@property (nonatomic, strong) ASCustomNavBar *nav;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UITextField *hiddenTF;

@property (nonatomic, strong) NSArray<UIView *> *boxes;
@property (nonatomic, strong) NSArray<UILabel *> *stars;

@property (nonatomic, copy) NSString *firstCode;   // Set flow: first input
@property (nonatomic, strong) NSMutableString *input;
@property (nonatomic, strong) UILabel *errorLabel;

@end

@implementation SetPasswordViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self as_applyPrivateBackground];

    self.input = [NSMutableString string];
    [self buildUI];
    [self updatePrompt];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self as_updatePrivateBackgroundLayout];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.hiddenTF becomeFirstResponder];
}

- (void)buildUI {
    __weak typeof(self) ws = self;

    self.nav = [[ASCustomNavBar alloc] initWithTitle:NSLocalizedString(@"Password", nil)];
    self.nav.translatesAutoresizingMaskIntoConstraints = NO;
    self.nav.onBack = ^{
        [ws.navigationController popViewControllerAnimated:YES];
    };
    self.nav.showRightButton = NO;
    [self.view addSubview:self.nav];

    // 原来 88，这里做缩放。注意：如果你的 ASCustomNavBar 内部已考虑 safeTop，
    // 这里保持你原样的“总高”，只是缩放即可。
    [NSLayoutConstraint activateConstraints:@[
        [self.nav.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.nav.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.nav.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.nav.heightAnchor constraintEqualToConstant:AS(88)],
    ]];

    self.titleLabel = [UILabel new];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.textColor = UIColor.blackColor;
    self.titleLabel.font = ASFontS(28, UIFontWeightSemibold);
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.titleLabel];

    self.errorLabel = [UILabel new];
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.font = ASFontS(14, UIFontWeightRegular);
    self.errorLabel.textColor = [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0];
    self.errorLabel.text = @"";
    self.errorLabel.hidden = YES;
    [self.view addSubview:self.errorLabel];

    // hidden textfield
    self.hiddenTF = [UITextField new];
    self.hiddenTF.translatesAutoresizingMaskIntoConstraints = NO;
    self.hiddenTF.keyboardType = UIKeyboardTypeNumberPad;
    self.hiddenTF.textColor = UIColor.clearColor;
    self.hiddenTF.tintColor = UIColor.clearColor;
    self.hiddenTF.delegate = self;
    [self.hiddenTF addTarget:self action:@selector(tfChanged) forControlEvents:UIControlEventEditingChanged];
    [self.view addSubview:self.hiddenTF];

    NSMutableArray *boxes = [NSMutableArray array];
    NSMutableArray *stars = [NSMutableArray array];

    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:row];

    CGFloat boxSize = AS(80.0);
    CGFloat gap = AS(10.0);

    UIView *prev = nil;
    for (int i = 0; i < 4; i++) {
        UIView *b = [UIView new];
        b.translatesAutoresizingMaskIntoConstraints = NO;
        b.backgroundColor = ASColorRGBA(0xD8,0xD8,0xD8,1);
        b.layer.cornerRadius = AS(16);
        b.layer.masksToBounds = YES;

        UILabel *star = [UILabel new];
        star.translatesAutoresizingMaskIntoConstraints = NO;
        star.textAlignment = NSTextAlignmentCenter;
        star.font = ASFontS(36, UIFontWeightSemibold);
        star.textColor = UIColor.blackColor;
        star.text = @"";
        [b addSubview:star];

        [row addSubview:b];
        [NSLayoutConstraint activateConstraints:@[
            [b.widthAnchor constraintEqualToConstant:boxSize],
            [b.heightAnchor constraintEqualToConstant:boxSize],
            [b.topAnchor constraintEqualToAnchor:row.topAnchor],
            [b.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],

            [star.centerXAnchor constraintEqualToAnchor:b.centerXAnchor],
            [star.centerYAnchor constraintEqualToAnchor:b.centerYAnchor],
        ]];

        if (!prev) {
            [b.leadingAnchor constraintEqualToAnchor:row.leadingAnchor].active = YES;
        } else {
            [b.leadingAnchor constraintEqualToAnchor:prev.trailingAnchor constant:gap].active = YES;
        }
        prev = b;

        [boxes addObject:b];
        [stars addObject:star];
    }
    [prev.trailingAnchor constraintEqualToAnchor:row.trailingAnchor].active = YES;

    [NSLayoutConstraint activateConstraints:@[
        // 原来 110 / 10 / 20 / 16 都缩放
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.nav.bottomAnchor constant:AS(110)],
        [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.errorLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:AS(10)],
        [self.errorLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:AS(20)],
        [self.errorLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-AS(20)],

        [row.topAnchor constraintEqualToAnchor:self.errorLabel.bottomAnchor constant:AS(16)],
        [row.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.hiddenTF.centerXAnchor constraintEqualToAnchor:row.centerXAnchor],
        [self.hiddenTF.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [self.hiddenTF.widthAnchor constraintEqualToConstant:AS(1)],
        [self.hiddenTF.heightAnchor constraintEqualToConstant:AS(1)],
    ]];

    self.boxes = boxes;
    self.stars = stars;

    [self updateFocusBorder];
}

- (void)updatePrompt {

    if (self.flow == ASPasswordFlowDisable) {
        self.titleLabel.text = (self.firstCode.length
                                ? NSLocalizedString(@"Confirm Password", nil)
                                : NSLocalizedString(@"Set New Passcode", nil));
        return;
    }

    if (self.flow == ASPasswordFlowSet) {
        self.titleLabel.text = (self.firstCode.length
                                ? NSLocalizedString(@"Confirm Password", nil)
                                : NSLocalizedString(@"Enter Password", nil));
    } else {
        self.titleLabel.text = NSLocalizedString(@"Enter Password", nil);
    }
}

- (void)showWrongPin {
    self.errorLabel.text = NSLocalizedString(@"Wrong PIN. Please retry.", nil);
    self.errorLabel.hidden = NO;
}

- (void)clearError {
    self.errorLabel.text = @"";
    self.errorLabel.hidden = YES;
}

- (void)tfChanged {
    NSString *t = self.hiddenTF.text ?: @"";

    if (t.length > 0 && !self.errorLabel.hidden) {
        [self clearError];
    }

    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    t = [[t componentsSeparatedByCharactersInSet:nonDigits] componentsJoinedByString:@""];
    if (t.length > 4) t = [t substringToIndex:4];

    [self.input setString:t];
    [self renderStars];
    [self updateFocusBorder];

    if (t.length == 4) {
        [self handleFullCode:t];
    }
}

- (void)renderStars {
    for (int i = 0; i < 4; i++) {
        UILabel *s = self.stars[i];
        s.text = (i < self.input.length) ? @"•" : @"";
    }
}

- (void)updateFocusBorder {
    NSInteger idx = MIN(self.input.length, 3);
    for (int i = 0; i < 4; i++) {
        UIView *b = self.boxes[i];
        if (self.input.length < 4 && i == idx) {
            b.layer.borderWidth = AS(2);
            b.layer.borderColor = ASBlue().CGColor;
        } else {
            b.layer.borderWidth = 0;
            b.layer.borderColor = UIColor.clearColor.CGColor;
        }
    }
}

- (void)resetInputAnimated:(BOOL)animated {
    self.hiddenTF.text = @"";
    [self.input setString:@""];
    [self renderStars];
    [self updateFocusBorder];

    if (animated) {
        UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [h impactOccurred];
    }
}

- (void)handleFullCode:(NSString *)code {
    if (self.flow == ASPasswordFlowDisable) {
        if (!self.firstCode.length) {
            [self clearError];
            self.firstCode = code;
            [self resetInputAnimated:NO];
            [self updatePrompt];
            return;
        } else {
            if ([self.firstCode isEqualToString:code]) {
                [self clearError];
                [ASPasscodeManager enableWithCode:code];
                if (self.onSuccess) self.onSuccess();

                UINavigationController *nav = [self as_rootNav];
                if (![nav isKindOfClass:UINavigationController.class]) return;
                [nav popViewControllerAnimated:YES];
                return;
            } else {
                self.firstCode = nil;
                [self resetInputAnimated:YES];
                [self updatePrompt];
                return;
            }
        }
    }

    if (self.flow == ASPasswordFlowSet) {
        if (!self.firstCode.length) {
            [self clearError];
            self.firstCode = code;
            [self resetInputAnimated:NO];
            [self updatePrompt];
            return;
        } else {
            if ([self.firstCode isEqualToString:code]) {
                [self clearError];
                [ASPasscodeManager enableWithCode:code];
                if (self.onSuccess) self.onSuccess();
                UINavigationController *nav = [self as_rootNav];
                if (![nav isKindOfClass:UINavigationController.class]) return;
                [nav popToRootViewControllerAnimated:YES];
                return;
            } else {
                self.firstCode = nil;
                [self resetInputAnimated:YES];
                [self updatePrompt];
                return;
            }
        }
    }

    if ([ASPasscodeManager verify:code]) {
        [self clearError];
        if (self.onSuccess) self.onSuccess();
        UINavigationController *nav = [self as_rootNav];
        if (![nav isKindOfClass:UINavigationController.class]) return;
        [nav popViewControllerAnimated:YES];
    } else {
        [self showWrongPin];
        [self resetInputAnimated:YES];
    }
}

@end
