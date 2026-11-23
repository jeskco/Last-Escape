#import "FBXImporter.h"
#import <UIKit/UIKit.h>
#include "ThirdParty/ufbx/ufbx.h"

@implementation FBXClip @end
@implementation FBXResult @end

static NSString *Str(ufbx_string s) {
    if (!s.data || s.length == 0) return @"";
    return [[NSString alloc] initWithBytes:s.data length:s.length encoding:NSUTF8StringEncoding] ?: @"";
}

static SCNMatrix4 Mat(ufbx_matrix m) {
    SCNMatrix4 r;
    r.m11 = m.m00; r.m12 = m.m10; r.m13 = m.m20; r.m14 = 0;
    r.m21 = m.m01; r.m22 = m.m11; r.m23 = m.m21; r.m24 = 0;
    r.m31 = m.m02; r.m32 = m.m12; r.m33 = m.m22; r.m34 = 0;
    r.m41 = m.m03; r.m42 = m.m13; r.m43 = m.m23; r.m44 = 1;
    return r;
}

static UIColor *Color3(ufbx_vec3 c, double a) {
    return [UIColor colorWithRed:MIN(MAX(c.x, 0), 1) green:MIN(MAX(c.y, 0), 1) blue:MIN(MAX(c.z, 0), 1) alpha:a];
}

@interface FBXBuilder : NSObject
@property (nonatomic, strong) NSURL *dir;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *imageCache;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SCNMaterial *> *materialCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *missing;
@property (nonatomic, strong) NSArray<NSURL *> *dirFiles;
@end

@implementation FBXBuilder

- (instancetype)initWithDir:(NSURL *)dir {
    if ((self = [super init])) {
        _dir = dir; _imageCache = [NSMutableDictionary new]; _materialCache = [NSMutableDictionary new]; _missing = [NSMutableSet new];
        NSMutableArray *files = [NSMutableArray new];
        NSDirectoryEnumerator *e = [[NSFileManager defaultManager] enumeratorAtURL:dir includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
        for (NSURL *u in e) { [files addObject:u]; if (files.count > 4000) break; }
        _dirFiles = files;
    }
    return self;
}

/// Finds a texture: embedded data first, then the paths stored in the file, then any file with the same name next to the FBX.
- (nullable UIImage *)imageForTexture:(ufbx_texture *)tex {
    if (!tex) return nil;
    if (tex->file_textures.count > 0 && tex->file_textures.data[0] != tex) tex = tex->file_textures.data[0];
    NSString *key = [NSString stringWithFormat:@"%u", tex->element_id];
    id cached = self.imageCache[key];
    if (cached) return cached == [NSNull null] ? nil : cached;
    UIImage *img = nil;
    if (tex->content.size > 0) img = [UIImage imageWithData:[NSData dataWithBytes:tex->content.data length:tex->content.size]];
    if (!img && tex->video && tex->video->content.size > 0) img = [UIImage imageWithData:[NSData dataWithBytes:tex->video->content.data length:tex->video->content.size]];
    NSString *name = Str(tex->filename);
    if (name.length == 0) name = Str(tex->relative_filename);
    NSString *base = [[name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] lastPathComponent];
    if (!img) {
        NSMutableArray<NSString *> *candidates = [NSMutableArray new];
        NSString *abs = Str(tex->absolute_filename), *rel = [Str(tex->relative_filename) stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        if (abs.length) [candidates addObject:abs];
        if (rel.length) [candidates addObject:[self.dir URLByAppendingPathComponent:rel].path];
        if (base.length) {
            [candidates addObject:[self.dir URLByAppendingPathComponent:base].path];
            for (NSString *sub in @[@"textures", @"Textures", @"texture", @"tex", @"images"]) [candidates addObject:[[self.dir URLByAppendingPathComponent:sub] URLByAppendingPathComponent:base].path];
        }
        for (NSString *p in candidates) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) { img = [UIImage imageWithContentsOfFile:p]; if (img) break; }
        }
        if (!img && base.length) {
            NSString *lower = base.lowercaseString, *stem = base.stringByDeletingPathExtension.lowercaseString;
            for (NSURL *u in self.dirFiles) if ([u.lastPathComponent.lowercaseString isEqualToString:lower]) { img = [UIImage imageWithContentsOfFile:u.path]; if (img) break; }
            // Same name, different extension (e.g. .tga in the file, .png shipped)
            if (!img) for (NSURL *u in self.dirFiles) if ([u.lastPathComponent.stringByDeletingPathExtension.lowercaseString isEqualToString:stem]) { img = [UIImage imageWithContentsOfFile:u.path]; if (img) break; }
        }
    }
    if (!img && base.length) [self.missing addObject:base];
    self.imageCache[key] = img ?: (id)[NSNull null];
    return img;
}

