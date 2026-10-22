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
    for script in ['ssh.sh']:
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

print(f'Passed {checks} isolated SSH installer runs.')
