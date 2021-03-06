//
//  AssimpMesh.m
//  OpenGLPresentation
//
//  Created by Emma Steimann on 8/22/16.
//  Copyright © 2016 Emma Steimann. All rights reserved.
//

#import "AssimpMesh.h"
#import "GLAssimpEffect.hpp"
#include <assimp/Importer.hpp>      // C++ importer interface
#include <assimp/scene.h>           // Output data structure
#include <assimp/postprocess.h>
#include "Common.hpp"
#include "AssimpMeshEntry.hpp"
#import "GLDirector.h"
#include "Animator.hpp"
#include <map>

#define POSITION_LOCATION    0
#define TEX_COORD_LOCATION   1
#define NORMAL_LOCATION      2
#define BONE_ID_LOCATION     3
#define BONE_WEIGHT_LOCATION 4

#define GLCheckError() (glGetError() == GL_NO_ERROR)

@interface AssimpMesh()
@end

@implementation AssimpMesh {
  std::vector<MeshEntry> m_Entries;
  std::vector<GLKTextureInfo*> m_Textures;
  char *_name;
  GLAssimpEffect *_assimpShader;
  GLuint _vao;
  GLuint m_VAO;
  std::map<std::string,uint> m_BoneMapping;
  uint m_NumBones;
  std::vector<BoneInfo> m_BoneInfo;
  aiMatrix4x4 m_GlobalInverseTransform;
  GLuint m_Buffers[NUM_VBs];
  const aiScene* m_pScene;
  Assimp::Importer m_Importer;
  Animator * m_pAnimator;
}

-(instancetype)initWithName:(char *)name andFileName:(NSString *)fileName andExtenstion:(NSString *)extension {
  if (self = [super init]){
    _name = name;

    self.position = GLKVector3Make(0, 0, 0);
    self.rotationX = -M_PI_2;
    self.rotationY = 0;
    self.rotationZ = 0;
    self.scale = 1.0;
    self.children = [NSMutableArray array];
    self.matColor = GLKVector4Make(1, 1, 1, 1);

    ZERO_MEM(m_Buffers);

    _assimpShader = [[GLAssimpEffect alloc] initWithVertexShader:@"GLSimpleBoneVertex.glsl" fragmentShader:@"GLSimpleBoneFragment.glsl"];

    [self loadMeshWithFileName:fileName andExtension:extension];
  }
  return self;
}

-(instancetype)initWithName:(char *)name {
  if (self = [super init]){
    _name = name;

    self.position = GLKVector3Make(0, 0, 0);
    self.rotationX = -M_PI_2;
    self.rotationY = 0;
    self.rotationZ = 0;
    self.scale = 1.0;
    self.children = [NSMutableArray array];
    self.matColor = GLKVector4Make(1, 1, 1, 1);

    ZERO_MEM(m_Buffers);

    _assimpShader = [[GLAssimpEffect alloc] initWithVertexShader:@"GLSimpleBoneVertex.glsl" fragmentShader:@"GLSimpleBoneFragment.glsl"];

    [self loadMeshWithFileName:@"TeamFlareAdmin" andExtension:@"DAE"];
  }
  return self;
}

#pragma mark - Assimp Boiler Plate

- (BOOL)loadMeshWithFileName:(NSString *)fileName andExtension:(NSString *)extension  {

  // should do a Clear here?

  // Create the VAO
  glGenVertexArrays(1, &m_VAO);
  glBindVertexArray(m_VAO);

  // Create the buffers for the vertices attributes
  glGenBuffers(ARRAY_SIZE_IN_ELEMENTS(m_Buffers), m_Buffers);

  BOOL Ret = false;

  Assimp::Importer* importer = new Assimp::Importer();
  importer->SetExtraVerbose(true);

  NSBundle *bundle = [NSBundle mainBundle];
  NSString *path = [bundle pathForResource:fileName ofType:extension];
  const char *cPath =[path cStringUsingEncoding: NSUTF8StringEncoding];

  m_pScene = importer->ReadFile(cPath, aiProcess_Triangulate | aiProcess_GenSmoothNormals | aiProcess_FlipUVs);

  if (m_pScene) {
    m_GlobalInverseTransform = m_pScene->mRootNode->mTransformation;
    m_GlobalInverseTransform.Inverse();
    Ret = [self initFromScene:m_pScene withFilePath:cPath];
  } else {
    printf("Error parsing '%s': '%s'\n", cPath, importer->GetErrorString());
  }

  if (m_pScene->HasAnimations()) {
    m_pAnimator = new Animator(m_pScene, 0);
  }

  delete importer;

  glBindVertexArray(0);

  return Ret;
}