- (SCNMaterial *)material:(ufbx_material *)mat {
    if (!mat) {
        SCNMaterial *m = [SCNMaterial material]; m.lightingModelName = SCNLightingModelPhysicallyBased;
        m.diffuse.contents = [UIColor colorWithWhite:0.8 alpha:1]; m.roughness.contents = @0.6; m.doubleSided = YES; return m;
    }
    NSNumber *key = @(mat->element_id);
    if (self.materialCache[key]) return self.materialCache[key];
    SCNMaterial *m = [SCNMaterial material];
    m.name = Str(mat->name);
    m.lightingModelName = SCNLightingModelPhysicallyBased;
    m.doubleSided = YES;

    ufbx_material_map bc = mat->pbr.base_color;
    UIImage *diffuse = [self imageForTexture:bc.texture ?: mat->fbx.diffuse_color.texture];
    double factor = mat->pbr.base_factor.has_value ? mat->pbr.base_factor.value_real : 1.0;
    if (diffuse) {
        m.diffuse.contents = diffuse;
    } else {
        ufbx_vec3 c = bc.has_value ? bc.value_vec3 : mat->fbx.diffuse_color.value_vec3;
        if (factor > 0 && factor < 1) { c.x *= factor; c.y *= factor; c.z *= factor; }
        m.diffuse.contents = Color3(c, 1);
    }
    UIImage *normal = [self imageForTexture:mat->pbr.normal_map.texture ?: (mat->fbx.normal_map.texture ?: mat->fbx.bump.texture)];
    if (normal) m.normal.contents = normal;

    UIImage *rough = [self imageForTexture:mat->pbr.roughness.texture];
    double r = mat->pbr.roughness.has_value ? mat->pbr.roughness.value_real : 0.6;
    if (mat->features.roughness_as_glossiness.enabled) r = 1 - r;
    m.roughness.contents = rough ?: @(MIN(MAX(r, 0.04), 1));
    UIImage *metal = [self imageForTexture:mat->pbr.metalness.texture];
    double mv = mat->pbr.metalness.has_value ? mat->pbr.metalness.value_real : 0;
    m.metalness.contents = metal ?: @(MIN(MAX(mv, 0), 1));

    UIImage *emissive = [self imageForTexture:mat->pbr.emission_color.texture ?: mat->fbx.emission_color.texture];
    if (emissive) m.emission.contents = emissive;
    else {
        ufbx_vec3 e = mat->pbr.emission_color.value_vec3;
        double ef = mat->pbr.emission_factor.has_value ? mat->pbr.emission_factor.value_real : 1;
        if ((e.x + e.y + e.z) * ef > 0.01) m.emission.contents = Color3((ufbx_vec3){ .x = e.x * ef, .y = e.y * ef, .z = e.z * ef }, 1);
    }
    UIImage *ao = [self imageForTexture:mat->pbr.ambient_occlusion.texture];
    if (ao) m.ambientOcclusion.contents = ao;

    double opacity = mat->pbr.opacity.has_value ? mat->pbr.opacity.value_real : 1;
    if (opacity > 0.001 && opacity < 0.999) { m.transparency = opacity; m.blendMode = SCNBlendModeAlpha; }
    if (mat->features.unlit.enabled) m.lightingModelName = SCNLightingModelConstant;
    self.materialCache[key] = m;
    return m;
}

