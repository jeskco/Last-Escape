#import "ObjCCatch.h"
NSException * _Nullable ApexTryCatch(void (NS_NOESCAPE ^block)(void)) {
    @try { block(); return nil; }
    @catch (NSException *e) { return e; }
}
