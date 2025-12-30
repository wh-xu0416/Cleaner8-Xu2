#import "OnboardingViewController.h"
#import "VideoViewController.h"
#import "MainTabBarController.h"

@interface OnboardingViewController ()

@property (nonatomic, strong) UIButton *startButton;

@end

@implementation OnboardingViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor whiteColor];
    
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

    if (![rootNav isKindOfClass:[UINavigationController class]]) {
        return;
    }

    [rootNav setViewControllers:@[main] animated:YES];
}


@end
