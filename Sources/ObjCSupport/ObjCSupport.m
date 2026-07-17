#import "ObjCSupport.h"

NSError *_Nullable VeloRunCatchingNSException(NS_NOESCAPE void (^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return [NSError errorWithDomain:@"com.flowclone.app.ObjCException"
                                   code:1
                               userInfo:@{
            NSLocalizedDescriptionKey: exception.reason ?: @"Unknown Objective-C exception",
            @"ExceptionName": exception.name ?: @"NSException"
        }];
    }
}
