#import <Foundation/Foundation.h>
#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

/// One animation take from an FBX file, ready to play.
@interface FBXClip : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) double duration;
@property (nonatomic, copy) NSArray<SCNAnimationPlayer *> *players;
@end

@interface FBXResult : NSObject
@property (nonatomic, strong) SCNScene *scene;
@property (nonatomic, copy) NSArray<FBXClip *> *clips;
@property (nonatomic, copy) NSArray<NSString *> *missingTextures;
@end

/// Reads .fbx files (binary and ASCII, 2011+) with ufbx and builds a SceneKit scene:
/// node hierarchy, meshes, skinning, blend shapes, PBR/Phong materials and baked animation takes.
@interface FBXImporter : NSObject
+ (nullable FBXResult *)loadURL:(NSURL *)url error:(NSString * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
