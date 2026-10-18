# Shader reference

The Python modules compile and bind the active passes at runtime. Panda3D's
`p3d_*` values are engine-provided vertex/model data; `osl_*` values are set by
`OutdoorLighting.py`; `sky*` values are pushed by `ProceduralSky.py`.

| Files | Role | Runtime owner |
|---|---|---|
| `world_shadow.vert.glsl`, `world_shadow.frag.glsl` | Main outdoor receiver. The vertex stage emits world position, normal, UV, vertex color, and projected shadow coordinates. The fragment stage samples the caster map, applies filtered shadowing, outdoor light/ambient, texture and vertex color, and optional fog/contact/cel terms. | `_loadWorldShadowShader()` / `_applyWorldShaderState()` |
| `world_shadow_caster.vert.glsl`, `world_shadow_caster.frag.glsl` | Depth-only sun-shadow pass. The fragment stage preserves cutout transparency so foliage cards and sign art do not cast solid rectangles. | `_spawnLightRig()` and `_enableAllShadowCasters()` |
| `sky.vert.glsl`, `sky.frag.glsl` | Camera-following sky dome and atmospheric integration: Rayleigh/Mie scattering, clouds, stars, sun/moon discs, aurora, and twilight. | `ProceduralSky._loadSkyShader()` and `ProceduralSky.update()` |
| `water.vert.glsl`, `water.frag.glsl` | Planar water surface. Combines the reflected scene, water tint, Fresnel response, and animated surface detail. | `_setupWaterNode()` |
| `sunrays.vert.glsl`, `sunrays.frag.glsl` | Full-screen `render2dp` sun-shaft overlay. It synthesizes rays from projected sun position and fog data without sampling scene color/depth. | `_createGodRaysOverlay()` |
| `post.vert.glsl`, `scene_post.frag.glsl` | Full-screen scene composite used by the optional experimental RTT post path. Applies selected tonemapping and screen-space effects using the color/depth textures. | `_setupPostProcess()` when full post is enabled |
| `skybox.vert.glsl`, `skybox.frag.glsl` | Generic textured spherical skybox pair retained as a compatibility/example asset. It is not selected by the current procedural-sky runtime. | Not currently loaded |
| `terrain.vert.glsl`, `terrain.frag.glsl` | Generic Panda3D `ShaderTerrainMesh` sample pair, including chunk/heightfield inputs. Toontown's DNA terrain does not use `ShaderTerrainMesh`; these files are not loaded by this package. | Not currently loaded |

## Editing guidance

- Keep each vertex/fragment interface paired: varyings must match by name and
  type, and new uniforms must be supplied by the owning Python setup/update
  function before the draw call.
- Match the shader version to the existing pair and target Panda3D's supported
  OpenGL profile. A compile failure should leave the legacy path available.
- Avoid adding a full-scene copy pass for an effect that can be drawn as an
  overlay. The stable bloom and sun-rays paths are separated for this reason.
- Test receivers against textured DNA (texture + vertex color), alpha-cutout
  foliage, water, and both daytime and nighttime profiles; a plain test cube
  cannot reveal lost texture state or incorrect alpha handling.
