//
//  GLNode.m
//  GLKit++
//
//  Created by Anton Holmberg on 2012-12-14.
//  Copyright (c) 2012 Anton Holmberg. All rights reserved.
//

#import "GPNode.h"
#import "GPCamera.h"
#import "GPScheduler.h"

#define GPNodeRepeatForever -1

#define GPNodeEasingCurveLinear ^(float f) {return f;}
#define GPNodeEasingCurveEaseInOut ^(float f) {return 0.5f - 0.5f * cosf(M_PI * f);}
#define GPNodeEasingCurveEaseIn ^(float f) {return f * f;}
#define GPNodeEasingCurveEaseOut ^(float f) {return 1 - (f - 1) * (f - 1);}

// GPNodeAnimator should only be used inside the GPNode class.
// It's used for internal animation management.
@interface GPNodeAnimator : NSObject

@property (readonly) BOOL isAnimating;

- (void)runWithDuration:(NSTimeInterval)duration
            easingCurve:(GPNodeEasingCurve)easingCurve
            autoReverse:(BOOL)autoReverse
                  times:(NSInteger)times
           updatesBlock:(GPNodeUpdatesBlock)updatesBlock
        completionBlock:(GPNodeCompletionBlock)completionBlock;

- (void)finishAnimating;

- (GPNodeUpdatesBlock)divideAnimationsBlock:(GPNodeAnimationsBlock)animations
                                   rootNode:(GPNode *)rootNode
                           affectedChildren:(NSMutableArray *)affectedChildren
                                childBlocks:(NSMutableArray *)childBlocks;

@end


@interface GPNode ()

@property GLKMatrix4 storedRotationMatrix;
@property (readonly) GLKMatrix4 rawRotationMatrix;
@property (readonly) GLKMatrix4 rotationMatrix;
@property (nonatomic, strong) NSMutableArray *children;
@property BOOL modelViewMatrixIsDirty;
@property GPNodeAnimator *animator;

@end

@implementation GPNode

@synthesize position = _position;
@synthesize rotation = _rotation;
@synthesize scale = _scale;
@synthesize modelViewMatrix = _modelViewMatrix;
@synthesize modelViewMatrixIsDirty = _modelViewMatrixIsDirty;
@synthesize camera = _camera;

- (id)init {
    if(self = [super init]) {
        self.position = GLKVector3Make(0, 0, 0);
        self.rotation = GLKVector3Make(0, 0, 0);
        self.storedRotationMatrix = GLKMatrix4Identity;
        self.scale = GLKVector3Make(1, 1, 1);
        self.children = [NSMutableArray array];
        self.modelViewMatrixIsDirty = YES;
    }
    return self;
}

+ (GPNode *)node {
    return [[[self class] alloc] init];
}

- (void)dealloc {
    [_camera removeObserver:self forKeyPath:@"modelViewMatrixIsDirty"];
}

- (BOOL)modelViewMatrixIsDirty {
    return _modelViewMatrixIsDirty;
}

- (void)setModelViewMatrixIsDirty:(BOOL)modelViewMatrixIsDirty {
    _modelViewMatrixIsDirty = modelViewMatrixIsDirty;
    
    if(_modelViewMatrixIsDirty) {
        for(GPNode *node in self.children)
            node.modelViewMatrixIsDirty = YES;
    }
}

#pragma mark - Getters / setters

- (void)setPosition:(GLKVector3)position {
    _position = position;
    self.modelViewMatrixIsDirty = YES;
}

- (GLKVector3)position {return _position;}

- (void)setRotation:(GLKVector3)rotation {
    _rotation = rotation;
    self.modelViewMatrixIsDirty = YES;
}

- (GLKVector3)rotation {return _rotation;};

- (void)setScale:(GLKVector3)scale {
    _scale = scale;
    self.modelViewMatrixIsDirty = YES;
}

- (GLKVector3)scale {return _scale;}

#pragma mark - Convenient getters / setters

// Position
- (void)setX:(float)x {_position.x = x;self.modelViewMatrixIsDirty = YES;}
- (float)x {return _position.x;}
- (void)setY:(float)y { _position.y = y;self.modelViewMatrixIsDirty = YES;}
- (float)y { return _position.y;}
- (void)setZ:(float)z {_position.z = z;self.modelViewMatrixIsDirty = YES;}
- (float)z {return _position.z;}