static SCNGeometrySource *FloatSource(NSData *d, SCNGeometrySourceSemantic sem, NSInteger count, NSInteger comps) {
    return [SCNGeometrySource geometrySourceWithData:d semantic:sem vectorCount:count floatComponents:YES componentsPerVector:comps bytesPerComponent:sizeof(float) dataOffset:0 dataStride:sizeof(float) * comps];
}

/// Builds the geometry (and skinner / morpher) for a mesh attached to `node`.
- (void)attachMesh:(ufbx_mesh *)mesh fbxNode:(ufbx_node *)fnode toNode:(SCNNode *)node nodes:(NSArray<SCNNode *> *)nodes {
    if (mesh->num_triangles == 0) return;
    size_t triCap = mesh->max_face_triangles * 3;
    uint32_t *tri = malloc(sizeof(uint32_t) * MAX(triCap, 3));

    // Parts per material
    size_t partCount = mesh->material_parts.count;
    NSMutableData *pos = [NSMutableData new], *nrm = [NSMutableData new], *uv = [NSMutableData new], *col = [NSMutableData new];
    NSMutableData *vids = [NSMutableData new];   // FBX vertex id for each output vertex (for skin + blend shapes)
    NSMutableArray<SCNGeometryElement *> *elements = [NSMutableArray new];
    NSMutableArray<SCNMaterial *> *materials = [NSMutableArray new];
    BOOL hasNormal = mesh->vertex_normal.exists, hasUV = mesh->vertex_uv.exists, hasColor = mesh->vertex_color.exists;
    uint32_t out = 0;

    for (size_t pi = 0; pi < MAX(partCount, (size_t)1); pi++) {
        size_t nFaces = partCount ? mesh->material_parts.data[pi].num_faces : mesh->num_faces;
        NSMutableData *idx = [NSMutableData new];
        for (size_t f = 0; f < nFaces; f++) {
            uint32_t fi = partCount ? mesh->material_parts.data[pi].face_indices.data[f] : (uint32_t)f;
            ufbx_face face = mesh->faces.data[fi];
            if (face.num_indices < 3) continue;
            uint32_t nt = ufbx_triangulate_face(tri, triCap, mesh, face);
            for (uint32_t k = 0; k < nt * 3; k++) {
                uint32_t ix = tri[k];
                ufbx_vec3 p = ufbx_get_vertex_vec3(&mesh->vertex_position, ix);
                float pf[3] = { (float)p.x, (float)p.y, (float)p.z }; [pos appendBytes:pf length:sizeof pf];
                if (hasNormal) { ufbx_vec3 n = ufbx_get_vertex_vec3(&mesh->vertex_normal, ix); float nf[3] = { (float)n.x, (float)n.y, (float)n.z }; [nrm appendBytes:nf length:sizeof nf]; }
                if (hasUV) { ufbx_vec2 t = ufbx_get_vertex_vec2(&mesh->vertex_uv, ix); float tf[2] = { (float)t.x, (float)(1.0 - t.y) }; [uv appendBytes:tf length:sizeof tf]; }
                if (hasColor) { ufbx_vec4 c = ufbx_get_vertex_vec4(&mesh->vertex_color, ix); float cf[4] = { (float)c.x, (float)c.y, (float)c.z, (float)c.w }; [col appendBytes:cf length:sizeof cf]; }
                uint32_t vid = mesh->vertex_indices.data[ix]; [vids appendBytes:&vid length:4];
                [idx appendBytes:&out length:4]; out++;
            }
        }
        if (idx.length == 0) continue;
        [elements addObject:[SCNGeometryElement geometryElementWithData:idx primitiveType:SCNGeometryPrimitiveTypeTriangles primitiveCount:idx.length / 12 bytesPerIndex:4]];
        uint32_t slot = partCount ? mesh->material_parts.data[pi].index : 0;
        ufbx_material *mat = NULL;
        if (slot < fnode->materials.count) mat = fnode->materials.data[slot];
        else if (slot < mesh->materials.count) mat = mesh->materials.data[slot];
        [materials addObject:[self material:mat]];
    }
    free(tri);
    if (out == 0) return;

    NSMutableArray<SCNGeometrySource *> *sources = [NSMutableArray arrayWithObject:FloatSource(pos, SCNGeometrySourceSemanticVertex, out, 3)];
    if (hasNormal) [sources addObject:FloatSource(nrm, SCNGeometrySourceSemanticNormal, out, 3)];
    if (hasUV) [sources addObject:FloatSource(uv, SCNGeometrySourceSemanticTexcoord, out, 2)];
    if (hasColor) [sources addObject:FloatSource(col, SCNGeometrySourceSemanticColor, out, 4)];
    SCNGeometry *geo = [SCNGeometry geometryWithSources:sources elements:elements];
    geo.name = Str(mesh->name).length ? Str(mesh->name) : Str(fnode->name);
    geo.materials = materials;
    const uint32_t *vid = vids.bytes;

    // Blend shapes (additive targets so they combine with skinning)
    NSMutableArray<SCNGeometry *> *targets = [NSMutableArray new];
    NSMutableArray<NSNumber *> *weights = [NSMutableArray new];
    for (size_t d = 0; d < mesh->blend_deformers.count; d++) {
        ufbx_blend_deformer *bd = mesh->blend_deformers.data[d];
        for (size_t c = 0; c < bd->channels.count; c++) {
            ufbx_blend_channel *ch = bd->channels.data[c];
            ufbx_blend_shape *shape = ch->target_shape;
            if (!shape && ch->keyframes.count) shape = ch->keyframes.data[ch->keyframes.count - 1].shape;
            if (!shape || shape->num_offsets == 0) continue;
            float *dense = calloc(mesh->num_vertices * 3, sizeof(float));
            for (size_t o = 0; o < shape->num_offsets; o++) {
                uint32_t v = shape->offset_vertices.data[o]; if (v >= mesh->num_vertices) continue;
                ufbx_vec3 off = shape->position_offsets.data[o];
                dense[v * 3] = off.x; dense[v * 3 + 1] = off.y; dense[v * 3 + 2] = off.z;
            }
            NSMutableData *delta = [NSMutableData dataWithLength:out * 3 * sizeof(float)];
            float *dp = delta.mutableBytes;
            for (uint32_t i = 0; i < out; i++) { uint32_t v = vid[i]; if (v < mesh->num_vertices) { dp[i * 3] = dense[v * 3]; dp[i * 3 + 1] = dense[v * 3 + 1]; dp[i * 3 + 2] = dense[v * 3 + 2]; } }
            free(dense);
            SCNGeometry *t = [SCNGeometry geometryWithSources:@[FloatSource(delta, SCNGeometrySourceSemanticVertex, out, 3)] elements:elements];
            NSString *nm = Str(ch->name);
            NSRange bar = [nm rangeOfString:@"." options:NSBackwardsSearch];
            if (bar.location != NSNotFound && bar.location + 1 < nm.length) nm = [nm substringFromIndex:bar.location + 1];
            t.name = nm.length ? nm : Str(shape->name);
            [targets addObject:t]; [weights addObject:@(ch->weight)];
        }
    }
    if (targets.count) {
        SCNMorpher *morpher = [SCNMorpher new];
        morpher.calculationMode = SCNMorpherCalculationModeAdditive;
        morpher.targets = targets;
        for (NSUInteger i = 0; i < weights.count; i++) [morpher setWeight:weights[i].doubleValue forTargetAtIndex:i];
        node.morpher = morpher;
    }

    // Skinning (up to 4 strongest influences per vertex)
    if (mesh->skin_deformers.count > 0) {
        ufbx_skin_deformer *skin = mesh->skin_deformers.data[0];
        size_t nb = skin->clusters.count;
        if (nb > 0 && nb < 65535) {
            NSMutableArray<SCNNode *> *bones = [NSMutableArray new];
            NSMutableArray<NSValue *> *ibm = [NSMutableArray new];
            for (size_t c = 0; c < nb; c++) {
                ufbx_skin_cluster *cl = skin->clusters.data[c];
                SCNNode *b = (cl->bone_node && cl->bone_node->typed_id < nodes.count) ? nodes[cl->bone_node->typed_id] : node;
                [bones addObject:b];
                [ibm addObject:[NSValue valueWithSCNMatrix4:Mat(cl->geometry_to_bone)]];
            }
            NSMutableData *bw = [NSMutableData dataWithLength:out * 4 * sizeof(float)], *bi = [NSMutableData dataWithLength:out * 4 * sizeof(uint16_t)];
            float *w = bw.mutableBytes; uint16_t *ii = bi.mutableBytes;
            for (uint32_t i = 0; i < out; i++) {
                uint32_t v = vid[i];
                if (v >= skin->vertices.count) { w[i * 4] = 1; continue; }
                ufbx_skin_vertex sv = skin->vertices.data[v];
                uint32_t n = MIN(sv.num_weights, 4u); float total = 0;
                for (uint32_t k = 0; k < n; k++) {
                    ufbx_skin_weight sw = skin->weights.data[sv.weight_begin + k];
                    w[i * 4 + k] = (float)sw.weight; ii[i * 4 + k] = (uint16_t)sw.cluster_index; total += (float)sw.weight;
                }
                if (total > 0) for (uint32_t k = 0; k < n; k++) w[i * 4 + k] /= total;
                else w[i * 4] = 1;
            }
            SCNGeometrySource *ws = [SCNGeometrySource geometrySourceWithData:bw semantic:SCNGeometrySourceSemanticBoneWeights vectorCount:out floatComponents:YES componentsPerVector:4 bytesPerComponent:sizeof(float) dataOffset:0 dataStride:sizeof(float) * 4];
            SCNGeometrySource *is = [SCNGeometrySource geometrySourceWithData:bi semantic:SCNGeometrySourceSemanticBoneIndices vectorCount:out floatComponents:NO componentsPerVector:4 bytesPerComponent:sizeof(uint16_t) dataOffset:0 dataStride:sizeof(uint16_t) * 4];
            SCNSkinner *skinner = [SCNSkinner skinnerWithBaseGeometry:geo bones:bones boneInverseBindTransforms:ibm boneWeights:ws boneIndices:is];
            node.skinner = skinner;
        }
    }
    node.geometry = geo;
    node.castsShadow = YES;
}

