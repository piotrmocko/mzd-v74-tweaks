"""Isolated dialog/installer tests; no real mounts, reboot or device files."""
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
SHELL = sys.argv[1] if len(sys.argv) > 1 else ('C:/Program Files/Git/bin/bash.exe' if os.name == 'nt' else '/bin/sh')

def bp(path):
    s = Path(path).resolve().as_posix()
    return '/' + s[0].lower() + s[2:] if len(s) > 1 and s[1] == ':' else s

def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8', newline='\n')
    path.chmod(0o755)

def md5(data):
    return hashlib.md5(data).hexdigest()

HASHES = ['e111883b9dcbeb6bb154521826fcacac', 'bb290d22840f82b1be14400ddb41f1b0',
          '1b69a54d01213cc7fbf1261ff4ab114d', 'bf24db1648049c7c29b46f2c3aeee8f0',
          '4134ff5877b799472ee8244300205a5c', 'a0947e23733735e2469775aa266ce41a',
          '0fb09cad9a062e0a2096da8487a29655', 'c02699ee8cf22def4393ff09c5a85f06']
variants = [(REPO / 'jci-org/List2Ctrl.js.org').read_bytes()] + [
    (REPO / f'jci-mods/List2Ctrl-{mask}.js').read_bytes() for mask in range(1, 8)]
assert [md5(data) for data in variants] == HASHES

