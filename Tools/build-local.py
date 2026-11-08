#!/usr/bin/env python3
"""Build GrainAgent with Command Line Tools, from this checkout only.

The C++ engine is compiled unchanged. The checked, precompiled Metal libraries
preserve the existing imaging pipeline when the offline Metal compiler is not
installed. Full Xcode builds remain available through the generated project.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
import time
from release_policy import verify_resources

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'modern_UI/Spektrafilm/Spektrafilm'
PRECOMPILED = ROOT / 'BuildSupport/Precompiled'
PRODUCT = json.loads((ROOT/'Product.json').read_text())
MACOS_MIN = PRODUCT['minimum_macos']
BUILD_TARGET = f'arm64-apple-macosx{MACOS_MIN}'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--resources-only', action='store_true',
                        help='reuse the verified executable when only metadata/resources changed')
    args = parser.parse_args()
    started = time.time()
    verify_resources()
    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    # Fail rather than silently building with a changed compiled resource.
    for name, expected in json.loads((PRECOMPILED/'manifest.json').read_text()).items():
        if digest(PRECOMPILED/name) != expected:
            raise SystemExit('Precompiled resource checksum mismatch: ' + name)
    subprocess.run(['sh', str(ROOT/'modern_UI/Spektrafilm/Tools/check-bundle-resources.sh')],check=True)
    engine = ROOT / 'engine'
    sources = sorted(p for d in ('core','gpu','pipeline') for p in (engine/'src'/d).glob('*.cpp')
                     if p.name not in ('vulkan_gpu.cpp','windows_unported.cpp'))
    objects = build / 'engine'; objects.mkdir(exist_ok=True)
    headers = sorted(p for d in ('include','src','third_party/metal-cpp') for p in (engine/d).rglob('*') if p.suffix in ('.h','.hpp'))
    signature = hashlib.sha256(b''.join(p.read_bytes() for p in headers)).hexdigest()
    def compile_engine(path):
        obj = objects / (path.stem+'.o')
        stamp = obj.with_suffix('.sha256')
        key = digest(path)+signature+BUILD_TARGET
        if obj.exists() and stamp.exists() and stamp.read_text()==key:
            return obj
        command = ['xcrun','clang++','-std=c++20','-O2','-arch','arm64',f'-mmacos-version-min={MACOS_MIN}']
        command += ['-I'+str(engine/d) for d in ('include','src','src/core','third_party/metal-cpp')]
        command += ['-c',str(path),'-o',str(obj)]
        result = subprocess.run(command,capture_output=True,text=True)
        if result.returncode: raise RuntimeError(result.stderr)
        stamp.write_text(key)
        return obj
    with ThreadPoolExecutor(max_workers=4) as pool:
        linked = list(pool.map(compile_engine,sources))
    app = build / 'GrainAgent.app'
    staging = build / 'GrainAgent.staging.app'
    if staging.exists(): shutil.rmtree(staging)
    contents = staging / 'Contents'
    binary = contents / 'MacOS/GrainAgent'; binary.parent.mkdir(parents=True)
    resources = contents / 'Resources'; resources.mkdir()
    shutil.copytree(SOURCE/'Resources', resources/'Resources')
    for name in ('default.metallib','Assets.car'): shutil.copy2(PRECOMPILED/name,resources/name)
    shutil.copy2(SOURCE/'Resources/GrainAgent.icns',resources/'GrainAgent.icns')
    inputs = sorted(SOURCE.rglob('*.swift'))
    compiled = inputs + sources + headers
    if args.resources_only:
        previous = json.loads((build/'build.json').read_text())
        if previous.get('build_target') != BUILD_TARGET:
            raise SystemExit('Deployment target changed; a full build is required')
        current_inputs = {str(p.relative_to(ROOT)):digest(p) for p in compiled}
        if current_inputs != previous['compiled_inputs']:
            raise SystemExit('Executable inputs changed; a full build is required')
        if previous['optimization'] != ('debug' if args.debug else 'release'):
            raise SystemExit('Optimization changed; a full build is required')
        if digest(app/'Contents/MacOS/GrainAgent') != previous['binary_sha256']:
            raise SystemExit('Existing executable does not match its build record')
        shutil.copy2(app/'Contents/MacOS/GrainAgent', binary)
    command = ['xcrun','swiftc','-module-name','Spektrafilm','-parse-as-library','-swift-version','6',
               '-strict-concurrency=complete','-target',BUILD_TARGET,'-I',str(engine/'include'),
               '-import-objc-header',str(SOURCE/'Service/Spektrafilm-Bridging-Header.h'),
               '-whole-module-optimization','-Onone' if args.debug else '-O']
    command += [str(p) for p in inputs+linked]+['-lc++','-lsqlite3']
    for framework in ('Metal','Foundation','QuartzCore','CoreText','CoreGraphics','Accelerate','SwiftUI','AppKit'):
        command += ['-framework',framework]
    command += ['-o',str(binary)]
    if not args.resources_only:
        with (build/'build.log').open('w') as log:
            result = subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
        if result.returncode:
            print((build/'build.log').read_text()[-14000:])
            raise SystemExit(result.returncode)
    info = plistlib.loads((SOURCE/'Info.plist').read_bytes())
    info.update(CFBundleExecutable='GrainAgent',CFBundleName='GrainAgent',CFBundleDisplayName='GrainAgent',
                CFBundleIdentifier=PRODUCT['bundle_id'],CFBundleShortVersionString=PRODUCT['version'],
                CFBundleVersion=PRODUCT['build'],CFBundleIconFile='GrainAgent.icns',LSMinimumSystemVersion=PRODUCT['minimum_macos'],
                GrainAgentMaintainer=PRODUCT['maintainer'],GrainAgentRepository=PRODUCT['repository'],
                GrainAgentReleaseTagPrefix=PRODUCT['release_tag_prefix'],
                GrainAgentPublicReleaseChannel=PRODUCT['public_release_channel'])
    info['NSHumanReadableCopyright'] = info['NSHumanReadableCopyright'].replace('$(GRAINAGENT_MAINTAINER)',PRODUCT['maintainer'])
    info.pop('CFBundleIconName',None)
    (contents/'Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign','--force','--deep','--sign','-',str(staging)],check=True,capture_output=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(staging)],check=True,capture_output=True)
    if app.exists(): shutil.rmtree(app)
    staging.rename(app)
    record = dict(bundle=str(app),source=str(ROOT),version=PRODUCT['version'],build=PRODUCT['build'],
                  bundle_id=PRODUCT['bundle_id'],build_target=BUILD_TARGET,swift_files=len(inputs),engine_files=len(linked),
                  optimization='debug' if args.debug else 'release',elapsed_seconds=round(time.time()-started,1),
                  binary_sha256=digest(app/'Contents/MacOS/GrainAgent'),
                  compiled_inputs={str(p.relative_to(ROOT)):digest(p) for p in compiled},
                  executable_reused=args.resources_only,
                  shaders='Pinned verified Metal libraries; offline compiler not required')
    (build/'build.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in record.items() if k != "compiled_inputs"},ensure_ascii=False,indent=2))

if __name__ == '__main__': main()
