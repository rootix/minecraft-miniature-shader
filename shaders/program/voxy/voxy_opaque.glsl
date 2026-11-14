// Voxy LoD opaque terrain patch for the Miniature shader.
//
// Mirrors program/textured_lit.fsh (the terrain program): lightmap ambient,
// directional sun/moon shading with the shadow map, torch light, glowing
// ores and the lava tint, followed by the same distance fog the vanilla
// programs apply under #ifdef VOXY. Everything the vanilla programs derive
// from vertex data is derived here from the Voxy fragment parameters
// instead (biome tint from tinting, block id from customId, light levels
// from lightMap and the face normal from face).

#include "/program/voxy/voxy_common.glsl"

// Version of common/getDiffuse.vsh for LoD geometry: the sun height and the
// thin-block flag replace its parameters, and the world-space face normal
// replaces mc_Entity and gl_Normal.

float getDiffuse(float sunHeight, bool isThin, vec3 viewNormal, float fogMix) {
   return (isEyeInWater == 0 ? 1.0 : 0.5)
        //  reduce with fog
        * (1.0 - fogMix)
        //  reduce with rain strength
        * (1.0 - rainStrength)
        //  thin objects have constant diffuse
        * (isThin ? 0.75 : clamp(2.5*dot(normalize(viewNormal),
                                         normalize(shadowLightPosition)), -0.3333, 1.0))
        // fade transition between night and day
        * clamp(0.1*abs(sunHeight) - 0.4453, 0.0, 1.0);
}

layout(location = 0) out vec4 colorOut;

void voxy_emitFragment(VoxyFragmentParameters parameters) {
   // Reconstruct the world-relative position of this fragment. Voxy undoes
   // its reverse-Z for the patch (gl_FragCoord.z is in vanilla depth
   // convention) and vxProjInv is the inverse of Voxy's own projection,
   // which reaches far beyond the vanilla far plane.
   vec3 screenPos = vec3(gl_FragCoord.xy / vec2(viewWidth, viewHeight), gl_FragCoord.z);
   vec4 viewPos   = vxProjInv * vec4(screenPos * 2.0 - 1.0, 1.0);

   vec3 feetPos = view2feet(viewPos.xyz / viewPos.w);

   // world-space face normal (from Cortex)
   vec3 normal = vec3(
                      uint((parameters.face >> 1) == 2),
                      uint((parameters.face >> 1) == 0),
                      uint((parameters.face >> 1) == 1)
                  )
       * (float(int(parameters.face) & 1) * 2.0 - 1.0);

   vec3 viewNormal = mat3(gbufferModelView) * normal;

   float sunHeight = view2feet(sunPosition).y;
   float skyLight  = clamp(parameters.lightMap.t, 0.0, 1.0);

   vec4 albedo = parameters.sampledColour;
   vec4 color  = parameters.tinting;

   // LoD terrain carries no vertex ambient occlusion data
   color.a = 1.0;

   // as in the terrain vertex stage; LoD terrain cannot use the
   // block emission attribute, so the block ids stand in
   float lightSourceLevel = float(parameters.customId == 10068u || parameters.customId == 10072u);

   // lava recolor, as done in the terrain vertex stage
   if (parameters.customId == 10068u) {
      color.rgb = mix(vec3(0.8, 0.5, 0.3), vec3(1.0), rescale(color.rgb, vec3(0.54), vec3(0.9)));
   }

   bool isThin = parameters.customId == 10031u || parameters.customId == 10059u
              || parameters.customId == 10175u || parameters.customId == 10176u
              || (abs(normal.y) < 0.01 && abs(abs(normal.x) - abs(normal.z)) < 0.01);

   #ifndef FLAT_LIGHTING
      // directional face shading, as done in the terrain vertex stage; the
      // LoD face normal is world-space already, like the transformed one
      vec3 lightNormal = isThin ? vec3(0.0, 1.0, 0.0) : normal;

      color.rgb *= clamp(lightNormal.x * lightNormal.x * 0.6
                       + lightNormal.y * lightNormal.y * 0.25 * (3.0 + lightNormal.y)
                       + lightNormal.z * lightNormal.z * 0.8, lightSourceLevel, 1.0);
   #endif

   float fogMix = getFogMix(feetPos);

   // light sources are less affected by fog, as done in the terrain vertex stage
   fogMix = mix(fogMix, fogMix*fogMix, lightSourceLevel);

   if (fogMix > 0.999) {
      discard;
   }

   vec4 ambient = getAmbientColor(skyLight, sunHeight);

   #ifdef THE_END
      ambient.rgb *= END_AMBIENT + 0.02*viewNormal;
   #endif

   #ifdef GLOWING_ORES
      float isOre = float(parameters.customId == 10014u);

      ambient.rgb = mix(
         ambient.rgb,
         vec3(1.0, 0.9, 0.9),
         isOre * 0.3333*squaredLength(rescale(albedo.rgb, vec3(0.59), vec3(1.0)))
      );
   #endif

   albedo *= color;

   float albedoLuma = luma(albedo.rgb);

   #ifdef ENABLE_SHADOWS
      // LoD sections are not rendered into the shadow map; the lookup below
      // still picks up shadows cast by vanilla geometry near the boundary
      float diffuse    = getDiffuse(sunHeight, isThin, viewNormal, fogMix);
      vec3  lightColor = getLightColor(sunHeight, skyLight);

      float lightStrength   = getLightStrength(diffuse, skyLight, feetPos);
      float lightBrightness = max(0.0, LIGHT_BRIGHTNESS - 0.5*pow3(albedoLuma));

      lightStrength = max(lightStrength, 0.75*lightSourceLevel);

      ambient.rgb *= mix(SHADOW_COLOR, vec3(1.0), lightStrength);
      ambient.rgb *= 0.75 + (lightBrightness * lightStrength) * lightColor;
   #endif

   ambient.rgb += getTorchColor(parameters.lightMap.s, ambient.rgb, feetPos);

   albedo *= ambient;

   #if defined THE_NETHER && defined NETHER_COLOR_GRADING
      albedo.rgb = mix(
         vec3(luma(albedo.rgb)),
         albedo.rgb,
         max(rescale(luma(ambient.rgb), 0.2, 0.6), rescale(albedoLuma, 0.15, 0.4))
      );
   #endif

   albedo.rgb = mix(albedo.rgb, getFogColor(fogMix, feetPos), fogMix);

   colorOut = albedo;
}
