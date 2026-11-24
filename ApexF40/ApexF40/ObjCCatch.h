#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Runs a block and returns the Objective-C exception it raised, if any.
NSException * _Nullable ApexTryCatch(void (NS_NOESCAPE ^block)(void));
NS_ASSUME_NONNULL_END