// Rotation
- (void)setRx:(float)rx {_rotation.x = rx;self.modelViewMatrixIsDirty = YES;}
- (float)rx {return _rotation.x;}
- (void)setRy:(float)ry { _rotation.y = ry;self.modelViewMatrixIsDirty = YES;}
- (float)ry { return _rotation.y; }
- (void)setRz:(float)rz {_rotation.z = rz;self.modelViewMatrixIsDirty = YES;}
- (float)rz {return _rotation.z;}

// Scale
- (void)setSx:(float)sx {_scale.x = sx;self.modelViewMatrixIsDirty = YES;}
- (float)sx {return _scale.x;}
- (void)setSy:(float)sy { _scale.y = sy;self.modelViewMatrixIsDirty = YES;}
- (float)sy { return _scale.y; }
- (void)setSz:(float)sz {_scale.z = sz;self.modelViewMatrixIsDirty = YES;}
- (float)sz {return _scale.z;}

- (void)setS:(float)s {
    _scale = GLKVector3Make(s, s, s);
    self.modelViewMatrixIsDirty = YES;
}

- (float)s {return (self.sx + self.sy + self.sz)/3;}

#pragma mark - Children Management

- (void)addChild:(GPNode *)node {
    [self.children addObject:node];
    node.parent = self;
}

- (void)removeChild:(GPNode *)node {
    [self.children removeObject:node];
    node.parent = nil;
}

#pragma mark - Model View Matrix

- (GLKMatrix4)modelViewMatrix {
    if(self.modelViewMatrixIsDirty) {
        GLKMatrix4 scaleMatrix = GLKMatrix4MakeScale(self.invertScale ? 1/self.sx : self.sx,
                                                     self.invertScale ? 1/self.sy : self.sy,
                                                     self.invertScale ? 1/self.sz : self.sz);
        
        GLKMatrix4 localModelViewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeTranslation(self.x, self.y, self.z),
                                                             GLKMatrix4Multiply(scaleMatrix, self.rotationMatrix));
        GLKMatrix4 rawModelViewMatrix = self.parent ? GLKMatrix4Multiply(self.parent.modelViewMatrix, localModelViewMatrix) : localModelViewMatrix;
        
        if([self class] != [GPCamera class])
            NSAssert(self.camera, @"The node must have a camera (may be inherited from the parent");
        
        // Only apply the camera transformation if the node has a camera that is not inherited from the parent
        _modelViewMatrix = _camera ? GLKMatrix4Multiply(GLKMatrix4Invert(_camera.modelViewMatrix, nil), rawModelViewMatrix) : rawModelViewMatrix;
        self.modelViewMatrixIsDirty = NO;
    }
    return _modelViewMatrix;
}

#pragma mark - Camera

- (GPCamera *)camera {
    return _camera ? _camera : self.parent.camera;
}

- (void)setCamera:(GPCamera *)camera {
    [_camera removeObserver:self forKeyPath:@"modelViewMatrixIsDirty"];
    
    _camera = camera;
    [_camera addObserver:self forKeyPath:@"modelViewMatrixIsDirty" options:NSKeyValueObservingOptionNew context:nil];
    self.modelViewMatrixIsDirty = YES;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if(object == self.camera) {
        if(self.camera.modelViewMatrixIsDirty)
            self.modelViewMatrixIsDirty = YES;
    }
}

#pragma mark - Rotation matrices

- (GLKMatrix4)rawRotationMatrix {
    GLKMatrix4 rotationMatrix = GLKMatrix4Identity;
    
    if(self.invertXYRotationOrder) {
        rotationMatrix = GLKMatrix4Rotate(rotationMatrix, self.rx, 1, 0, 0);
        rotationMatrix = GLKMatrix4Rotate(rotationMatrix, self.ry, 0, 1, 0);
        rotationMatrix = GLKMatrix4Rotate(rotationMatrix, self.rz, 0, 0, 1);
    }
    else {
        rotationMatrix = GLKMatrix4Rotate(rotationMatrix, self.ry, 0, 1, 0);
        rotationMatrix = GLKMatrix4Rotate(rotationMatrix, self.rx, 1, 0, 0);
        rotationMatrix = GLKMatrix4Rotate(rotationMatrix, self.rz, 0, 0, 1);
    }
    return rotationMatrix;
}

