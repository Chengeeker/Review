"""Package checks only; no device, account or playback acceptance implied."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import zipfile

root = Path(__file__).resolve().parent.parent
apk = root / 'app/build/outputs/apk/release/app-release.apk'
sdk_home = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
if not sdk_home:
    raise SystemExit('Set ANDROID_HOME to the Android SDK directory')
sdk = Path(sdk_home)
tools = sdk / 'build-tools/37.0.0'
exe_suffix = '.exe' if os.name == 'nt' else ''
java_home = os.environ.get('JAVA_HOME')
java = Path(java_home) / 'bin' / f'java{exe_suffix}' if java_home else shutil.which('java')
if java is None:
    raise SystemExit('Set JAVA_HOME or add java to PATH')
aapt = tools / f'aapt2{exe_suffix}'

def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True, encoding='utf-8', errors='replace').stdout

config = (root / 'app/build.gradle.kts').read_text(encoding='utf-8')
package = 'com.review'
name = re.search(r'versionName = "([^"]+)"', config)[1]
code = re.search(r'versionCode = (\d+)', config)[1]
badging = run(aapt, 'dump', 'badging', apk)
assert f"name='{package}' versionCode='{code}' versionName='{name}'" in badging
assert "application-label:'Review'" in badging
assert int(code) > 266, 'Release versionCode must upgrade the last preview APK'
manifest = run(aapt, 'dump', 'xmltree', apk, '--file', 'AndroidManifest.xml')
for suffix in ('MainActivity', 'MainActivityAlias1', 'MainActivityAlias2', 'documents'):
    assert f'="{package}.{suffix}"' in manifest, suffix
assert "minSdkVersion:'26'" in badging or "sdkVersion:'26'" in badging
assert 'application-debuggable' not in badging
signature = run(java, '-jar', tools / 'lib/apksigner.jar', 'verify', '--verbose', '--print-certs', apk)
certificate = '3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975'
digests = re.findall(r'certificate SHA-256 digest: ([0-9a-f]{64})', signature)
assert digests and set(digests) == {certificate}
assert 'Number of signers: 1' in signature
assert 'Verified using v2 scheme (APK Signature Scheme v2): true' in signature
run(tools / f'zipalign{exe_suffix}', '-c', '-P', '16', '4', apk)
libraries = []
with zipfile.ZipFile(apk) as archive:
    assert archive.testzip() is None, 'APK ZIP integrity check failed'
    signing_config = archive.read('assets/cfg.json')
    assert hashlib.sha256(signing_config).hexdigest() == '0ffeaffc2282b815d23d18b495c28cbb10d45ab2ec1d8e990fd840fb24ffdfb4'
    for path in archive.namelist():
        assert not path.lower().endswith(('.bks', '.jks', '.p12', 'key.properties'))
        assert 'flutter_assets/' not in path and not path.endswith(('libflutter.so', 'libapp.so'))
        if not path.endswith('.so'):
            continue
        if path in ('assets/libbb.so', 'assets/libshare.so'):
            # Retained authentication signatures use .so names but contain DER data, not ELF code.
            data = archive.read(path)
            assert data.startswith(b'\x30\x82')
            assert data == (root / 'app/src/main' / path).read_bytes()
            continue
        assert path.startswith('lib/arm64-v8a/'), path
        data = archive.read(path)
        assert data[:6] == b'\x7fELF\x02\x01' and struct.unpack_from('<H', data, 18)[0] == 183
        offset = struct.unpack_from('<Q', data, 32)[0]
        size, count = struct.unpack_from('<HH', data, 54)
        alignments = [struct.unpack_from('<Q', data, offset + i * size + 48)[0] for i in range(count) if struct.unpack_from('<I', data, offset + i * size)[0] == 1]
        assert alignments and min(alignments) >= 16384, path
        libraries.append(path)
assert libraries, 'No ARM64 libraries in release'
report = dict(package=package, versionName=name, versionCode=int(code), minSdk=26,
              bytes=apk.stat().st_size, sha256=hashlib.sha256(apk.read_bytes()).hexdigest(),
              signerSha256=certificate, libraries=libraries, flutterRuntime=False,
              v2Signature=True, zip16KiBAligned=True, elf16KiBAligned=True)
(root / 'build/release-verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
