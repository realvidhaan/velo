#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` inside an Objective-C `@try/@catch`.
///
/// Some Cocoa APIs (notably `-[AVAudioNode installTapOnBus:...]`) report failure
/// by **raising an Objective-C `NSException`**, not by returning an error. A Swift
/// `do/catch` cannot catch those — the runtime calls `abort()` and the whole
/// process dies. This shim converts such an exception into an `NSError` that Swift
/// can handle, so callers degrade gracefully instead of crashing.
///
/// - Returns: `nil` if `block` completed normally, otherwise an `NSError` whose
///   `localizedDescription` is the exception's `reason`.
NSError *_Nullable VeloRunCatchingNSException(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
