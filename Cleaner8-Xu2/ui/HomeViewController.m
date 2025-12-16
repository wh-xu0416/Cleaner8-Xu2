//
//  HomeViewController.m
//  Cleaner8-Xu2
//
//  Created by 徐文豪 on 2025/12/15.
//
#import "HomeViewController.h"

#import "ASScannerManager.h"
#import "ASSelectionManager.h"

@property(nonatomic,strong) ASScannerManager *scanner;
@property(nonatomic,strong) ASSelectionManager *selection;
@implementation HomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.whiteColor;
    self.title = @"首页";
}


@end
