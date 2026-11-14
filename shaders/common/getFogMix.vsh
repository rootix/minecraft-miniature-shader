uniform float fogEnd, fogStart;
uniform float near, far;

float calcFogMix(vec3 feetPos, float fogStartMult, float far) {
   float len = length(feetPos);
   float cylinderLen = max(length(feetPos.xz), abs(feetPos.y));

   #ifdef VOXY
      // On modern versions the vanilla fog start sits at zero, turning the
      // strength factor into a no-op for the fog itself, and the far plane
      // fade it would act on is pushed by Voxy beyond the visible world.
      // The overworld fog amount is therefore handled separately in
      // getFogMix() below; this only serves its remaining callers, which
      // all use full strength, keeping fog effects like blindness and the
      // non-overworld dimensions on the vanilla fade at fogEnd.
      float end = fogEnd * mix(VOXY_FOG_END_MIN, 1.0, fogStartMult);
   #else
      float end = fogEnd;
   #endif

   return max(
      rescale(len, fogStartMult * fogStart, end),
      rescale(cylinderLen, fogStartMult * (far - clamp(0.1 * far, 4.0, 64.0)), far)
   );
}

float getFogMix(vec3 feetPos) {
   // the vanilla far plane, kept before the VOXY override below shadows it;
   // only this value can tell whether a fog effect (like blindness) is
   // active, since Voxy always extends the far plane to its own render
   // distance
   float vanillaFar = far;

   #if defined VOXY && !defined GBUFFERS_SKYBASIC && !defined GBUFFERS_CLOUDS
      float far = 48000.0;
      float near = 16.0;
   #endif

   #ifndef ENABLE_FOG
      if (fogEnd >= vanillaFar) {
         return 0.0;
      }
   #endif

   #if MC_VERSION >= 11700
      if (fogEnd < vanillaFar) {
         // a fog effect (like blindness) is active
         return calcFogMix(feetPos, 1.0, far);
      }

      #if defined GBUFFERS_SKYBASIC
         return 0.0;
      #elif defined GBUFFERS_CLOUDS
         return clamp((length(feetPos) - far) * (near * 0.01), 0.0, 1.0);
      #else
         #ifdef OVERWORLD
            #ifdef VOXY
               // With Voxy the strength factor below has nothing to act on:
               // the far plane fade it scales sits beyond the visible world,
               // and on modern versions the vanilla fog start is zero. Turn
               // the overworld fog settings into a linear fog amount instead
               // (0 = no fog, 1 = maximum fog, one tenth per slider step).
               float amount    = 1.0 - OVERWORLD_FOG_MAX; // "Overworld fog", linear
               float transition = 1.0 - OVERWORLD_FOG_MIN; // "Overworld transition fog", linear

               // full weight from sunset through the night to sunrise,
               // falling to zero over the day (the vanilla curve is
               // 25 * distance-to-sunset/sunrise + 0.3, hence the 0.7)
               float t = worldTime * NORMALIZE_TIME;
               float weight = 1.0 - clamp(25.0 * (t < MIDNIGHT ? SUNSET - t : t - SUNRISE) / 0.7, 0.0, 1.0);

               // the transition setting amplifies the base amount around
               // sunset, sunrise and at night, in proportion to it
               amount *= 1.0 + transition * weight;

               // rain forces its own fog, like the vanilla weather fog
               amount = max(amount, rainStrength);

               if (amount < 0.0001) {
                  return 0.0;
               }

               // fade distance shrinks by a constant factor per step, so
               // every step of the sliders is equally visible; at maximum
               // fog the world fades at VOXY_FOG_END_MIN * fogEnd
               float minEnd = VOXY_FOG_END_MIN * fogEnd;
               float end = minEnd * pow(far / minEnd, 1.0 - amount);

               return rescale(length(feetPos), fogStart, end);
            #else
               float x = worldTime * NORMALIZE_TIME;

               x = clamp(25.0*(x < MIDNIGHT ? SUNSET - x : x - SUNRISE) + 0.3,
                        OVERWORLD_FOG_MIN,
                        OVERWORLD_FOG_MAX);

               x = min(x, 1.0 - rainStrength);

               return calcFogMix(feetPos, x, far);
            #endif
         #else
            return calcFogMix(feetPos, 1.0, far);
         #endif
      #endif
   #else
      gl_FogFragCoord = length(feetPos);

      return (isEyeInWater > 0) ? 1.0 - exp(-gl_FogFragCoord * gl_Fog.density)
                                : clamp((gl_FogFragCoord - gl_Fog.start) * gl_Fog.scale, 0.0, 1.0);
   #endif
}