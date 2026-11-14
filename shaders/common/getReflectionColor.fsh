#define SSR_BINARY_Z_CUTOFF 16.0

// How far a hit point reconstructed from the depth buffer may lie from the
// reflection ray to still count as an intersection: relative to the hit
// distance and in absolute blocks, respectively. Screen-space marching can
// report hits on surfaces the ray passes nowhere near (a balcony roof
// showing up in water in front of it, for example), because it only ever
// compares depths along the projected ray. A real intersection lies on the
// ray, and both the depth quantization and the refinement error grow with
// the hit distance, so the allowance has to grow with it as well. The
// absolute part has to stay small though: reflection rays that just graze
// past the silhouette of a nearby roof or fence line must not pick it up,
// even though their closest approach to its edge is only a fraction of a
// block.
#define SSR_HIT_SLOPE 0.05
#define SSR_HIT_BIAS 0.2

float getReflectionVignette(vec2 uv) {
   uv.y = min(uv.y, 1.0 - uv.y);
   uv.x *= 1.0 - uv.x;
   uv.y *= uv.y;

   return 1.0 - pow(1.0 - uv.x, 50.0*uv.y);
}

vec4 getReflectionColor(float depth, vec3 normal, vec3 viewPos, bool skyFallback) {
   vec3 V = normalize(viewPos);
   vec3 R = normalize(reflect(V, normal));
   float fresnel = 1.0 - dot(normal, -V);

   // Rays parallel to the screen leave it immediately; their reflection is
   // off-screen, so show plain water like the pack does for anything it
   // cannot source from the screen.
   if (R.z >= -0.05) return vec4(0.0);
   float grazingEpsilon = rescale(1.0 - abs(dot(R, normal)), 0.95, 1.0);
   float invR = 1.0 / abs(R.z);
   float invFar = 1.0 / (2.0*far);
   float lengthR = 1.0;
   vec3 oldPos = viewPos;

   // the most recent sky the ray passed: what a reflection that finds
   // nothing on screen should show
   vec2 skySampleUV = vec2(0.0);
   vec3 skySampleColor = vec3(0.0);
   bool sawSky = false;

   // where the ray was blocked by a surface it does not actually
   // intersect (first false hit): the true reflection continues behind
   // it, and the sky nearest to that spot is what blends best with the
   // reflections around it
   vec2 firstRejectUV = vec2(0.0);
   bool rejectedOnce = false;

   // whether the march ran off the screen: reflections sourced from
   // off-screen have no valid content, the pack's own vignette fades
   // edge-sourced reflections too, so show plain water for them
   bool leftScreen = false;

   for (int i = 0; i < SSR_MAX_STEPS; i++) {
      vec3 curPos = viewPos + R * lengthR;
      vec2 curUV  = view2screen(curPos).st;

      if (curUV.s < 0.0 || curUV.s > 1.0 || curUV.t < 0.0 || curUV.t > 1.0) {
         leftScreen = true;
         break;
      }

      float sceneDepth = texture2D(depthtex0, curUV).x;

      if (sceneDepth > 0.9999) {
         skySampleUV = curUV;
         skySampleColor = texture2D(colortex0, curUV).rgb;
         sawSky = true;
      }

      float sceneZ = screen2view(curUV, sceneDepth).z;
      float distanceEpsilon = clamp(abs(sceneZ) * invFar, 0.0, 1.0);
      float epsilon = 1.0 + 0.1*max(distanceEpsilon, grazingEpsilon);
      float diffZ = curPos.z - sceneZ * epsilon;

      if (diffZ < 0.0) {
         vec3 a = oldPos;
         vec3 b = curPos;

         if (diffZ > -SSR_BINARY_Z_CUTOFF) {
            for (int j = 0; j < SSR_BINARY_STEPS; j++) {
               curPos = (a + b) * 0.5;
               curUV = view2screen(curPos).st;
               sceneDepth = texture2D(depthtex0, curUV).x;

               if (sceneDepth > 0.9999) {
                  // the refinement often crosses the sky on its way to a
                  // silhouette edge; that sky is the best fallback content
                  skySampleUV = curUV;
                  skySampleColor = texture2D(colortex0, curUV).rgb;
                  sawSky = true;
               }

               sceneZ = screen2view(curUV, sceneDepth).z;

               if (-curPos.z < -sceneZ) { a = curPos; }
               else                     { b = curPos; }
            }
         }

         // Reject false hits. The ray can march behind surfaces that it
         // never intersects in 3D whenever its projection ends up inside
         // their screen silhouette, so require the reconstructed hit point
         // to lie close to the ray. The reflection ray only ever moves away
         // from the camera, so a real hit is always farther along the view
         // axis than the fragment itself; hits that are not (fences, deck
         // edges, anything between the camera and the water) are impossible
         // and get skipped.
         vec3 hitOffset = screen2view(curUV, sceneDepth) - viewPos;
         float hitDeviation = length(cross(hitOffset, R));
         bool onReflectionRay = hitOffset.z < 0.0
                              && hitDeviation < SSR_HIT_SLOPE*length(hitOffset) + SSR_HIT_BIAS;

         // Hits that the binary refinement converges onto the silhouette
         // edge of a surface (a roof eave or fence line against the sky)
         // are not intersections either: the ray only passed close by the
         // edge, which no distance tolerance can tell apart from a graze.
         // Such hits sit within a pixel or two of the sky, real face hits
         // do not.
         bool hitBesideSky = false;

         if (sceneDepth <= 0.9999) {
            vec2 px4 = vec2(4.0/viewWidth, 4.0/viewHeight);
            vec2 px8 = vec2(8.0/viewWidth, 8.0/viewHeight);
            hitBesideSky = texture2D(depthtex0, curUV + vec2( px4.x, 0.0)).x > 0.9999
                        || texture2D(depthtex0, curUV + vec2(-px4.x, 0.0)).x > 0.9999
                        || texture2D(depthtex0, curUV + vec2(0.0,  px4.y)).x > 0.9999
                        || texture2D(depthtex0, curUV + vec2(0.0, -px8.y)).x > 0.9999;
         }

         // Sky depth alone is not a valid hit either: a sample on the sky
         // side of a silhouette edge reads sky depth while its color is
         // the edge itself, which reflects the roof or fence into water
         // the ray never comes near. Only accept sky once the march
         // itself has left the world.
         bool rayLeftWorld = -curPos.z >= far;

         if ((onReflectionRay && !hitBesideSky) || (sceneDepth > 0.9999 && rayLeftWorld)) {
            return sceneDepth + 0.0001 <= depth
                  ? vec4(0.0)
                  : vec4(texture2D(colortex0, curUV).rgb,
                         getReflectionVignette(curUV) * fresnel);
         }

         if (!rejectedOnce) {
            firstRejectUV = curUV;
            rejectedOnce = true;
         }
      }

      oldPos = curPos;
      lengthR += max(SSR_STEP_SIZE * abs(diffZ) * invR, 1.0);
   }

   // Nothing was hit: the ray either left the screen or every candidate
   // crossing was a false hit, and the true reflection source -- usually
   // the sky above and behind an obstruction like a roof or fence -- is
   // off-screen. Without a fallback these pixels stay dark and read as a
   // phantom reflection of that obstruction. Show the sky nearest to the
   // obstruction instead: it is the same sky the neighbouring reflections
   // sample, at the same vignette-dimmed strength, so the filled area
   // blends into them instead of showing a seam.
   if (skyFallback && !leftScreen) {
      if (sawSky) {
         vec2 fillUV = skySampleUV;

         if (rejectedOnce) {
            // walk from the last sky the ray saw toward the surface that
            // blocked it (exponentially out, binary back), keeping the
            // sky pixel closest to that surface
            vec2 delta = firstRejectUV - skySampleUV;
            float t = 0.0;
            float step = 0.02;
            vec2 best = skySampleUV;

            for (int k = 0; k < 24; k++) {
               float nt = min(t + step, 1.0);
               vec2 probe = skySampleUV + delta*nt;

               if (texture2D(depthtex0, probe).x > 0.9999) {
                  best = probe;
                  t = nt;
                  step *= 2.0;
               } else {
                  step *= 0.5;
               }

               if (step < 0.001) break;
            }

            fillUV = best;
         }

         return vec4(texture2D(colortex0, fillUV).rgb,
                     fresnel * getReflectionVignette(fillUV));
      }

      // the ray never saw any sky: there is no trustworthy content for
      // these pixels, show plain water rather than an invented sky color
      return vec4(0.0);
   }

   return vec4(0.0);
}