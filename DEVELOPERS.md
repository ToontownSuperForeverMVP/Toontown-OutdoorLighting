# Developer guide

This package is a render subsystem for Panda3D Toontown sources. It does not
load a hood or create a `Playground`; the host client supplies the active
geometry and owns the zone lifecycle. The package changes Panda render state
while that geometry is active, then restores the saved state when the last
caller exits.

## Runtime lifecycle

1. Import `toontown.hood.OutdoorLighting` after the game's Python package is
   available. Importing early is supported; the module resolves `base` again
   when the lifecycle starts.
2. In the outdoor zone's enter hook, call
   `OutdoorLighting.begin(geom, hoodId=hoodId, zoneId=zoneId)`. `geom` is the
   loaded outdoor `NodePath`, after it is reparented under `render`.
3. `begin()` resolves the profile, registers the owner, captures mutable Panda
   state, creates the shared light rig, and starts the update task. Shader,
   post, water, and procedural-sky work are gated by config and renderer
   capability checks.
4. If the zone streams in additional outdoor nodes, call
   `shadeExtraSubtree(node)` after attaching them. Call
   `clearExtraSubtree(node)` before removing them so their previous shader and
   texture state is restored.
5. In the matching exit hook, call `OutdoorLighting.end(geom)` with the same
   geometry root. Multiple callers can share the rig; only the final `end()`
   tears down global tasks, lights, filters, water, fog, and sky and restores
   the states captured on entry.

Example hooks:

```python
def enter(self, requestStatus):
    self.loader.geom.reparentTo(render)
    from toontown.hood import OutdoorLighting
    OutdoorLighting.begin(
        self.loader.geom,
        hoodId=getattr(self.loader.hood, 'id', None),
        zoneId=requestStatus.get('zoneId'),
    )

def exit(self):
    from toontown.hood import OutdoorLighting
    OutdoorLighting.end(self.loader.geom)
    self.loader.geom.reparentTo(hidden)
```

Keep calls in `try/except` in game hooks so an optional graphics feature cannot
strand the player during a zone transition. Log failures through the source's
normal notify category; do not swallow them silently during development.

## Configuration lookup

`LightingConfig.py` registers typed Panda3D `ConfigVariable`s and optionally
reads `base.settings`. For each registered key, lookup order is:

1. An explicit PRC/command-line value (`has_value()` distinguishes it from the
   registered default).
2. The game's settings provider, if one is available.
3. The typed default registered in `LightingConfig.py`.

This lets game options control defaults while allowing a developer's
`Config.prc` to force a value. `describe(name)` supplies the intent text shown
by PRC introspection. Add new settings to the registration tables rather than
creating a one-off variable in a render path.

## Profiles and time

`OutdoorLighting.py` resolves `zoneId` before `hoodId`, then falls back to the
requested style. Zone/hood overrides can be registered at runtime with
`registerZoneProfile()` and `registerHoodProfile()`, or supplied as repeatable
PRC profile-map entries. A profile contains lighting colors/directions,
fog/sky values, feature gates, and optional keyframes. `_evalKeyframes()`
interpolates those values; `setTimeOfDay(hours)` is intended for deterministic
capture/debugging and normal gameplay advances through the update task.

## Render passes and state ownership

- **Light rig:** `_spawnLightRig()` creates ambient and directional lights and,
  when enabled and supported, allocates the sun shadow camera/buffer.
- **World receiver/caster shaders:** the receiver samples the shadow map and
  combines texture, vertex color, world lighting, fog, and contact detail. The
  caster writes depth and alpha-tests cutout textures such as foliage.
- **Street lamps:** lamp nodes are discovered from cached transforms or scene
  names. Point lights and projected ground pools are updated from the night
  factor and profile; flattened DNA fixtures need transform caching before
  flattening if a source wants per-lamp placement.
- **Atmosphere:** `ProceduralSky.py` creates a camera-following dome and pushes
  sky uniforms; `SkyUtil.py` retains the legacy model-sky cloud animation.
- **Water:** matching water nodes receive reflection targets and shader inputs;
  cleanup removes buffers and restores their original render state.
- **Post effects:** stable bloom uses Panda's `CommonFilters`; sun rays use a
  `render2dp` quad. The optional full-scene RTT compositor is separately
  gated because render-to-texture support and viewport behavior vary by driver.

Every optional feature should have three pieces: a configuration/capability
gate, a setup path that can fail without stopping zone entry, and a cleanup
path that restores exactly what it changed. Avoid replacing complete
`LightAttrib` or texture state when a narrower clear/restore operation will do.

## Shader files

The runtime shader loader lives in `OutdoorLighting.py`; procedural-sky GLSL is
loaded by `ProceduralSky.py`. `shaders/README.md` documents each pair, its
uniform contract, and whether the active runtime loads it. Some bundled files
are standalone Panda3D examples or compatibility assets rather than active
OutdoorLighting passes; the inventory marks those explicitly.

## Capture harness

`capture_playground.py` is a source-checkout visual harness. It loads the TTC
DNA storage tables, fonts, safe-zone DNA, and neighborhood ground model, then
activates the real lighting module in an onscreen Panda3D window. It registers
the `ground` and `shadow` cull bins used by the live client before model load.
It bypasses login/avatar setup and is useful for shader iteration, not proof of
full-client HUD, avatar, or gameplay behavior.

## Porting notes

Use `Install-OutdoorLighting.ps1` for a checkout with the conventional
`toontown/hood`, `toontown/safezone`, and `toontown/shaders` layout. Review the
resulting hook diff for that source before launching it: upstream revisions can
move geometry reparent calls or alter hook signatures. The installer backs up
overwritten files under `.outdoorlighting-backup-*` when `-Force` is used.

The target repository's root `LICENSE` is MIT. The copied source stack also
retains the original permissive source notice in `THIRD_PARTY_NOTICES.md`; keep
both notices with the files when redistributing this extraction.
