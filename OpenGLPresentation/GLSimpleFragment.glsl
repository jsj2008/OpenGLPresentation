#version 330 core

in vec4 frag_Color;
in vec2 frag_TexCoord;
in vec3 frag_Normal;
in vec3 frag_Position;

uniform sampler2D u_Texture;
uniform float u_MatSpecularIntensity;
uniform float u_Shininess;
uniform vec4 u_MatColor;

struct Light {
  vec3 Color;
  float AmbientIntensity;
  float DiffuseIntensity;
  vec3 Direction;
};
uniform Light u_Light;

out vec4 outputColor;

void main(void) {

  // Ambient
  vec3 AmbientColor = u_Light.Color * u_Light.AmbientIntensity;
  
  // Diffuse
  vec3 Normal = normalize(frag_Normal);
  float DiffuseFactor = max(-dot(Normal, u_Light.Direction), 0.0);
  vec3 DiffuseColor = u_Light.Color * u_Light.DiffuseIntensity * DiffuseFactor;

  // Specular
  vec3 Eye = normalize(frag_Position);
  vec3 Reflection = reflect(u_Light.Direction, Normal);
  float SpecularFactor = pow(max(0.0, -dot(Reflection, Eye)), u_Shininess);
  vec3 SpecularColor = u_Light.Color * u_MatSpecularIntensity * SpecularFactor;

  outputColor = u_MatColor * texture(u_Texture, frag_TexCoord) * vec4((AmbientColor + DiffuseColor + SpecularColor), 1.0);
}