checks = 0
with tempfile.TemporaryDirectory(prefix='mzd-navigation-') as folder:
    tmp = Path(folder)
    usb = tmp / 'USB stick'
    usb.mkdir()
    for d in ['jci-org', 'jci-mods']:
        shutil.copytree(REPO / d, usb / d)
    cmu, tools = tmp / 'jci', tmp / 'bin'
    tools.mkdir()
    answers, events = tmp / 'answers', tmp / 'events'
    write(tmp / 'mounts', f'mock {bp(usb)} vfat rw 0 0\n')
    write(tmp / 'gpio', '')
    write(tools / 'mount', '#!/bin/sh\nexit 0\n')
    for name in ['killall', 'hwclock', 'sync', 'reboot']:
        write(tools / name, f'#!/bin/sh\necho {name} >> "{bp(events)}"\n')
    write(cmu / 'tools/jci-dialog', f'''#!/bin/sh
case "$*" in
  *--3-button-dialog*) fallback=2 ;;
  *--question*) fallback=1 ;;
  *) exit 0 ;;
esac
set -- $(/bin/cat "{bp(answers)}")
a=${{1:-$fallback}}
[ "$#" -gt 0 ] && shift
printf '%s\\n' "$*" > "{bp(answers)}"
exit "$a"
''')
    write(tools / 'cat', f'''#!/bin/sh
case "$1" in
  *jci-mods/List2Ctrl-*)
    if [ -f "{bp(tmp / 'corrupt-copy')}" ]; then printf corrupt; exit 0; fi ;;
esac
exec /bin/cat "$@"
''')
    for script in ['list-tweaks.sh', 'main-menu-loop.sh', 'ssh.sh']:
        text = (REPO / script).read_text(encoding='utf-8')
        text = text.replace('#!/bin/sh\n', '#!/bin/sh\nPATH="' + bp(tools) + ':/usr/bin:/bin"\nexport PATH\n', 1)
        text = text.replace('/jci/', bp(cmu) + '/')
        text = text.replace('/proc/mounts', bp(tmp / 'mounts'))
        text = text.replace('/tmp/mnt/resources', bp(tmp / 'resources'))
        text = text.replace('/sys/class/gpio/Watchdog\\ Disable/value', bp(tmp / 'gpio'))
        write(usb / script, text)
        write(usb / (script + '.md5'), md5((usb / script).read_bytes()) + '  ' + script + '\n')
    env = dict(os.environ, PATH=bp(tools) + ':/usr/bin:/bin')
    write(cmu / 'version.ini', 'JCI_SW_VER="MAZ_CMU-150_74.00.324"\n')
    target = cmu / 'gui/common/controls/List2/js/List2Ctrl.js'
    backup = target.with_name(target.name + '.org')

    def run(script, reply, code=0):
        global checks
        write(answers, reply)
        write(events, '')
        result = subprocess.run([SHELL, bp(usb / script)], env=env, capture_output=True, timeout=20)
        assert result.returncode == code, result.stderr
        checks += 1
        return (usb / 'logs' / (script[:-3] + '.log')).read_text(encoding='utf-8')

    # Exercise every setting from every known state, including selective removal.
    for mask in range(8):
        for bit in range(3):
            for enable in [False, True]:
                write(target, '')
                target.write_bytes(variants[mask])
                if mask: backup.write_bytes(variants[0])
                elif backup.exists(): backup.unlink()
                wanted = mask | (1 << bit) if enable else mask & ~(1 << bit)
                reply = []
                for step in range(3):
                    reply += (['0' if enable else '1', '0'] if step == bit else ['2'])
                if wanted != mask: reply += ['1']  # Reboot later.
                run('list-tweaks.sh', ' '.join(reply))
                assert target.read_bytes() == variants[wanted], (mask, bit, enable)
                if wanted != 0: assert backup.read_bytes() == variants[0]
                assert 'reboot' not in events.read_text()
    target.write_bytes(variants[0] + b'// foreign change\n')
    before = target.read_bytes()
    assert 'not a known original' in run('list-tweaks.sh', '0 0 2 2')
    assert target.read_bytes() == before
    target.write_bytes(variants[7]); backup.unlink(missing_ok=True)
    assert 'backup is missing' in run('list-tweaks.sh', '1 0 2 2')
    assert target.read_bytes() == variants[7]
    backup.write_bytes(b'bad backup')
    assert 'not the known original' in run('list-tweaks.sh', '1 0 2 2')
    assert target.read_bytes() == variants[7]
    backup.write_bytes(variants[0]); target.write_bytes(variants[3])
    write(tmp / 'corrupt-copy', 'yes')
    assert 'previous settings were restored' in run('list-tweaks.sh', '2 2 0 0')
    assert target.read_bytes() == variants[3] and backup.read_bytes() == variants[0]
    (tmp / 'corrupt-copy').unlink()
    payload = usb / 'jci-mods/List2Ctrl-7.js'
    payload.write_bytes(b'damaged')
    assert 'missing or damaged' in run('list-tweaks.sh', '2 2 0 0')
    assert target.read_bytes() == variants[3]
    payload.write_bytes(variants[7])
    write(cmu / 'version.ini', 'JCI_SW_VER="MAZ_CMU-150_70.00.100"\n')
    assert 'CMU version: 70.00.100' in run('list-tweaks.sh', '', 1)
    assert target.read_bytes() == variants[3]
    write(cmu / 'version.ini', 'JCI_SW_VER="MAZ_CMU-150_74.00.324"\n')
    run('list-tweaks.sh', '2 2 2')
    assert target.read_bytes() == variants[3] and backup.read_bytes() == variants[0]
    menu = cmu / 'gui/apps/system/controls/MainMenu/js/MainMenuCtrl.js'
    menu.parent.mkdir(parents=True)
    original = (usb / 'jci-org/MainMenuCtrl.js.org').read_bytes()
    menu.write_bytes(original)
    run('main-menu-loop.sh', '0 1')
    assert md5(menu.read_bytes()) == 'ae272c9befc1350b93f23511568f13c7'
    run('main-menu-loop.sh', '1 1')
    assert menu.read_bytes() == original and not menu.with_name(menu.name + '.org').exists()
    menu.write_bytes(original + b'// foreign\n')
    assert 'not the known original' in run('main-menu-loop.sh', '0')
    assert menu.read_bytes() == original + b'// foreign\n'

    menu.with_name(menu.name + '.org').write_bytes(original)
    assert 'has other changes' in run('main-menu-loop.sh', '1')
    assert menu.read_bytes() == original + b'// foreign\n'

    # Exercise the native-style SSH installer with a stand-in supervisor.
    source = usb / 'services/ssh'
    shutil.copytree(REPO / 'services/ssh', source)
    mock_service = """#!/bin/sh
D=$(CDPATH= cd "$(dirname "$0")" && pwd)
case "$1" in
check) [ ! -f "FOREIGN" ] || { echo 'Port 22 is already in use'; exit 1; } ;;
boot) [ ! -f "FAIL_START" ] && [ -f "$D/enabled" ] && echo running > "$D/running" ;;
status) [ -f "$D/running" ] ;;
stop) rm -f "$D/running" ;;
*) exit 1 ;;
esac
""".replace('FOREIGN', bp(tmp / 'foreign-port')).replace('FAIL_START', bp(tmp / 'fail-start'))
    write(source / 'service.sh', mock_service)
    write(source / 'service.sh.md5', md5((source / 'service.sh').read_bytes()) + '  service.sh\n')
    stage = cmu / 'scripts/stage_wifi.sh'
    stage.parent.mkdir(parents=True)
    stage.write_bytes(b'#!/bin/sh\n\n')
    service = tmp / 'resources/mzd-v74-tweaks/ssh'
    def ssh_run(reply, code=0):
        global checks
        write(answers, reply); write(events, '')
        result = subprocess.run([SHELL, bp(usb / 'ssh.sh')], env=env, capture_output=True, timeout=20)
        assert result.returncode == code, result.stderr
        checks += 1
        return (usb / 'logs/ssh.log').read_text(encoding='utf-8')
    write(tmp / 'foreign-port', 'yes')
    assert 'Prerequisite check failed' in ssh_run('0', 1)
    assert stage.read_bytes() == b'#!/bin/sh\n\n' and not service.exists()
    (tmp / 'foreign-port').unlink()
    assert 'Enabled on port 22' in ssh_run('0 1')
    assert (service / 'enabled').exists() and b'service.sh boot' in stage.read_bytes()
    assert stage.with_name(stage.name + '.org').read_bytes() == b'#!/bin/sh\n\n'
    assert 'Enabled on port 22' in ssh_run('0 1')
    assert 'Uninstalled' in ssh_run('1 1')
    assert stage.read_bytes() == b'#!/bin/sh\n\n' and not service.exists()
    assert 'Not installed' in ssh_run('1')
    write(tmp / 'fail-start', 'yes')
    assert 'runtime changes were reverted' in ssh_run('0', 1)
    assert stage.read_bytes() == b'#!/bin/sh\n\n' and not (service / 'enabled').exists()
    (tmp / 'fail-start').unlink()
    assert 'Uninstalled' in ssh_run('1 1')
    stage.write_bytes(b'foreign startup script\n')
    assert 'not a known original' in ssh_run('0', 1)
    assert stage.read_bytes() == b'foreign startup script\n'
    stage.write_bytes(b'#!/bin/sh\n\n')
    stage.with_name(stage.name + '.org').write_bytes(b'bad backup')
    assert 'backup is not the known original' in ssh_run('0', 1)
    stage.with_name(stage.name + '.org').unlink()
    write(source / 'service.sh', mock_service + '# damaged\n')
    assert 'missing or damaged' in ssh_run('0', 1)
    assert not service.exists() and stage.read_bytes() == b'#!/bin/sh\n\n'

    # Reproduce each distributed payload from OEM and check the pinned device hashes.
    for mask in range(8):
        out = tmp / f'rebuilt-{mask}.js'
        subprocess.run([sys.executable, str(REPO / 'jci-patches/List2Ctrl-patch.py'),
                        str(REPO / 'jci-org/List2Ctrl.js.org'), str(out), str(mask)], check=True)
        assert out.read_bytes() == variants[mask]
    subprocess.run([sys.executable, str(REPO / 'jci-patches/MainMenuCtrl-patch.py'),
                    str(REPO / 'jci-org/MainMenuCtrl.js.org'), str(tmp / 'menu.js')], check=True)
    assert (tmp / 'menu.js').read_bytes() == (REPO / 'jci-mods/MainMenuCtrl.js').read_bytes()
print(f'Passed {checks} isolated navigation installer runs and all payload rebuilds.')
