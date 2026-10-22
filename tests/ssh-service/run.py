"""Run the real SSH supervisor with fake kernel/network/sshd commands only."""
import argparse
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--bash', default='C:/Program Files/Git/bin/bash.exe' if os.name == 'nt' else '/bin/sh')
args = p.parse_args()
root = Path(__file__).resolve().parents[2]
def bp(path):
    s = Path(path).resolve().as_posix()
    return '/' + s[0].lower() + s[2:] if len(s) > 1 and s[1] == ':' else s
def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8', newline='\n')

with tempfile.TemporaryDirectory(prefix='mzd-ssh-test-') as temporary:
    temp = Path(temporary)
    service = temp / 'service'
    shutil.copytree(root / 'services/ssh', service)
    usb, ram, proc, bins = temp / 'usb', temp / 'runtime', temp / 'proc', temp / 'bin'
    bins.mkdir(); proc.mkdir()
    write(usb / 'services/ssh/usb-log-marker.txt', 'MZD-AIO-SSH-v1\n')
    write(service / 'enabled', 'enabled\n')
    account, mounts, saved = temp / 'passwd', temp / 'mounts', temp / 'factory-saved'
    original = 'cmu:$5$fake$factory:0:0:CMU:/tmp/root:/bin/sh\nother:x:10:10:Other:/:/bin/false\n'
    write(account, original); write(mounts, '')
    key = temp / 'host-key'; write(key, 'TEST KEY: never used by a real sshd\n')
    source = (service / 'service.sh').read_text()
    for before, after in [('RAM=/tmp/mzd-aio-ssh', 'RAM=' + shlex.quote(bp(ram))),
                          ('ACCOUNT=/config-mfg/passwd', 'ACCOUNT=' + shlex.quote(bp(account))),
                          ('PASSWD_LINK=/etc/passwd', 'PASSWD_LINK=' + shlex.quote(bp(temp / 'passwd-link'))),
                          ('MOUNTS=/proc/mounts', 'MOUNTS=' + shlex.quote(bp(mounts))),
                          ('PROC=/proc', 'PROC=' + shlex.quote(bp(proc)))]: source = source.replace(before, after)
    source = source.replace('PATH=/usr/sbin:/usr/bin:/sbin:/bin', 'PATH=' + shlex.quote(bp(bins)) + ':/usr/bin:/bin')
    source = source.replace('[ "$(id -u)" = 0 ]', ':').replace('/etc/ssh/ssh_host_rsa_key', shlex.quote(bp(key)))
    source = source.replace('printf \'%s\\n\' "$$" > "$RAM/supervisor.pid"', 'printf \'%s\\n\' "$$" > "$RAM/supervisor.pid"\nmkdir -p "$PROC/$$"\nprintf \'%s\\000\' "$SELF" boot > "$PROC/$$/cmdline"')
    write(service / 'service.sh', source)
    config = (service / 'sshd_config').read_text().replace('/tmp/mzd-aio-ssh', bp(ram)).replace('/etc/ssh/ssh_host_rsa_key', bp(key))
    write(service / 'sshd_config', config)
    write(bins / 'readlink', '#!/bin/sh\nprintf "%s\\n" ' + shlex.quote(bp(account)) + '\n')
    write(bins / 'netstat', f'''#!/bin/sh
printf 'Proto Recv-Q Send-Q Local Foreign State\ntcp 0 0 0.0.0.0:36000 0.0.0.0:* LISTEN\n'
if [ -f {shlex.quote(bp(temp / 'foreign-port'))} ]; then printf 'tcp 0 0 0.0.0.0:22 0.0.0.0:* LISTEN\n'; fi
''')
    write(bins / 'mount', f'''#!/bin/sh
cp "$4" {shlex.quote(bp(saved))}
cp "$3" "$4"
printf '/fake %s tmpfs rw 0 0\n' "$4" >> {shlex.quote(bp(mounts))}
''')
    write(bins / 'umount', f'''#!/bin/sh
cp {shlex.quote(bp(saved))} "$1"
: > {shlex.quote(bp(mounts))}
''')
    chain, jump = temp / 'chain', temp / 'jump'
    write(bins / 'iptables', f'''#!/bin/sh
case "$1:$2" in
-S:INPUT) echo '-P INPUT DROP'; if [ -f {shlex.quote(bp(jump))} ]; then echo '-A INPUT -p tcp -m tcp --dport 22 -j MZD_AIO_SSH'; fi ;;
-S:MZD_AIO_SSH) [ -f {shlex.quote(bp(chain))} ] || exit 1; echo '-A MZD_AIO_SSH -j ACCEPT' ;;
-N:MZD_AIO_SSH) : > {shlex.quote(bp(chain))} ;;
-A:MZD_AIO_SSH) exit 0 ;;
-I:INPUT) : > {shlex.quote(bp(jump))} ;;
-D:INPUT) [ -f {shlex.quote(bp(jump))} ] || exit 1; rm {shlex.quote(bp(jump))} ;;
-F:MZD_AIO_SSH) exit 0 ;;
-X:MZD_AIO_SSH) rm -f {shlex.quote(bp(chain))} ;;
*) exit 1 ;;
esac
''')
    starts = temp / 'starts'
    network = temp / 'network-state'
    write(network, 'absent')
    write(bins / 'ip', f'''#!/bin/sh
case "$(cat {shlex.quote(bp(network))})" in
absent) echo 'Device wlan0 does not exist' >&2; exit 1 ;;
disabled) printf '2: wlan0: <BROADCAST> state DOWN\n' ;;
disconnected) printf '2: wlan0: <NO-CARRIER,BROADCAST,UP> state DOWN\n' ;;
connected) printf '2: wlan0: <BROADCAST,UP> state UP\n    inet 10.0.0.5/24 scope global wlan0\n' ;;
*) exit 1 ;;
esac
''')
    # Match the target grep limitation so GNU grep cannot hide another -x use.
    write(bins / 'grep', '''#!/bin/sh
for ARG in "$@"; do
    case "$ARG" in --) break ;; -*x*) echo 'unsupported grep option -x' >&2; exit 2 ;; esac
done
exec /usr/bin/grep "$@"
''')
    assert 'ListenAddress 0.0.0.0' in config
    assert 'BindToDevice' not in config
    write(bins / 'sshd', f'''#!/bin/sh
case "$0" in /*) ;; *) echo 'sshd re-exec requires execution with an absolute path' >&2; exit 1 ;; esac
if [ "$1" = -t ]; then exit 0; fi
if [ -f {shlex.quote(bp(temp / 'fail-daemon'))} ]; then exit 1; fi
CFG=$4
PIDFILE=$(awk '$1=="PidFile" {{print $2}}' "$CFG")
mkdir -p {shlex.quote(bp(proc))}/$$
printf '%s\000' /usr/sbin/sshd -D -e -f "$CFG" > {shlex.quote(bp(proc))}/$$/cmdline
printf '%s\n' "$$" > "$PIDFILE"
printf 'start\n' >> {shlex.quote(bp(starts))}
trap 'exit 0' TERM INT
N=0
while [ "$N" -lt 60 ]; do sleep 1; N=$((N+1)); done
''')
    for file in bins.iterdir(): file.chmod(0o700)
    def run(command, expected, text):
        r = subprocess.run([args.bash, str(service / 'service.sh'), command, str(usb)], capture_output=True, text=True, timeout=20)
        assert r.returncode == expected, r.stdout + r.stderr
        assert text in r.stdout + r.stderr, r.stdout + r.stderr
    run('check', 0, 'prerequisites checked')
    assert not ram.exists() and account.read_text() == original
    write(temp / 'foreign-port', 'busy')
    run('check', 1, 'Port 22 is already in use')
    assert not ram.exists() and account.read_text() == original
    run('boot', 1, 'Port 22 is already in use')
    assert not ram.exists() and account.read_text() == original
    (temp / 'foreign-port').unlink()
    write(temp / 'fail-daemon', 'fail')
    run('boot', 1, 'SSH could not open port 22')
    assert not ram.exists() and account.read_text() == original
    (temp / 'fail-daemon').unlink()
    background = subprocess.Popen([args.bash, str(service / 'service.sh'), 'boot', str(usb)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(20):
            result = subprocess.run([args.bash, str(service / 'service.sh'), 'status'], capture_output=True, timeout=10)
            if result.returncode == 0: break
            time.sleep(.5)
        else: raise AssertionError('Mock SSH did not become ready')
        expected_hash = (service / 'password.hash').read_text().strip()
        assert account.read_text().splitlines()[0].split(':')[1] == expected_hash
        assert account.read_text().splitlines()[1] == original.splitlines()[1]
        run('check', 0, 'prerequisites checked')
        run('boot', 0, 'is already running')
        assert starts.read_text().splitlines() == ['start']
        for state in ('absent', 'disabled', 'disconnected', 'connected', 'absent'):
            write(network, state)
            run('status', 0, 'SSH is running')
            assert background.poll() is None, state
            assert starts.read_text().splitlines() == ['start'], state
        chain.unlink(); jump.unlink()
        for _ in range(15):
            if chain.exists() and jump.exists(): break
            time.sleep(.5)
        assert chain.exists() and jump.exists()
        stop = subprocess.Popen([args.bash, str(service / 'service.sh'), 'stop'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        for _ in range(40):
            background.poll()  # reap the terminated supervisor for kill -0 checks
            if stop.poll() is not None: break
            time.sleep(.25)
        output, errors = stop.communicate(timeout=10)
        assert stop.returncode == 0, output + errors
        assert account.read_text() == original and not ram.exists()
        assert not chain.exists() and not jump.exists()
        assert list((usb / 'reports').glob('ssh-*/run.log'))
    finally:
        if background.poll() is None:
            subprocess.run([args.bash, str(service / 'service.sh'), 'stop'], capture_output=True, timeout=20)
            background.wait(timeout=10)
print('Passed: absent/disabled/disconnected WLAN, later address arrival/loss without service restart, target grep limitation, OEM port 36000 coexistence, occupied port 22 rejection, duplicate start, RAM password overlay, failed-start rollback, firewall reset recovery, owned-process stop and USB-only logs. No real sshd, mounts or firewall used.')