- (BOOL)initFromScene:(const aiScene *)pScene withFilePath:(const char *)filePath {
  m_Entries.resize(pScene->mNumMeshes);
  m_Textures.resize(pScene->mNumMaterials);

  std::vector<GLKVector3> Positions;
  std::vector<GLKVector3> Normals;
  std::vector<GLKVector2> TexCoords;
  std::vector<VertexBoneData> Bones;
  std::vector<uint> Indices;

  uint NumVertices = 0;
  uint NumIndices = 0;

  // Count the number of vertices and indices
  for (uint i = 0 ; i < m_Entries.size() ; i++) {
    m_Entries[i].MaterialIndex = pScene->mMeshes[i]->mMaterialIndex;
    m_Entries[i].NumIndices    = pScene->mMeshes[i]->mNumFaces * 3;
    m_Entries[i].BaseVertex    = NumVertices;
    m_Entries[i].BaseIndex     = NumIndices;
    m_Entries[i].ReferenceId   = i;

    NumVertices += pScene->mMeshes[i]->mNumVertices;
    NumIndices  += m_Entries[i].NumIndices;
  }

  // Reserve space in the vectors for the vertex attributes and indices
  Positions.reserve(NumVertices);
  Normals.reserve(NumVertices);
  TexCoords.reserve(NumVertices);
  Bones.resize(NumVertices);
  Indices.reserve(NumIndices);


  // Initialize the meshes in the scene one by one
  for (unsigned int i = 0 ; i < pScene->mNumMeshes ; i++) {
    const aiMesh* paiMesh = pScene->mMeshes[i];
    [self initMesh:paiMesh withIndex:i andPosition:Positions andNormals:Normals andTex:TexCoords andBones:Bones andIndices:Indices];
  }

  if (![self initMaterials:pScene withFilePath:filePath]) {
    return NO;
  }

  // Generate and populate the buffers with vertex attributes and the indices
  glBindBuffer(GL_ARRAY_BUFFER, m_Buffers[POS_VB]);
  glBufferData(GL_ARRAY_BUFFER, sizeof(Positions[0]) * Positions.size(), &Positions[0], GL_STATIC_DRAW);
  glEnableVertexAttribArray(POSITION_LOCATION);
  glVertexAttribPointer(POSITION_LOCATION, 3, GL_FLOAT, GL_FALSE, 0, 0);

  glBindBuffer(GL_ARRAY_BUFFER, m_Buffers[TEXCOORD_VB]);
  glBufferData(GL_ARRAY_BUFFER, sizeof(TexCoords[0]) * TexCoords.size(), &TexCoords[0], GL_STATIC_DRAW);
  glEnableVertexAttribArray(TEX_COORD_LOCATION);
  glVertexAttribPointer(TEX_COORD_LOCATION, 2, GL_FLOAT, GL_FALSE, 0, 0);

  glBindBuffer(GL_ARRAY_BUFFER, m_Buffers[NORMAL_VB]);
  glBufferData(GL_ARRAY_BUFFER, sizeof(Normals[0]) * Normals.size(), &Normals[0], GL_STATIC_DRAW);
  glEnableVertexAttribArray(NORMAL_LOCATION);
  glVertexAttribPointer(NORMAL_LOCATION, 3, GL_FLOAT, GL_FALSE, 0, 0);

  glBindBuffer(GL_ARRAY_BUFFER, m_Buffers[BONE_VB]);
  glBufferData(GL_ARRAY_BUFFER, sizeof(Bones[0]) * Bones.size(), &Bones[0], GL_STATIC_DRAW);

  glEnableVertexAttribArray(BONE_ID_LOCATION);
  glVertexAttribIPointer(BONE_ID_LOCATION, 4, GL_INT, sizeof(VertexBoneData), (const GLvoid*) offsetof(VertexBoneData, IDs));
  glEnableVertexAttribArray(BONE_WEIGHT_LOCATION);
  glVertexAttribPointer(BONE_WEIGHT_LOCATION, 4, GL_FLOAT, GL_FALSE, sizeof(VertexBoneData), (const GLvoid*) offsetof(VertexBoneData, Weights));

  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m_Buffers[INDEX_BUFFER]);
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(Indices[0]) * Indices.size(), &Indices[0], GL_STATIC_DRAW);

  return GLCheckError();
}

