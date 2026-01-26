//
//  Cleaner8_Xu2UITestsLaunchTests.m
//  Cleaner8-Xu2UITests
//
//  Created by 徐文豪 on 2025/12/15.
//

#import <XCTest/XCTest.h>

@interface Cleaner8_Xu2UITestsLaunchTests : XCTestCase

@end

@implementation Cleaner8_Xu2UITestsLaunchTests

+ (BOOL)runsForEachTargetApplicationUIConfiguration {
    return YES;
}

- (void)setUp {
    self.continueAfterFailure = NO;
}

- (void)testLaunch {
    XCUIApplication *app = [[XCUIApplication alloc] init];
    [app launch];

    // Insert steps here to perform after app launch but before taking a screenshot,
    // such as logging into a test account or navigating somewhere in the app

    XCTAttachment *attachment = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    attachment.name = @"Launch Screen";
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
}

@end
