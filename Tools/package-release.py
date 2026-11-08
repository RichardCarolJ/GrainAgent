#!/usr/bin/env python3
"""Create a self-contained, locally signed GrainAgent ZIP. Never uploads."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
import tempfile
import zipfile
from release_policy import verify_resources, verify_source

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {'.git', '.DS_Store', '__pycache__', 'build', 'dist', 'DerivedData',
            'xcuserdata', '.build', 'node_modules', 'backups', '.swiftpm'}
FILES = ['.gitignore', 'Product.json', 'LICENSE.txt', 'NOTICE.md', 'CITATION.cff',
         'DEVELOPMENT.md', 'docs/DISTRIBUTION.md', 'docs/SCREENSHOT-CREDITS.md',
         'engine/build.sh',
         'engine/tools/bake_resources.py', 'engine/third_party/README.md']
TREES = ['engine/include', 'engine/src', 'engine/resources', 'engine/resources_product',
         'engine/tests', 'engine/third_party/metal-cpp', 'license', 'BuildSupport', 'Tools',
         'modern_UI/Spektrafilm/Spektrafilm', 'modern_UI/Spektrafilm/SpektrafilmTests',
         'modern_UI/Spektrafilm/Tools', 'modern_UI/Spektrafilm/Spektrafilm.xcodeproj']

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def source_files():
    paths = [ROOT / name for name in FILES]
    for name in TREES:
        paths.extend(p for p in (ROOT/name).rglob('*') if p.is_file())
    for p in sorted(set(paths)):
        relative = p.relative_to(ROOT)
        if p.is_symlink() or any(part in EXCLUDED for part in relative.parts):
            continue
        if p.suffix.lower() in {'.p12', '.p8', '.pfx', '.mobileprovision'} or p.name.startswith('.env'):
            raise SystemExit('Private signing/configuration material in source: '+str(relative))
        verify_source(p, relative)
        yield p, relative.as_posix()

def run(*args):
    subprocess.run(args, check=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true', help='build before packaging')
    parser.add_argument('--guide', type=Path, default=ROOT/'docs/GrainAgent-Quick-Start.pdf',
                        help='approved PDF guide, supplied separately when packaging from the source ZIP')
    args = parser.parse_args()
    if not args.guide.is_file():
        parser.error('PDF guide not found; supply --guide with the official quick-start PDF')
    product = json.loads((ROOT/'Product.json').read_text())
    verify_resources()
    run('xcrun', 'swift', str(ROOT/'Tools/generate-app-icon.swift'), '--check')
    if args.build:
        run('python3', str(ROOT/'Tools/build-local.py'))
    app = ROOT/'build/GrainAgent.app'
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    for key, expected in [('CFBundleShortVersionString',product['version']),
                          ('CFBundleVersion',product['build']),('CFBundleIdentifier',product['bundle_id']),
                          ('LSMinimumSystemVersion',product['minimum_macos'])]:
        if info.get(key) != expected:
            raise SystemExit('App metadata is stale; build before packaging: '+key)
    record = json.loads((ROOT/'build/build.json').read_text())
    for relative, expected in record['compiled_inputs'].items():
        if digest(ROOT/relative) != expected:
            raise SystemExit('Compiled source changed; rebuild: '+relative)
    verify_resources(app/'Contents/Resources/Resources')
    if digest(app/'Contents/Resources/GrainAgent.icns') != digest(
            ROOT/'modern_UI/Spektrafilm/Spektrafilm/Resources/GrainAgent.icns'):
        raise SystemExit('Top-level application icon is stale; rebuild before packaging')
    expected_app_files = {'Contents/Info.plist', 'Contents/MacOS/GrainAgent',
                          'Contents/Resources/default.metallib', 'Contents/Resources/Assets.car',
                          'Contents/Resources/GrainAgent.icns', 'Contents/Resources/CorrespondingSource.zip',
                          'Contents/_CodeSignature/CodeResources'}
    expected_app_files.update('Contents/Resources/Resources/'+p.relative_to(app/'Contents/Resources/Resources').as_posix()
                              for p in (app/'Contents/Resources/Resources').rglob('*') if p.is_file())
    for path in app.rglob('*'):
        if path.is_symlink() or (path.is_file() and path.relative_to(app).as_posix() not in expected_app_files):
            raise SystemExit('Unexpected application payload: '+str(path.relative_to(app)))
    libraries = subprocess.check_output(['otool','-L',str(app/'Contents/MacOS/GrainAgent')],text=True)
    for line in libraries.splitlines()[1:]:
        dependency = line.strip().split(' (',1)[0]
        if not dependency.startswith(('/System/Library/','/usr/lib/')):
            raise SystemExit('Unexpected external runtime dependency: '+dependency)
    # An allowlisted source snapshot, not the encompassing private workspace.
    manifest = dict(product=product,upstream_commit='02d82b56cf65f0f8e802a708612edc4e9a4790af',files={})
    resources = app/'Contents/Resources'
    source_zip = resources/'CorrespondingSource.zip'
    prefix = f"GrainAgent-{product['version']}-build{product['build']}-source/"
    with zipfile.ZipFile(source_zip,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for path, relative in source_files():
            manifest['files'][relative] = digest(path)
            archive.write(path,prefix+relative)
        archive.writestr(prefix+'SOURCE-MANIFEST.json',json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    with zipfile.ZipFile(source_zip) as archive:
        if archive.testzip() is not None: raise SystemExit('Source archive failed integrity check')
    run('codesign','--force','--deep','--sign','-',str(app))
    run('codesign','--verify','--deep','--strict',str(app))
    # Signing after embedding corresponding source updates the executable's
    # signature. Keep its build record current for resources-only revisions.
    record['binary_sha256'] = digest(app/'Contents/MacOS/GrainAgent')
    (ROOT/'build/build.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    dist = ROOT/'dist'; dist.mkdir(exist_ok=True)
    stem = f"GrainAgent-{product['version']}-build{product['build']}-macOS-{product['architecture']}"
    output = dist/(stem+'.zip')
    with tempfile.TemporaryDirectory(prefix='grainagent-package-') as temp:
        staging = Path(temp)/stem; staging.mkdir()
        shutil.copytree(app,staging/'GrainAgent.app')
        shutil.copy2(args.guide,staging/'GrainAgent-Quick-Start.pdf')
        run('ditto','-c','-k','--norsrc','--noextattr','--noqtn','--keepParent',str(staging),str(output))
    public_source = dist/f"GrainAgent-{product['version']}-build{product['build']}-source.zip"
    shutil.copyfile(source_zip, public_source)
    checksum = digest(output)
    (dist/(stem+'.sha256')).write_text(checksum+'  '+output.name+'\n')
    (dist/(public_source.stem+'.sha256')).write_text(digest(public_source)+'  '+public_source.name+'\n')
    release = dict(product=product,signature='ad-hoc',notarized=False,published=False,
                   archive=output.name,archive_sha256=checksum,archive_bytes=output.stat().st_size,
                   binary_sha256=digest(app/'Contents/MacOS/GrainAgent'),
                   corresponding_source_sha256=digest(source_zip),source_files=len(manifest['files']),
                   corresponding_source_archive=public_source.name,
                   runtime_resource_files=verify_resources(app/'Contents/Resources/Resources'),
                   runtime_dependencies='macOS system libraries/frameworks only')
    (dist/'release.json').write_text(json.dumps(release,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(release,ensure_ascii=False,indent=2))

if __name__ == '__main__': main()