static NSArray *Keys(double duration, size_t count, double (^timeAt)(size_t)) {
    NSMutableArray *t = [NSMutableArray arrayWithCapacity:count];
    for (size_t i = 0; i < count; i++) [t addObject:@(duration > 0 ? MIN(MAX(timeAt(i) / duration, 0), 1) : 0)];
    return t;
}

- (CAKeyframeAnimation *)vecAnim:(NSString *)path keys:(ufbx_baked_vec3_list)keys duration:(double)dur {
    NSMutableArray *vals = [NSMutableArray arrayWithCapacity:keys.count + 2];
    NSMutableArray *times = [Keys(dur, keys.count, ^double(size_t i) { return keys.data[i].time; }) mutableCopy];
    for (size_t i = 0; i < keys.count; i++) { ufbx_vec3 v = keys.data[i].value; [vals addObject:[NSValue valueWithSCNVector3:SCNVector3Make(v.x, v.y, v.z)]]; }
    if ([times.firstObject doubleValue] > 0) { [times insertObject:@0 atIndex:0]; [vals insertObject:vals.firstObject atIndex:0]; }
    if ([times.lastObject doubleValue] < 1) { [times addObject:@1]; [vals addObject:vals.lastObject]; }
    CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:path];
    a.values = vals; a.keyTimes = times; a.duration = dur; a.calculationMode = kCAAnimationLinear;
    return a;
}

