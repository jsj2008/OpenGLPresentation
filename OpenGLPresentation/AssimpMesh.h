//
//  AssimpMesh.h
//  OpenGLPresentation
//
//  Created by Emma Steimann on 8/22/16.
//  Copyright © 2016 Emma Steimann. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <GLKit/GLKit.h>
#include <assimp/cimport.h>
#include <assimp/scene.h>

@interface AssimpMesh : NSObject
@property (nonatomic, assign) GLKVector3 position;
@property (nonatomic) float rotationX;
@property (nonatomic) float rotationY;
@property (nonatomic) float rotationZ;
@property (nonatomic) float scale;
@property (nonatomic) GLuint texture;
@property (assign) GLKVector4 matColor;
@property (assign) float width;
@property (assign) float height;

@property (nonatomic, strong) NSMutableArray *children;
-(instancetype)initWithName:(char *)name;
-(instancetype)initWithName:(char *)name andFileName:(NSString *)fileName andExtenstion:(NSString *)extension;
- (void)renderWithParentModelViewMatrix:(GLKMatrix4)parentModelViewMatrix;
- (void)updateWithDelta:(NSTimeInterval)dt;
@end
