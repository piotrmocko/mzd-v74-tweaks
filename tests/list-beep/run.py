"""Test one standalone tweak with isolated paths and commands."""
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

ID = 'list-beep'
REPO = Path(__file__).resolve().parents[2]
SHELL = 'C:/Program Files/Git/bin/bash.exe' if os.name == 'nt' else '/bin/sh'
EXPECTED = {'list-beep': 'bb290d22840f82b1be14400ddb41f1b0',
            'shorter-delay': '1b69a54d01213cc7fbf1261ff4ab114d',
            'list-loop': '4134ff5877b799472ee8244300205a5c',
            'main-menu-loop': 'ae272c9befc1350b93f23511568f13c7'}

def bp(path):
    value = Path(path).resolve().as_posix()
    return '/' + value[0].lower() + value[2:] if len(value) > 1 and value[1] == ':' else value

def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8', newline='\n')
    path.chmod(0o755)

def md5(data):
    return hashlib.md5(data).hexdigest()

source = (REPO / (ID + '.sh')).read_text(encoding='utf-8')
program = source.split("<<'TWEAK_PROGRAM_END'\n", 1)[1].split('\nTWEAK_PROGRAM_END', 1)[0]
original = Path(sys.argv[1]).read_bytes() if len(sys.argv) > 1 else Path(__file__).with_name('original.txt').read_bytes()
original_hash = md5(original)
checks = 0
with tempfile.TemporaryDirectory(prefix='mzd-' + ID + '-') as folder:
    tmp = Path(folder)
    awk = tmp / 'transform.awk'
    write(awk, program + '\n')

    def transform(action, data, success=True):
        global checks
        input_ = tmp / 'input.js'
        input_.write_bytes(data)
        command = 'awk -v action=' + shlex.quote(action) + ' -f ' + shlex.quote(bp(awk)) + ' ' + shlex.quote(bp(input_))
        result = subprocess.run([SHELL, '-c', command], capture_output=True, timeout=10)
        assert (result.returncode == 0) == success, result.stderr
        checks += 1
        return result.stdout

    assert transform('status', original) == b'uninstalled\n'
    installed = transform('install', original)
    if len(sys.argv) > 1:
        assert md5(installed) == EXPECTED[ID], 'Full OEM result differs from the previously verified AIO port.'
    else:
        assert installed == Path(__file__).with_name('installed.txt').read_bytes()
    assert transform('status', installed) == b'installed\n'
    assert transform('uninstall', installed) == original
    assert transform('install', installed) == installed
    assert transform('uninstall', original) == original
    transform('status', original + original, False)
    # Corrupt the guarded block inside its actual function, not a similar block elsewhere.
    old_block = [json.loads(match.group(1)) for match in re.finditer(r'^    block\[1,0,\d+\] = (.*)$', program, re.M)]
    new_block = [json.loads(match.group(1)) for match in re.finditer(r'^    block\[1,1,\d+\] = (.*)$', program, re.M)]
    changed = next(line.encode() for line in old_block if line.strip() and not line.strip().startswith('//'))
    old_bytes = ('\n'.join(old_block) + '\n').encode()
    scope = json.loads(re.search(r'^    scope\[1\] = (.*)$', program, re.M).group(1))
    begin = original.index(scope.encode()) if scope else 0
    at = original.index(old_bytes, begin)
    corrupted = old_bytes.replace(changed, changed + b' // unknown modification', 1)
    unknown = original[:at] + corrupted + original[at+len(old_bytes):]
    transform('status', unknown, False)
    if not re.search(r'hunks = 1\b', program):
        mixed = original[:at] + ('\n'.join(new_block) + '\n').encode() + original[at+len(old_bytes):]
        transform('status', mixed, False)
    prefix, suffix = b'// unrelated change before the tweak\n', b'// unrelated change after the tweak\n'
    foreign = prefix + original + suffix
    assert transform('install', foreign) == prefix + installed + suffix
    assert transform('uninstall', prefix + installed + suffix) == foreign

    usb, bins = tmp / 'USB stick', tmp / 'bin'
    usb.mkdir(); bins.mkdir()
    app, gpio, mounts = tmp / 'target.js', tmp / 'gpio', tmp / 'mounts'
    backup = app.with_name('target.js.org')
    write(gpio, '0\n')
    write(mounts, f'mock {bp(usb)} vfat rw 0 0\nroot / relfs ro 0 0\n')
    events = tmp / 'events'
    for name in ['sync', 'killall', 'reboot']:
        write(bins / name, '#!/bin/sh\nprintf "%s\\n" ' + name + ' >> ' + shlex.quote(bp(events)) + '\n')
    write(bins / 'mount', f'''#!/bin/sh
printf '%s\\n' "$*" >> '{bp(events)}'
if [ "$3" = / ]; then
  awk -v opt="$2" '$2=="/" {{$4=(opt=="rw,remount"?"rw":"ro")}} {{print}}' '{bp(mounts)}' > '{bp(tmp / 'mounts.new')}'
  mv '{bp(tmp / 'mounts.new')}' '{bp(mounts)}'
fi
''')
    write(bins / 'cat', f'''#!/bin/sh
case "$1" in
  */desired.js) if [ -f '{bp(tmp / 'fail-write')}' ]; then printf corrupt; exit 0; fi ;;
esac
exec /bin/cat "$@"
''')
    version = tmp / 'version.ini'
    write(version, 'JCI_SW_VER="MAZ_CMU-150_74.00.324"\n')
    isolated = source
    isolated = re.sub(r'^APP=.*$', 'APP=' + shlex.quote(bp(app)), isolated, flags=re.M)
    isolated = re.sub(r'^ORIGINAL=.*$', 'ORIGINAL=' + original_hash, isolated, flags=re.M)
    isolated = isolated.replace('/jci/version.ini', bp(version)).replace('/proc/mounts', bp(mounts))
    isolated = isolated.replace('/sys/class/gpio/Watchdog\\ Disable/value', bp(gpio))
    isolated = isolated.replace('LOCK=/tmp/mzd-List2Ctrl-tweak.lock', 'LOCK=' + shlex.quote(bp(tmp / 'lock')))
    isolated = isolated.replace('#!/bin/sh\n', '#!/bin/sh\nPATH=' + shlex.quote(bp(bins) + ':/usr/bin:/bin') + '\nexport PATH\n', 1)
    script = usb / (ID + '.sh')
    write(script, isolated)
    checksum = script.with_name(script.name + '.md5')
    write(checksum, md5(script.read_bytes()) + '  ' + script.name + '\n')
    app.write_bytes(original)

    def run(action, code=0, text=''):
        global checks
        result = subprocess.run([SHELL, bp(script), action], capture_output=True, timeout=20)
        assert result.returncode == code, result.stdout + result.stderr
        assert text.encode() in result.stdout + result.stderr
        assert gpio.read_text().strip() == '0'
        assert 'root / relfs ro ' in mounts.read_text()
        assert not (tmp / 'lock').exists()
        checks += 1

    run('status', text='uninstalled')
    assert not events.exists(), 'Status must not remount storage or call sync.'
    assert not (usb / 'logs').exists(), 'Status must not write USB reports.'

    run('install', text='install completed')
    assert app.read_bytes() == installed and backup.read_bytes() == original
    saved = backup.stat().st_mtime_ns
    run('install', text='already present')
    assert backup.stat().st_mtime_ns == saved
    app.write_bytes(prefix + installed + suffix)
    run('uninstall', text='uninstall completed')
    assert app.read_bytes() == foreign and backup.read_bytes() == original
    run('install')
    assert app.read_bytes() == prefix + installed + suffix
    run('restore')
    assert app.read_bytes() == foreign
    backup.write_bytes(b'corrupt backup')
    run('install', 1, 'not the known OEM original')
    assert app.read_bytes() == foreign
    backup.unlink()
    run('install', 1, 'backup is missing')
    assert app.read_bytes() == foreign
    backup.write_bytes(original)
    app.write_bytes(unknown)
    run('install', 1, 'Unknown or partially modified')
    assert app.read_bytes() == unknown
    app.write_bytes(foreign)
    write(tmp / 'fail-write', 'yes')
    run('install', 1, 'previous file was restored')
    assert app.read_bytes() == foreign and backup.read_bytes() == original
    (tmp / 'fail-write').unlink()
    write(version, 'JCI_SW_VER="MAZ_CMU-150_70.00.100"\n')
    run('install', 1, 'requires firmware')
    assert app.read_bytes() == foreign
    write(version, 'JCI_SW_VER="MAZ_CMU-150_74.00.324"\n')
    write(script, isolated + '# damaged\n')
    run('install', 1, 'checksum mismatch')
    assert app.read_bytes() == foreign
    assert 'reboot' not in events.read_text()
print(f'{ID}: passed {checks} transform and isolated installer checks' + (' against the complete OEM file.' if len(sys.argv) > 1 else ' against OEM excerpts.'))
