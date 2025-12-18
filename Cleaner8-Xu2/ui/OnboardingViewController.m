#import "OnboardingViewController.h"
#import "MainTabBarController.h"

@interface OnboardingViewController ()

@property (nonatomic, strong) UIButton *startButton;

@end

@implementation OnboardingViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // 设置引导页的 UI
    self.view.backgroundColor = [UIColor whiteColor];
    
    // 创建一个按钮，点击按钮跳转到 MainTabBarController
    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.startButton.frame = CGRectMake(100, 300, 200, 50);
    [self.startButton setTitle:@"开始体验" forState:UIControlStateNormal];
    [self.startButton addTarget:self action:@selector(startExperience) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startButton];
}

- (void)startExperience {

    [[NSUserDefaults standardUserDefaults]
        setBool:YES
        forKey:@"hasCompletedOnboarding"];

    MainTabBarController *main = [MainTabBarController new];

    UINavigationController *rootNav =
        (UINavigationController *)self.view.window.rootViewController;

    // 安全判断（防止以后改结构崩）
    if (![rootNav isKindOfClass:[UINavigationController class]]) {
        return;
    }

    // 用 Main 替换整个栈，引导页彻底出局
    [rootNav setViewControllers:@[main] animated:YES];
}


@end
