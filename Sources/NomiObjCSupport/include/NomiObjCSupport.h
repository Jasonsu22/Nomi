#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and stops an Objective-C exception at this boundary.
///
/// Some AVFoundation calls report bad input by raising NSException. Swift cannot
/// catch it, and letting it unwind through Swift frames corrupts the running task.
/// Returns NO and sets `reason` when the block raised.
BOOL NomiCatchException(NS_NOESCAPE void (^block)(void), NSString *_Nullable *_Nullable reason);

NS_ASSUME_NONNULL_END