- (void)initMesh:(const aiMesh*)paiMesh withIndex:(unsigned int)MeshIndex andPosition:(std::vector<GLKVector3> &)Positions andNormals:(std::vector<GLKVector3> &)Normals andTex:(std::vector<GLKVector2> &)TexCoords andBones:(std::vector<VertexBoneData> &)Bones andIndices:(std::vector<uint> &)Indices {

  const aiVector3D Zero3D(0.0f, 0.0f, 0.0f);

  // Populate the vertex attribute vectors
  for (uint i = 0 ; i < paiMesh->mNumVertices ; i++) {
    const aiVector3D* pPos      = &(paiMesh->mVertices[i]);
    const aiVector3D* pNormal   = &(paiMesh->mNormals[i]);
    const aiVector3D* pTexCoord = paiMesh->HasTextureCoords(0) ? &(paiMesh->mTextureCoords[0][i]) : &Zero3D;

    Positions.push_back(GLKVector3Make(pPos->x, pPos->y, pPos->z));
    Normals.push_back(GLKVector3Make(pNormal->x, pNormal->y, pNormal->z));
    TexCoords.push_back(GLKVector2Make(pTexCoord->x, pTexCoord->y));
  }
  //
  //  for (int i=0; i<Positions.size(); i++)
  //    printf("Px: %f, Py: %f, Pz: %f", Positions.at(i).x, Positions.at(i).y, Positions.at(i).z);
//    for (int i=0; i<Normals.size(); i++)
//      printf("Nx: %f, Ny: %f, Nz: %f", Normals.at(i).x, Normals.at(i).y, Normals.at(i).z);
//      for (int i=0; i<TexCoords.size(); i++)
//        printf("Tu: %f, Tv: %f", TexCoords.at(i).x, TexCoords.at(i).y);



  [self loadBones:Bones withMesh:paiMesh andIndex:MeshIndex];

  // Populate the index buffer
  for (uint i = 0 ; i < paiMesh->mNumFaces ; i++) {
    const aiFace& Face = paiMesh->mFaces[i];
    assert(Face.mNumIndices == 3);
    Indices.push_back(Face.mIndices[0]);
    Indices.push_back(Face.mIndices[1]);
    Indices.push_back(Face.mIndices[2]);
  }
}

- (void)loadBones:(std::vector<VertexBoneData>&)Bones withMesh:(const aiMesh*)pMesh andIndex:(uint)MeshIndex {
  for (uint i = 0 ; i < pMesh->mNumBones ; i++) {
    uint BoneIndex = 0;
    std::string BoneName(pMesh->mBones[i]->mName.data);

    if (m_BoneMapping.find(BoneName) == m_BoneMapping.end()) {
      // Allocate an index for a new bone
      BoneIndex = m_NumBones;
      m_NumBones++;
      BoneInfo bi;
      m_BoneInfo.push_back(bi);
      m_BoneInfo[BoneIndex].BoneOffset = pMesh->mBones[i]->mOffsetMatrix;
      m_BoneMapping[BoneName] = BoneIndex;
    }
    else {
      BoneIndex = m_BoneMapping[BoneName];
    }

    for (uint j = 0 ; j < pMesh->mBones[i]->mNumWeights ; j++) {
      uint VertexID = m_Entries[MeshIndex].BaseVertex + pMesh->mBones[i]->mWeights[j].mVertexId;
      float Weight  = pMesh->mBones[i]->mWeights[j].mWeight;
      Bones[VertexID].AddBoneData(BoneIndex, Weight);
    }
  }

}

- (BOOL)initMaterials:(const aiScene *)pScene withFilePath:(const char *)filePath {
  // Extract the directory part from the file name
  std::string Filename = std::string(filePath);
  std::string::size_type SlashIndex = Filename.find_last_of("/");
  std::string Dir;

  if (SlashIndex == std::string::npos) {
    Dir = ".";
  }
  else if (SlashIndex == 0) {
    Dir = "/";
  }
  else {
    Dir = Filename.substr(0, SlashIndex);
  }

  bool Ret = true;

  // Initialize the materials
  for (unsigned int i = 0 ; i < pScene->mNumMaterials ; i++) {
    const aiMaterial* pMaterial = pScene->mMaterials[i];

    m_Textures[i] = NULL;

    if (pMaterial->GetTextureCount(aiTextureType_DIFFUSE) > 0) {
      aiString Path;

      if (pMaterial->GetTexture(aiTextureType_DIFFUSE, 0, &Path, NULL, NULL, NULL, NULL, NULL) == AI_SUCCESS) {
        std::string FullPath = Dir + "/" + Path.data;
        NSString *pathString = [NSString stringWithUTF8String:FullPath.c_str()];
        NSError *error = nil;

        NSString *path = [[NSBundle mainBundle] pathForResource:[pathString lastPathComponent] ofType:nil];

        GLKTextureInfo *info = [GLKTextureLoader textureWithContentsOfFile:path options:nil error:&error];
        if (info == nil) {
          NSLog(@"%@", path);
          NSLog(@"Error loading file: %@", error.localizedDescription);
          m_Textures[i] = NULL;
          Ret = false;
        } else {
          m_Textures[i] = info;
        }
      }
    }

    // Load a white texture in case the model does not include its own texture
    if (!m_Textures[i]) {
      NSError *error = nil;
      NSString *path = [[NSBundle mainBundle] pathForResource:@"white.png" ofType:nil];

      NSDictionary *options = @{};
      GLKTextureInfo *info = [GLKTextureLoader textureWithContentsOfFile:path options:options error:&error];
      m_Textures[i] = info;

      if (info == nil) {
        NSLog(@"Error loading file: %@", error.localizedDescription);
        m_Textures[i] = NULL;
        Ret = false;
      }
    }
  }

  return Ret;
}

