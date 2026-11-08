"""Release-only resource boundary: no photo library or unreviewed artwork."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
RESOURCE_ROOT = ROOT/'modern_UI/Spektrafilm/Spektrafilm/Resources'
POLICY = ROOT/'BuildSupport/ReleaseResources.json'
MEDIA = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.svg', '.icns', '.car',
         '.tif', '.tiff', '.heic', '.heif', '.avif', '.dng', '.arw', '.nef',
         '.cr2', '.cr3', '.raf', '.rw2', '.orf', '.pef', '.mp4', '.mov'}
PRIVATE_DIRS = {'Sidecars', 'Caches', 'Inputs', 'Relocated',
                'Test_image', 'PhotoLibrary', '__MACOSX', 'xcuserdata'}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def policy():
    return json.loads(POLICY.read_text())

def verify_resources(root=RESOURCE_ROOT):
    expected = policy()['runtime_files']
    files = {p.relative_to(root).as_posix():p for p in root.rglob('*') if p.is_file()}
    if set(files) != set(expected):
        raise SystemExit('Unreviewed/missing release resources: '+str(sorted(set(files)^set(expected))))
    for name,path in files.items():
        if path.is_symlink() or digest(path) != expected[name]:
            raise SystemExit('Release resource changed; review the inventory: '+name)
    return len(files)

def verify_source(path, relative):
    if any(x in PRIVATE_DIRS or x.startswith('._') for x in relative.parts):
        raise SystemExit('Personal/development data in source: '+str(relative))
    if path.name.endswith(('.spektra.json', '.grainagent.json')):
        raise SystemExit('Photo settings in source: '+str(relative))
    if path.suffix.lower() in {'.log', '.sqlite', '.sqlite3', '.db', '.sqlite-wal', '.sqlite-shm'}:
        raise SystemExit('Runtime logs/database in source: '+str(relative))
    if path.suffix.lower() in MEDIA:
        approved = policy()['source_visual_files']
        name = relative.as_posix()
        if name not in approved or digest(path) != approved[name]:
            raise SystemExit('Unreviewed image/media in source: '+name)
    # No old helper executable may ride along in the corresponding source.
    with path.open('rb') as f:
        magic = f.read(4)
    if magic in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe'):
        raise SystemExit('Unexpected executable in source: '+str(relative))
