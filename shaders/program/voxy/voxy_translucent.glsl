// Voxy LoD translucent terrain patch (water, stained glass, ...) for the
// Miniature shader.
//
// Produces the plain lit color that program/translucent.fsh blends towards
// near the edge of the vanilla terrain under #ifdef VOXY (the vanillaMix
// varying), so both sides of the boundary look the same: no water
// brightening, no screen-space reflections, just albedo, tint and lightmap
// ambient, with the same distance fog as the opaque patch.

#include "/program/voxy/voxy_common.glsl"

layout(location = 0) out vec4 colorOut;

void voxy_emitFragment(VoxyFragmentParameters parameters) {
   vec3 screenPos = vec3(gl_FragCoord.xy / vec2(viewWidth, viewHeight), gl_FragCoord.z);
   vec4 viewPos   = vxProjInv * vec4(screenPos * 2.0 - 1.0, 1.0);

   vec3 feetPos = view2feet(viewPos.xyz / viewPos.w);

   float fogMix = getFogMix(feetPos);

   if (fogMix > 0.999) {
      discard;
   }

   float sunHeight = view2feet(sunPosition).y;
   float skyLight  = clamp(parameters.lightMap.t, 0.0, 1.0);

   vec4 albedo  = parameters.sampledColour;
   vec4 color    = parameters.tinting;
   vec4 ambient  = getAmbientColor(skyLight, sunHeight);

   // as in the translucent vertex stage
   ambient.rgb *= color.a;
   color.a = 1.0;

   albedo *= color * ambient;

   albedo.rgb = mix(albedo.rgb, getFogColor(fogMix, feetPos), fogMix);

   colorOut = albedo;
}