- (CAKeyframeAnimation *)quatAnim:(ufbx_baked_quat_list)keys duration:(double)dur {
    NSMutableArray *vals = [NSMutableArray arrayWithCapacity:keys.count + 2];
    NSMutableArray *times = [Keys(dur, keys.count, ^double(size_t i) { return keys.data[i].time; }) mutableCopy];
    ufbx_quat prev = { .x = 0, .y = 0, .z = 0, .w = 1 };
    for (size_t i = 0; i < keys.count; i++) {
        ufbx_quat q = keys.data[i].value;
        if (i > 0 && q.x * prev.x + q.y * prev.y + q.z * prev.z + q.w * prev.w < 0) { q.x = -q.x; q.y = -q.y; q.z = -q.z; q.w = -q.w; }
        prev = q;
        [vals addObject:[NSValue valueWithSCNVector4:SCNVector4Make(q.x, q.y, q.z, q.w)]];
    }
    if ([times.firstObject doubleValue] > 0) { [times insertObject:@0 atIndex:0]; [vals insertObject:vals.firstObject atIndex:0]; }
    if ([times.lastObject doubleValue] < 1) { [times addObject:@1]; [vals addObject:vals.lastObject]; }
    CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:@"orientation"];
    a.values = vals; a.keyTimes = times; a.duration = dur; a.calculationMode = kCAAnimationLinear;
    return a;
}