#pragma mark - Integrated Rending Code

- (void)renderWithParentModelViewMatrix:(GLKMatrix4)parentModelViewMatrix {

  GLKMatrix4 modelViewMatrix = GLKMatrix4Multiply(parentModelViewMatrix, [self modelMatrix]);

  for (id child in self.children) {
    if ([child respondsToSelector:@selector(renderWithParentModelViewMatrix:)]) {
      [child renderWithParentModelViewMatrix:modelViewMatrix];
    }
  }

  glBindVertexArray(m_VAO);

  for (unsigned int i = 0 ; i < m_Entries.size() ; i++) {

    _assimpShader.modelViewMatrix = modelViewMatrix;
    _assimpShader.projectionMatrix = [GLDirector sharedInstance].sceneProjectionMatrix;
    _assimpShader.matColor = self.matColor;

    const unsigned int MaterialIndex = m_Entries[i].MaterialIndex;

    if (MaterialIndex < m_Textures.size() && m_Textures[MaterialIndex]) {
      glActiveTexture(GL_TEXTURE0+m_Textures[MaterialIndex].name);
      _assimpShader.texture = m_Textures[MaterialIndex].name;
      glBindTexture(GL_TEXTURE_2D, m_Textures[MaterialIndex].name);

    }

    //    printf("Num indices: %d", m_Entries[i].NumIndices);
    //    printf("Num indices: %d", m_Entries[i].BaseIndex);
    //    printf("Num indices: %d", m_Entries[i].BaseVertex);

    [_assimpShader prepareToDraw];
//
//    glm::mat4* pMatrices = new glm::mat4[MAXBONESPERMESH];
//
//    //upload bone matrices
//    if ((m_pScene->mMeshes[m_Entries[i].ReferenceId]->HasBones()) && (m_pAnimator != NULL)) {
//      const std::vector<aiMatrix4x4>& vBoneMatrices = m_pAnimator->GetBoneMatrices(pNode, i);
//
//      if (vBoneMatrices.size() != pCurrentMesh->mNumBones) {
//        continue;
//      }
//
//      for (unsigned int j = 0; j < pCurrentMesh->mNumBones; j++) {
//        if (j < MAXBONESPERMESH) {
//          pMatrices[j][0][0] = vBoneMatrices[j].a1;
//          pMatrices[j][0][1] = vBoneMatrices[j].b1;
//          pMatrices[j][0][2] = vBoneMatrices[j].c1;
//          pMatrices[j][0][3] = vBoneMatrices[j].d1;
//          pMatrices[j][1][0] = vBoneMatrices[j].a2;
//          pMatrices[j][1][1] = vBoneMatrices[j].b2;
//          pMatrices[j][1][2] = vBoneMatrices[j].c2;
//          pMatrices[j][1][3] = vBoneMatrices[j].d2;
//          pMatrices[j][2][0] = vBoneMatrices[j].a3;
//          pMatrices[j][2][1] = vBoneMatrices[j].b3;
//          pMatrices[j][2][2] = vBoneMatrices[j].c3;
//          pMatrices[j][2][3] = vBoneMatrices[j].d3;
//          pMatrices[j][3][0] = vBoneMatrices[j].a4;
//          pMatrices[j][3][1] = vBoneMatrices[j].b4;
//          pMatrices[j][3][2] = vBoneMatrices[j].c4;
//          pMatrices[j][3][3] = vBoneMatrices[j].d4;
//        }
//      }
    if ([[GLDirector sharedInstance] currentView] == ShowDots) {
      //    Drawing just dots with blackness
          [_assimpShader toggleNormalcy];

          [_assimpShader toggleBlackness];
          glPointSize(2.0f);
          glDrawElementsBaseVertex(GL_POINTS,
                                   m_Entries[i].NumIndices,
                                   GL_UNSIGNED_INT,
                                   (void*)(sizeof(uint) * m_Entries[i].BaseIndex),
                                   m_Entries[i].BaseVertex);
          [_assimpShader toggleBlackness];
          [_assimpShader toggleNormalcy];

    } else if ([[GLDirector sharedInstance] currentView] == ShowWireFrame) {
      //    Drawing with overlayed wireframe:
          [_assimpShader toggleNormalcy];
          glEnable(GL_POLYGON_OFFSET_FILL);
          glPolygonOffset(5.0f, 5.0f);
          glDrawElementsBaseVertex(GL_TRIANGLES,
                                   m_Entries[i].NumIndices,
                                   GL_UNSIGNED_INT,
                                   (void*)(sizeof(uint) * m_Entries[i].BaseIndex),
                                   m_Entries[i].BaseVertex);
          glDisable(GL_POLYGON_OFFSET_FILL);
      
          [_assimpShader toggleBlackness];
            glPolygonMode( GL_FRONT_AND_BACK, GL_LINE );
            glLineWidth(2.0f);
            glDrawElementsBaseVertex(GL_TRIANGLES,
                                   m_Entries[i].NumIndices,
                                   GL_UNSIGNED_INT,
                                   (void*)(sizeof(uint) * m_Entries[i].BaseIndex),
                                   m_Entries[i].BaseVertex);
            glPolygonMode( GL_FRONT_AND_BACK, GL_FILL );
          [_assimpShader toggleBlackness];
          [_assimpShader toggleNormalcy];
//          glEnable(GL_POLYGON_OFFSET_FILL);
//          glPolygonOffset(5.0f, 5.0f);
//          glDrawElementsBaseVertex(GL_TRIANGLES,
//                                   m_Entries[i].NumIndices,
//                                   GL_UNSIGNED_INT,
//                                   (void*)(sizeof(uint) * m_Entries[i].BaseIndex),
//                                   m_Entries[i].BaseVertex);
//          glDisable(GL_POLYGON_OFFSET_FILL);

    }  else if ([[GLDirector sharedInstance] currentView] == ShowColorDots) {
//          [_assimpShader toggleBlackness];
          [_assimpShader toggleNormalcy];
          glPointSize(5.0f);
          glDrawElementsBaseVertex(GL_POINTS,
                                   m_Entries[i].NumIndices,
                                   GL_UNSIGNED_INT,
                                   (void*)(sizeof(uint) * m_Entries[i].BaseIndex),
                                   m_Entries[i].BaseVertex);
          [_assimpShader toggleNormalcy];
//          [_assimpShader toggleBlackness];

    } else {
//    Normal Drawing:
//
//    [_assimpShader toggleNormalcy];
    glDrawElementsBaseVertex(GL_TRIANGLES,
                             m_Entries[i].NumIndices,
                             GL_UNSIGNED_INT,
                             (void*)(sizeof(uint) * m_Entries[i].BaseIndex),
                             m_Entries[i].BaseVertex);
//    [_assimpShader toggleNormalcy];
    }


  }

  glBindVertexArray(0);
}

