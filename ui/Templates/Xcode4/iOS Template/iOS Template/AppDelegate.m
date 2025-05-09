//
//  AppDelegate.m
//
//  Copyright 2012 Gideros Mobile. All rights reserved.
//

#import "AppDelegate.h"
#import "ViewController.h"

#import <AVFoundation/AVFoundation.h>

#include "giderosapi.h"

//GIDEROS-TAG-IOS:APP-DELEGATE-DECL//

#ifndef NSFoundationVersionNumber_iOS_7_1
# define NSFoundationVersionNumber_iOS_7_1 1047.25
#endif

@implementation AppDelegate

@synthesize window;
@synthesize viewController;

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions  API_AVAILABLE(ios(13.0)){
    if (@available(iOS 13,*)) {
        //[self.window setWindowScene:(UIWindowScene *) scene];
        AppDelegate *mainDelegate=(AppDelegate *) [UIApplication sharedApplication].delegate;
        viewController=mainDelegate.viewController;
        
        UIWindowScene *ws=((UIWindowScene *)scene);
        self.window = [[UIWindow alloc] initWithWindowScene:ws];
        [self.window setRootViewController:self.viewController];
        [self.window makeKeyAndVisible];
    }
}

- (void) sceneDidDisconnect:(UIScene *) scene
API_AVAILABLE(ios(13.0)){
}

- (void) sceneDidBecomeActive:(UIScene *) scene
API_AVAILABLE(ios(13.0)){
    [self applicationDidBecomeActive:[UIApplication sharedApplication]];
}

- (void) sceneWillResignActive:(UIScene *) scene
API_AVAILABLE(ios(13.0)){
    [self applicationWillResignActive:[UIApplication sharedApplication]];
}

- (void) sceneWillEnterForeground:(UIScene *) scene
API_AVAILABLE(ios(13.0)){
    [self applicationWillEnterForeground:[UIApplication sharedApplication]];
}

- (void) sceneDidEnterBackground:(UIScene *) scene
API_AVAILABLE(ios(13.0)){
    [self applicationDidEnterBackground:[UIApplication sharedApplication]];
}

- (BOOL)isNotRotatedBySystem{
    BOOL OSIsBelowIOS8 = [[[UIDevice currentDevice] systemVersion] floatValue] < 8.0;
    BOOL SDKIsBelowIOS8 = floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_7_1;
    return OSIsBelowIOS8 || SDKIsBelowIOS8;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	CGRect bounds = [[UIScreen mainScreen] bounds];
	
    self.viewController = [[ViewController alloc] init];

	[self.viewController view];

    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:nil];

    int width = bounds.size.width;
    int height = bounds.size.height;
    
    if(![self isNotRotatedBySystem] && UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation)){
        height = bounds.size.width;
        width = bounds.size.height;
    }
    
    NSString *path = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"assets"] stringByAppendingPathComponent:@"properties.bin"];
    
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    
    BOOL isPlayer = false;
    BOOL exists = [fileManager fileExistsAtPath:path];
    if (!exists) {
        isPlayer = true;
        
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString* dir = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"gideros"];
        
        NSArray *files = [fileManager contentsOfDirectoryAtPath:dir error:nil];
        if (files != nil) {
            for (NSString *file in files) {
                [self.viewController addProject:file];
            }
        }
        [self.viewController initTable];
    }
    
    gdr_initialize(self.viewController.glView, width, height, isPlayer);

    if (@available(iOS 13,*)) {
        self.window = [[UIWindow alloc] initWithFrame:bounds];
    }
    else {
	    if ([[[UIDevice currentDevice] systemVersion] compare:@"6.0" options:NSNumericSearch] != NSOrderedAscending)
    	{
        	[self.window setRootViewController:self.viewController];
	    }
	    else
    	{
        	[self.window addSubview:self.viewController.view];
	    }

    	[self.window makeKeyAndVisible];
    }

    gdr_drawFirstFrame();

    //GIDEROS-TAG-IOS:APP-LAUNCHED//

    return YES;
}

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_2
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    gdr_handleOpenUrl(url);
    return YES;
}
#else
- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url
{
    gdr_handleOpenUrl(url);
    return YES;
}
#endif

- (void)applicationWillResignActive:(UIApplication *)application
{
	gdr_suspend();
    [self.viewController stopAnimation];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
	gdr_resume();
    [self.viewController startAnimation];
}

- (void)applicationWillTerminate:(UIApplication *)application
{
	gdr_exitGameLoop();
    [self.viewController stopAnimation];
	gdr_deinitialize();
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    gdr_background();
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    gdr_foreground();
}

#ifdef GIDEROS_TAG_APNS
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    //GIDEROS-TAG-IOS:NOTIFICATION-RX//
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    UIBackgroundFetchResult result=UIBackgroundFetchResultNewData;
    //GIDEROS-TAG-IOS:NOTIFICATION-RX-CH//
    completionHandler(result);
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(nonnull NSData *)deviceToken {
    //GIDEROS-TAG-IOS:NOTIFICATION-TOKEN//
}
#endif

- (void)dealloc
{
}

@end