@end

@implementation FBXImporter

+ (FBXResult *)loadURL:(NSURL *)url error:(NSString **)errorOut {
    ufbx_load_opts opts = { 0 };
    opts.target_axes = ufbx_axes_right_handed_y_up;
    opts.target_unit_meters = 1.0;
    opts.space_conversion = UFBX_SPACE_CONVERSION_TRANSFORM_ROOT;
    opts.geometry_transform_handling = UFBX_GEOMETRY_TRANSFORM_HANDLING_MODIFY_GEOMETRY;
    opts.generate_missing_normals = true;
    opts.ignore_missing_external_files = true;
    ufbx_error err;
    ufbx_scene *scene = ufbx_load_file(url.fileSystemRepresentation, &opts, &err);
    if (!scene) {
        char buf[512]; ufbx_format_error(buf, sizeof buf, &err);
        if (errorOut) *errorOut = [NSString stringWithFormat:@"%s", err.description.data ? err.description.data : buf];
        return nil;
    }

    FBXBuilder *b = [[FBXBuilder alloc] initWithDir:url.URLByDeletingLastPathComponent];
    NSMutableArray<SCNNode *> *nodes = [NSMutableArray arrayWithCapacity:scene->nodes.count];
    for (size_t i = 0; i < scene->nodes.count; i++) {
        ufbx_node *fn = scene->nodes.data[i];
        SCNNode *n = [SCNNode node];
        n.name = fn->is_root ? @"FBX Root" : Str(fn->name);
        ufbx_transform t = fn->local_transform;
        n.position = SCNVector3Make(t.translation.x, t.translation.y, t.translation.z);
        n.orientation = SCNVector4Make(t.rotation.x, t.rotation.y, t.rotation.z, t.rotation.w);
        n.scale = SCNVector3Make(t.scale.x, t.scale.y, t.scale.z);
        [nodes addObject:n];
    }
    for (size_t i = 0; i < scene->nodes.count; i++) {
        ufbx_node *fn = scene->nodes.data[i];
        if (fn->parent && fn->parent->typed_id < nodes.count) [nodes[fn->parent->typed_id] addChildNode:nodes[i]];
    }
    for (size_t i = 0; i < scene->nodes.count; i++) {
        ufbx_node *fn = scene->nodes.data[i];
        if (fn->mesh) [b attachMesh:fn->mesh fbxNode:fn toNode:nodes[i] nodes:nodes];
    }

    SCNScene *scn = [SCNScene scene];
    SCNNode *root = nodes[scene->root_node->typed_id];
    [scn.rootNode addChildNode:root];

    // Animation takes, baked to linear keys at 30 fps
    NSMutableArray<FBXClip *> *clips = [NSMutableArray new];
    for (size_t s = 0; s < scene->anim_stacks.count; s++) {
        ufbx_anim_stack *stack = scene->anim_stacks.data[s];
        ufbx_bake_opts bo = { 0 };
        bo.trim_start_time = true;
        bo.resample_rate = 30;
        ufbx_error be;
        ufbx_baked_anim *bake = ufbx_bake_anim(scene, stack->anim, &bo, &be);
        if (!bake) continue;
        double dur = bake->playback_duration > 0 ? bake->playback_duration : bake->key_time_max;
        if (dur <= 0.0001) { ufbx_free_baked_anim(bake); continue; }
        NSMutableArray<SCNAnimationPlayer *> *players = [NSMutableArray new];
        for (size_t k = 0; k < bake->nodes.count; k++) {
            ufbx_baked_node bn = bake->nodes.data[k];
            if (bn.typed_id >= nodes.count) continue;
            SCNNode *n = nodes[bn.typed_id];
            if (bn.constant_translation && bn.constant_rotation && bn.constant_scale) {
                // Only keep a static channel if it actually moves the node away from its rest pose.
                ufbx_transform rest = scene->nodes.data[bn.typed_id]->local_transform;
                ufbx_vec3 t0 = bn.translation_keys.count ? bn.translation_keys.data[0].value : rest.translation;
                ufbx_quat q0 = bn.rotation_keys.count ? bn.rotation_keys.data[0].value : rest.rotation;
                ufbx_vec3 s0 = bn.scale_keys.count ? bn.scale_keys.data[0].value : rest.scale;
                double dt = fabs(t0.x - rest.translation.x) + fabs(t0.y - rest.translation.y) + fabs(t0.z - rest.translation.z);
                double dq = 1 - fabs(q0.x * rest.rotation.x + q0.y * rest.rotation.y + q0.z * rest.rotation.z + q0.w * rest.rotation.w);
                double ds = fabs(s0.x - rest.scale.x) + fabs(s0.y - rest.scale.y) + fabs(s0.z - rest.scale.z);
                if (dt < 1e-5 && dq < 1e-7 && ds < 1e-5) continue;
            }
            NSMutableArray *anims = [NSMutableArray new];
            if (bn.translation_keys.count) [anims addObject:[b vecAnim:@"position" keys:bn.translation_keys duration:dur]];
            if (bn.rotation_keys.count) [anims addObject:[b quatAnim:bn.rotation_keys duration:dur]];
            if (bn.scale_keys.count) [anims addObject:[b vecAnim:@"scale" keys:bn.scale_keys duration:dur]];
            if (!anims.count) continue;
            CAAnimationGroup *g = [CAAnimationGroup animation];
            g.animations = anims; g.duration = dur;
            SCNAnimation *sa = [SCNAnimation animationWithCAAnimation:g];
            sa.repeatCount = HUGE_VALF; sa.removedOnCompletion = NO; sa.usesSceneTimeBase = NO;
            SCNAnimationPlayer *p = [SCNAnimationPlayer animationPlayerWithAnimation:sa];
            [n addAnimationPlayer:p forKey:[NSString stringWithFormat:@"fbx-take-%zu", s]];
            [p stop];
            [players addObject:p];
        }
        ufbx_free_baked_anim(bake);
        if (!players.count) continue;
        FBXClip *c = [FBXClip new];
        NSString *nm = Str(stack->name);
        NSRange bar = [nm rangeOfString:@"|" options:NSBackwardsSearch];
        if (bar.location != NSNotFound && bar.location + 1 < nm.length) nm = [nm substringFromIndex:bar.location + 1];
        if ([nm isEqualToString:@"mixamo.com"] || nm.length == 0) nm = scene->anim_stacks.count == 1 ? @"Animation" : [NSString stringWithFormat:@"Take %zu", s + 1];
        c.name = nm; c.duration = dur; c.players = players;
        [clips addObject:c];
    }

    FBXResult *r = [FBXResult new];
    r.scene = scn; r.clips = clips; r.missingTextures = b.missing.allObjects;
    ufbx_free_scene(scene);
    return r;
}

@end