- (GLKMatrix4)rotationMatrix {
    return GLKMatrix4Multiply(self.rawRotationMatrix, self.storedRotationMatrix);
}

- (void)storeRotation {
    self.storedRotationMatrix = GLKMatrix4Multiply(self.rawRotationMatrix, self.storedRotationMatrix);
    self.rotation = GLKVector3Make(0, 0, 0);
}

- (void)resetStoredRotation {
    self.storedRotationMatrix = GLKMatrix4Identity;
    self.modelViewMatrixIsDirty = YES;
}

- (void)draw {
    if(self.hidden) return;
    
    for(GPNode *child in self.children) {
        [child draw];
    }
}

#pragma mark - Touch handling

- (BOOL)isTouchingNode:(UITouch *)touch {
    for(GPNode *node in self.children) {
        if([node isTouchingNode:touch]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Properties copying/interpolation

// Provides a constructor which doesn't do anything.
// This allows the method copyWithSameProperties to create "cheap"
// copies of objects of subclasses even if they do all kinds of
// resource intense stuff in the default init constructor.
- (id)initShallow {
    if (self = [super init]) {
        
    }
    return self;
}

- (GPNode *)copyWithSameProperties {
    GPNode *node = [[[self class] alloc] initShallow];
    [node applyPropertiesOfNode:self];
    return node;
}

- (void)applyPropertiesOfNode:(GPNode *)node {
    self.position = node.position;
    self.rotation = node.rotation;
    self.scale = node.scale;
}

- (void)lerpUnequalPropertiesFromNode:(GPNode *)fromNode toNode:(GPNode *)toNode fraction:(float)f {
    if(!GLKVector3AllEqualToVector3(fromNode.position, toNode.position))
        self.position = GLKVector3Lerp(fromNode.position, toNode.position, f);
    if(!GLKVector3AllEqualToVector3(fromNode.rotation, toNode.rotation))
        self.rotation = GLKVector3Lerp(fromNode.rotation, toNode.rotation, f);
    if(!GLKVector3AllEqualToVector3(fromNode.scale, toNode.scale))
        self.scale = GLKVector3Lerp(fromNode.scale, toNode.scale, f);
}

- (BOOL)propertiesAreEqualToNode:(GPNode *)node {
    return
    GLKVector3AllEqualToVector3(self.position, node.position) &&
    GLKVector3AllEqualToVector3(self.rotation, node.rotation) &&
    GLKVector3AllEqualToVector3(self.scale, node.scale);
}


#pragma mark - Recursive tree functions

typedef void(^ChildrenWorkBlock)(GPNode *node);

// Depth first visit
- (void)enumerateChildrenRecursively:(ChildrenWorkBlock)block {
    for(GPNode *child in self.children) {
        block(child);
        [child enumerateChildrenRecursively:block];
    }
}

- (NSArray *)childrenInTree {
    NSMutableArray *childrenInTree = [NSMutableArray array];
    [self enumerateChildrenRecursively:^(GPNode *child) {
        [childrenInTree addObject:child];
    }];
    return childrenInTree;
}

- (void)finishChildAnimationsRecursively {
    [self enumerateChildrenRecursively:^(GPNode *child) {
        [child finishAnimation];
    }];
}

#pragma mark - Animation

- (BOOL)isAnimating {
    return self.animator.isAnimating;
}

- (void)finishAnimation {
    if(self.animator.isAnimating) {
        [self.animator finishAnimating];
    }
    
    self.animator = nil;
}

- (GPNodeEasingCurve)easingCurveFromOptions:(GPAnimationOptionsMask)options {
    if(options & GPAnimationNoEase) return GPNodeEasingCurveLinear;
    else if(options & GPAnimationEaseIn) return GPNodeEasingCurveEaseIn;
    else if(options & GPAnimationEaseOut) return GPNodeEasingCurveEaseOut;
    else if(options & GPAnimationEaseInOut) return GPNodeEasingCurveEaseInOut;
    
    if(options & GPAnimationRepeat && !(options & GPAnimationAutoReverse))
        return GPNodeEasingCurveLinear;
    else return GPNodeEasingCurveEaseInOut;
}

#pragma mark - Animations block based animation method

- (void)animateWithDuration:(NSTimeInterval)duration
                 animations:(GPNodeAnimationsBlock)animations
{
    [self animateWithDuration:duration
                  easingCurve:nil
                      options:0
                   animations:animations
                   completion:nil];
}

- (void)animateWithDuration:(NSTimeInterval)duration
                 animations:(GPNodeAnimationsBlock)animations
                 completion:(GPNodeCompletionBlock)completion
{
    [self animateWithDuration:duration
                  easingCurve:nil
                      options:0
                   animations:animations
                   completion:completion];
}


- (void)animateWithDuration:(NSTimeInterval)duration
                    options:(GPAnimationOptionsMask)options
                 animations:(GPNodeAnimationsBlock)animations
{
    [self animateWithDuration:duration
                  easingCurve:nil
                      options:options
                   animations:animations
                   completion:nil];
}

- (void)animateWithDuration:(NSTimeInterval)duration
                    options:(GPAnimationOptionsMask)options
                 animations:(GPNodeAnimationsBlock)animations
                 completion:(GPNodeCompletionBlock)completion
{
    [self animateWithDuration:duration
                  easingCurve:nil
                      options:options
                   animations:animations
                   completion:completion];
}

- (void)animateWithDuration:(NSTimeInterval)duration
                easingCurve:(GPNodeEasingCurve)easingCurve
                    options:(GPAnimationOptionsMask)options
                 animations:(GPNodeAnimationsBlock)animations
{
    [self animateWithDuration:duration
                  easingCurve:easingCurve
                      options:options
                   animations:animations
                   completion:nil];
}

// Designated animation method
- (void)animateWithDuration:(NSTimeInterval)duration
                easingCurve:(GPNodeEasingCurve)easingCurve
                    options:(GPAnimationOptionsMask)options
                 animations:(GPNodeAnimationsBlock)animations
                 completion:(GPNodeCompletionBlock)completion
{
    [self animateWithDuration:duration
                  easingCurve:easingCurve ? easingCurve : [self easingCurveFromOptions:options]
                  autoReverse:options & GPAnimationAutoReverse
                        times:(options & GPAnimationRepeat) ? GPNodeRepeatForever : 1
                   animations:animations
                   completion:completion];
}

#pragma mark - Updates block based animation methods

- (void)animateWithDuration:(NSTimeInterval)duration
                    updates:(GPNodeUpdatesBlock)updates
{
    [self animateWithDuration:duration
                  easingCurve:nil
                      options:0
                      updates:updates
                   completion:nil];
}

- (void)animateWithDuration:(NSTimeInterval)duration
                    updates:(GPNodeUpdatesBlock)updates
                 completion:(GPNodeCompletionBlock)completion
{
    [self animateWithDuration:duration
                  easingCurve:nil
                      options:0
                      updates:updates
                   completion:completion];
}


- (void)animateWithDuration:(NSTimeInterval)duration
                    options:(GPAnimationOptionsMask)options
                    updates:(GPNodeUpdatesBlock)updates
{
    [self animateWithDuration:duration
                  easingCurve:nil
                      options:options
                      updates:updates
                   completion:nil];
}

- (void)animateWithDuration:(NSTimeInterval)duration
                    options:(GPAnimationOptionsMask)options
                    updates:(GPNodeUpdatesBlock)updates
                 completion:(GPNodeCompletionBlock)completion
{
    [self animateWithDuration:duration
                  easingCurve:nil
                      options:options
                      updates:updates
                   completion:completion];
}

- (void)animateWithDuration:(NSTimeInterval)duration
                easingCurve:(GPNodeEasingCurve)easingCurve
                    options:(GPAnimationOptionsMask)options
                    updates:(GPNodeUpdatesBlock)updates
{
    [self animateWithDuration:duration
                  easingCurve:easingCurve
                      options:options
                      updates:updates
                   completion:nil];
}

// Designated animation method
- (void)animateWithDuration:(NSTimeInterval)duration
                easingCurve:(GPNodeEasingCurve)easingCurve
                    options:(GPAnimationOptionsMask)options
                    updates:(GPNodeUpdatesBlock)updates
                 completion:(GPNodeCompletionBlock)completion
{
    [self animateWithDuration:duration
                  easingCurve:easingCurve ? easingCurve : [self easingCurveFromOptions:options]
                  autoReverse:options & GPAnimationAutoReverse
                        times:(options & GPAnimationRepeat) ? GPNodeRepeatForever : 1
                      updates:updates
                   completion:completion];
}

#pragma mark - Actual internal animation methods

- (void)animateWithDuration:(NSTimeInterval)duration
                easingCurve:(GPNodeEasingCurve)easingCurve
                autoReverse:(BOOL)autoReverse
                      times:(NSInteger)times
                    updates:(GPNodeUpdatesBlock)updates
                 completion:(GPNodeCompletionBlock)completionBlock {
    
    [self finishAnimation];
    
    self.animator = [[GPNodeAnimator alloc] init];
    
    [self.animator runWithDuration:duration
                       easingCurve:easingCurve
                       autoReverse:autoReverse
                             times:times
                      updatesBlock:updates
                   completionBlock:completionBlock];
}

// This is where the magic happens
- (void)animateWithDuration:(NSTimeInterval)duration
                easingCurve:(GPNodeEasingCurve)easingCurve
                autoReverse:(BOOL)autoReverse
                      times:(NSInteger)times
                 animations:(GPNodeAnimationsBlock)animations
                 completion:(GPNodeCompletionBlock)completionBlock {
    
    [self finishAnimation];
    
    self.animator = [[GPNodeAnimator alloc] init];
    
    NSMutableArray *affectedChildren = [NSMutableArray array];
    NSMutableArray *childBlocks = [NSMutableArray array];
    
    // extract local updates, affected children and children updates block
    // by running the animations block only once
    // affectedChildren and childBlocks are filled by the method
    GPNodeUpdatesBlock localBlock = [self.animator divideAnimationsBlock:animations
                                                                rootNode:self
                                                        affectedChildren:affectedChildren
                                                             childBlocks:childBlocks];
    if(duration > 0) {
        
        [self.animator runWithDuration:duration
                           easingCurve:easingCurve
                           autoReverse:autoReverse
                                 times:times
                          updatesBlock:localBlock
                       completionBlock:^{
                           [self finishChildAnimationsRecursively];
                           if(completionBlock)
                               completionBlock();
                       }];
        
        for(int i = 0; i < affectedChildren.count; i++) {
            [[affectedChildren objectAtIndex:i] animateWithDuration:duration
                                                        easingCurve:easingCurve
                                                        autoReverse:autoReverse
                                                              times:times
                                                            updates:[childBlocks objectAtIndex:i]
                                                         completion:^{[self finishAnimation];}];
        }
    }
    else {
        localBlock(autoReverse ? 0 : 1);
        for(GPNodeAnimationsBlock childBlock in childBlocks) {
            childBlock(autoReverse ? 0 : 1);
        }
        completionBlock();
    }
}

@end


#pragma mark - GPNodeAnimator Implementation

@interface GPNodeAnimator ()

@property NSTimeInterval duration;
@property (nonatomic, strong) GPNodeEasingCurve easingCurve;
@property float normalizedLength;
@property NSInteger timesLeft;
@property float elapsedTime;

@property (nonatomic, strong) GPNodeUpdatesBlock updatesBlock;
@property (nonatomic, strong) GPNodeCompletionBlock completionBlock;

@end

@implementation GPNodeAnimator

- (void)runWithDuration:(NSTimeInterval)duration
            easingCurve:(GPNodeEasingCurve)easingCurve
            autoReverse:(BOOL)autoReverse
                  times:(NSInteger)times
           updatesBlock:(GPNodeUpdatesBlock)updatesBlock
        completionBlock:(GPNodeCompletionBlock)completionBlock {
    
    if(self.isAnimating) {
        [self finishAnimating];
    }
    
    self.updatesBlock = updatesBlock;
    self.completionBlock = completionBlock;
    
    self.elapsedTime = 0;
    self.duration = duration;
    self.easingCurve = easingCurve;
    
    self.normalizedLength = autoReverse ? 2 : 1;
    self.timesLeft = times;
    
    if(self.duration > 0) {
        [[GPScheduler defaultScheduler] scheduleUpdates:self];
    }
    else {
        [self finishAnimating];
    }
}

// extract local updates, affected children and children updates block
// by running the animations block only once
// affectedChildren and childBlocks are filled by the method
- (GPNodeUpdatesBlock)divideAnimationsBlock:(GPNodeAnimationsBlock)animations
                                   rootNode:(GPNode *)rootNode
                           affectedChildren:(NSMutableArray *)affectedChildren
                                childBlocks:(NSMutableArray *)childBlocks
{
    NSArray *children = [rootNode childrenInTree];
    
    NSMutableArray *startChildren = [NSMutableArray arrayWithCapacity:children.count];
    for(GPNode *child in children)
        [startChildren addObject:[child copyWithSameProperties]];
    
    GPNode *startRootNode = [rootNode copyWithSameProperties];
    
    animations();
    
    NSMutableArray *endChildren = [NSMutableArray arrayWithCapacity:children.count];
    for(GPNode *child in children)
        [endChildren addObject:[child copyWithSameProperties]];
    
    GPNode *endRootNode = [rootNode copyWithSameProperties];
    
    for(int i = 0; i < children.count; i++) {
        GPNode *child = [children objectAtIndex:i];
        GPNode *startChild = [startChildren objectAtIndex:i];
        GPNode *endChild = [endChildren objectAtIndex:i];
        
        [child applyPropertiesOfNode:startChild];
        
        if(![startChild propertiesAreEqualToNode:endChild]) {
            [affectedChildren addObject:child];
            [childBlocks addObject:[^(float f) {
                [child lerpUnequalPropertiesFromNode:startChild toNode:endChild fraction:f];
            } copy]];
        }
    }
    
    [rootNode applyPropertiesOfNode:startRootNode];
    
    return [^(float f) {
        [rootNode lerpUnequalPropertiesFromNode:startRootNode toNode:endRootNode fraction:f];
    } copy];
}

- (BOOL)isAnimating {
    return self.updatesBlock != nil;
}

- (void)update:(GLKViewController *)vc {
    self.elapsedTime += vc.timeSinceLastUpdate;
    
    float realDuration = self.duration * self.normalizedLength;
    if(self.elapsedTime < realDuration) {
        [self updateAnimation:self.elapsedTime/self.duration];
    }
    else {
        BOOL repeat = NO;
        if(self.timesLeft != GPNodeRepeatForever) {
            self.timesLeft--;
            if(self.timesLeft <= 0) {
                [self finishAnimating];
            }
            else {
                repeat = YES;
            }
        }
        else {
            repeat = YES;
        }
        
        if(repeat) {
            self.elapsedTime -= floorf(self.elapsedTime/realDuration) * realDuration;
            [self updateAnimation:self.elapsedTime/self.duration];
        }
    }
}

- (void)finishAnimating {
    if(!self.isAnimating) return;
    
    if(self.duration > 0)
        [[GPScheduler defaultScheduler] unscheduleUpdates:self];
    
    [self updateAnimation:self.normalizedLength];
    
    self.updatesBlock = nil;
    self.easingCurve = nil;
    self.duration = 0;
    self.elapsedTime = 0;
    
    // Assign the completion block to a local variable in case
    // The block makes this animator animate again.
    GPNodeCompletionBlock completionBlock = self.completionBlock;
    self.completionBlock = nil;
    
    if(completionBlock)
        completionBlock();
    
}

- (void)updateAnimation:(float)f {
    float localF = self.easingCurve(f > 1 ? 2 - f : f);
    if(self.updatesBlock) {
        self.updatesBlock(localF);
    }
    else {
        NSLog(@"Node animator is animating without an updates block!");
    }
}

@end


