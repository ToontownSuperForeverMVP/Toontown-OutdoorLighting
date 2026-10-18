"""Capture the real Toontown Central playground with OutdoorLighting enabled.

Run from the repository root with its bundled Panda3D interpreter:
    Panda3D/python/ppython.exe OutdoorLighting/capture_playground.py

This is a scene-loading harness, not a replacement client. It builds the same
DNA storage used by TTC, loads the safe-zone DNA plus its neighborhood ground,
initializes the standard client cull bins, and activates the real OutdoorLighting
module. Login, avatar setup, and networking are intentionally skipped. Each time
sample is rendered to the onscreen Panda window and saved as a PNG.
"""

from __future__ import annotations

import sys
from pathlib import Path

from panda3d.core import (
    CSDefault,
    CullBinManager,
    Filename,
    NodePath,
    PNMImage,
    VirtualFileSystem,
    loadPrcFile,
    loadPrcFileData,
)
from panda3d.toontown import DNAStorage, loadDNAFile


ROOT = Path.cwd()
OUTPUT = Path(__file__).resolve().parent / 'screenshots'
# Add the game checkout first so imports resolve to its normal toontown package.
sys.path.insert(0, str(ROOT))

loadPrcFile('config/common.prc')
loadPrcFile('config/development.prc')
loadPrcFileData('', 'window-title Toontown Central - OutdoorLighting Capture')
loadPrcFileData('', 'win-size 1280 720')
loadPrcFileData('', 'audio-library-name null')
loadPrcFileData('', 'show-frame-rate-meter false')

# The source checkout uses loose phase directories. Mount the repository's
# resource root just as the normal client does, without requiring a login.
VirtualFileSystem.getGlobalPtr().mount(
    Filename.fromOsSpecific(str(ROOT / 'resources')),
    Filename('/'),
    0,
)

from direct.showbase.ShowBase import ShowBase
from toontown.toonbase import TTLocalizer
from toontown.hood import OutdoorLighting


base = ShowBase()
base.disableMouse()

# Match the cull-bin order configured by the live client before BAM/DNA load.
# TTC ground meshes use the named ``ground`` bin; the lighting system also uses
# ``shadow``. Registering them before any model is loaded preserves the same
# fixed draw order as ToonBase.addCullBins() in a full client.
cullBinMgr = CullBinManager.getGlobalPtr()
cullBinMgr.addBin('shadow', CullBinManager.BTFixed, 15)
cullBinMgr.addBin('ground', CullBinManager.BTFixed, 14)

dnaStore = DNAStorage()
# Storage DNA maps symbolic codes in TTC's playground DNA to BAM models, signs,
# fonts, and props. Load the same shared and TTC-specific tables as the hood.
for storageFile in (
    'phase_4/dna/storage.dna',
    'phase_3.5/dna/storage_interior.dna',
    'phase_4/dna/storage_TT.dna',
    'phase_4/dna/storage_TT_sz.dna',
):
    loadDNAFile(dnaStore, storageFile, CSDefault, 0)

dnaStore.storeFont('humanist', loader.loadFont(TTLocalizer.InterfaceFont))
dnaStore.storeFont('mickey', loader.loadFont(TTLocalizer.SignFont))
dnaStore.storeFont('suit', loader.loadFont(TTLocalizer.SuitFont))

# Parse the zone layout only after all referenced codes and fonts are available.
playground = loadDNAFile(
    dnaStore,
    'phase_4/dna/toontown_central_sz.dna',
    CSDefault,
    0,
)
if playground is None:
    raise RuntimeError('Could not load Toontown Central playground DNA.')

if playground.getNumParents() == 1:
    geom = NodePath(playground.getParent(0))
else:
    geom = NodePath(playground)
sceneRoot = render.attachNewNode('ToontownCentralCaptureScene')
# Keep the DNA and neighborhood model under one neutral root so their authored
# world coordinates line up without applying a second transform.
geom.reparentTo(sceneRoot)
geom.setName('liveToontownCentralPlayground')

# The TTC safe-zone DNA contains props and buildings; its continuous plaza
# ground/background lives in the separate neighborhood model.
ttcGround = loader.loadModel('phase_4/models/neighborhoods/toontown_central')
if ttcGround.isEmpty():
    raise RuntimeError('Could not load the Toontown Central neighborhood ground model.')
ttcGround.reparentTo(sceneRoot)
geom.flattenMedium()

# Activate lighting against the playable DNA geometry. The neighborhood ground
# remains a separate sibling under sceneRoot, matching the way the hood owns its
# background geometry and preventing a receiver shader from replacing its maps.
OutdoorLighting.begin(geom, hoodId=2000, zoneId=2000)

# Place the camera on the playable ground beside TTC's fountain and aim
# northward into the central plaza. This keeps the shot inside the map.
base.camera.setPos(100, -142, 9)
base.camera.lookAt(80, -70, 7)

OUTPUT.mkdir(parents=True, exist_ok=True)
# Re-render several times after each time change so Panda's task/shader updates
# settle before grabbing the current framebuffer.
for label, hour in (
    ('toontown-central-day', 15.0),
    ('toontown-central-golden-hour', 17.0),
    ('toontown-central-twilight', 18.8),
    ('toontown-central-night', 0.0),
):
    OutdoorLighting.setTimeOfDay(hour)
    for _ in range(8):
        base.graphicsEngine.renderFrame()
    screenshot = PNMImage()
    if not base.win.getScreenshot(screenshot):
        raise RuntimeError(f'Panda3D could not capture the {label} frame.')
    destination = OUTPUT / f'{label}.png'
    if not screenshot.write(Filename.fromOsSpecific(str(destination))):
        raise RuntimeError(f'Could not write screenshot: {destination}')
    print(f'Captured {destination} ({screenshot.getXSize()}x{screenshot.getYSize()})')

OutdoorLighting.end(geom)
base.destroy()