- (GLKMatrix4)modelMatrix {
  GLKMatrix4 modelMatrix = GLKMatrix4Identity;
  modelMatrix = GLKMatrix4Translate(modelMatrix, self.position.x, self.position.y, self.position.z);
  modelMatrix = GLKMatrix4Rotate(modelMatrix, self.rotationX, 1, 0, 0);
  modelMatrix = GLKMatrix4Rotate(modelMatrix, self.rotationY, 0, 1, 0);
  modelMatrix = GLKMatrix4Rotate(modelMatrix, self.rotationZ, 0, 0, 1);
  modelMatrix = GLKMatrix4Scale(modelMatrix, self.scale, self.scale, self.scale);
  return modelMatrix;
}

- (void)updateWithDelta:(NSTimeInterval)dt {
  switch ([[GLDirector sharedInstance] currentView]) {
    case ShowDots:
      self.rotationZ += M_PI * dt/2;
      break;
    case ShowWireFrame:
    case ShowColorDots:
    case ShowNormals:
      self.rotationZ += M_PI * dt/2;
      break;
    default:
      if (!strcmp(_name, "k9")){
        self.rotationZ = 0;
      } else {
        self.rotationZ = M_PI;
      }
      break;
  }
  for (id child in self.children) {
    if ([child respondsToSelector:@selector(updateWithDelta:)]) {
      [child updateWithDelta:dt];
    }
  }
}

@end
