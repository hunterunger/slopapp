// Launch-time hooks every app that links SlopKit gets without calling anything.
// See SlopKitLaunch.m. Nothing here is meant to be called from app code.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The appearance name SLOP_APPEARANCE asked for ("light" → aqua, "dark" → darkAqua), or nil.
FOUNDATION_EXPORT NSString *_Nullable SlopKitTestAppearanceName(void);

NS_ASSUME_NONNULL_END
