#import <AppKit/AppKit.h>
#import "SlopKitLaunch.h"

// `SLOP_APPEARANCE=light|dark` forces that appearance for the whole app, so screenshots can
// cover both modes without touching the system setting:
//
//     scripts/drive launch build/<Name>.app --env SLOP_APPEARANCE=dark
//
// This runs as an image constructor, so it works in every app that links SlopKit, whatever
// its app delegate is (many apps wrap or skip `SlopAppDelegate`). It only registers for
// "will finish launching", before any window exists, and does nothing when the variable is
// unset.

NSString *_Nullable SlopKitTestAppearanceName(void) {
    NSString *value = NSProcessInfo.processInfo.environment[@"SLOP_APPEARANCE"];
    if ([value isEqualToString:@"light"]) return NSAppearanceNameAqua;
    if ([value isEqualToString:@"dark"]) return NSAppearanceNameDarkAqua;
    return nil;
}

__attribute__((constructor))
static void SlopKitInstallTestAppearance(void) {
    NSString *name = SlopKitTestAppearanceName();
    if (name == nil) return;
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillFinishLaunchingNotification
                                                    object:nil
                                                     queue:nil
                                                usingBlock:^(NSNotification *note) {
        NSApp.appearance = [NSAppearance appearanceNamed:name];
    }];
}
