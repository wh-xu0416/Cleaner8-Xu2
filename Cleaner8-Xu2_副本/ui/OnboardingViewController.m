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
    // 将 "isFirstLaunch" 设置为 NO，表示引导页已经看过
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"isFirstLaunch"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // 跳转到 MainTabBarController
    MainTabBarController *mainTabBarController = [[MainTabBarController alloc] init];
    UIWindow *window = [UIApplication sharedApplication].delegate.window;
    window.rootViewController = mainTabBarController;
    [window makeKeyAndVisible];
}

@end
