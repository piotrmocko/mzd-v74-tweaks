"""Isolated corrected SSH worker tests; no real mounts, SSH or vehicle access."""
import hashlib,os,re,shlex,shutil,subprocess,tempfile
from pathlib import Path
REPO=Path(__file__).resolve().parents[2]
SHELL='C:/Program Files/Git/bin/bash.exe' if os.name=='nt' else '/bin/sh'
def bp(p):
    s=Path(p).resolve().as_posix();return '/'+s[0].lower()+s[2:] if len(s)>1 and s[1]==':' else s
def write(p,text):
    p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text,encoding='utf-8',newline='\n');p.chmod(0o755)
def checksum(p):write(p.with_name(p.name+'.md5'),hashlib.md5(p.read_bytes()).hexdigest()+'  '+p.name+'\n')
checks=0
with tempfile.TemporaryDirectory(prefix='mzd-ssh-worker-') as folder:
    tmp=Path(folder);usb=tmp/'usb';payload=usb/'services/ssh';shutil.copytree(REPO/'services/ssh',payload)
    bins=tmp/'bin';bins.mkdir();app=tmp/'stage_wifi.sh';version=tmp/'version.ini';mounts=tmp/'mounts';gpio=tmp/'gpio';lock=tmp/'lock';resources=tmp/'resources';resources.mkdir();service=resources/'ssh'
    original=(REPO/'jci-org/stage_wifi.sh.org').read_bytes();app.write_bytes(original)
    write(version,'JCI_SW_VER="MAZ_CMU-150_74.00.324"\n');write(gpio,'0\n')
    def reset_mounts():write(mounts,'mock '+bp(usb)+' vfat rw 0 0\nroot / relfs ro 0 0\nmock '+bp(resources)+' relfs ro 0 0\n')
    reset_mounts()
    write(bins/'mount',f'''#!/bin/sh
if [ "$3" = / ] && [ "$2" = ro,remount ] && [ -f '{bp(tmp/'fail-cleanup')}' ]; then exit 1; fi
awk -v target="$3" -v option="$2" '$2==target {{$4=(option=="rw,remount"?"rw":"ro")}} {{print}}' '{bp(mounts)}' > '{bp(tmp/'mounts-new')}'
mv '{bp(tmp/'mounts-new')}' '{bp(mounts)}'
''')
    # A CMU-compatible grep stand-in deliberately rejects the unsupported flag.
    write(bins/'grep','''#!/bin/sh
for option in "$@"; do case "$option" in -*x*) echo 'CMU grep has no -x' >&2; exit 2 ;; esac; done
exec /usr/bin/grep "$@"
''')
    for name in ['sync','killall','hwclock']:write(bins/name,'#!/bin/sh\nexit 0\n')
    write(bins/'sleep','#!/bin/sh\nexec /bin/sleep 0.02\n')
    write(bins/'cat',f'''#!/bin/sh
case "$1" in
 */install/target.data|*/uninstall/target.data) if [ -f '{bp(tmp/'fail-write')}' ]; then printf corrupt; exit 0; fi ;;
 */before.data) if [ -f '{bp(tmp/'fail-rollback')}' ]; then printf corrupt; exit 0; fi ;;
esac
exec /bin/cat "$@"
''')
    mock='''#!/bin/sh
D=$(CDPATH= cd "$(dirname "$0")" && pwd)
case "$1" in
check) [ ! -f 'FOREIGN' ] ;;
boot) [ ! -f 'FAIL_START' ] && [ -f "$D/enabled" ] && touch "$D/running" ;;
status) [ -f "$D/running" ] ;;
stop) [ ! -f 'FAIL_STOP' ] || exit 1; rm -f "$D/running" ;;
*) exit 1 ;;
esac
'''.replace('FOREIGN',bp(tmp/'foreign-port')).replace('FAIL_START',bp(tmp/'fail-start')).replace('FAIL_STOP',bp(tmp/'fail-stop'))
    write(payload/'service.sh',mock);checksum(payload/'service.sh')
    worker=payload/'run.sh';source=worker.read_text(encoding='utf-8')
    source=source.replace('#!/bin/sh\n','#!/bin/sh\nPATH='+shlex.quote(bp(bins)+':/usr/bin:/bin')+'\nexport PATH\n',1)
    source=re.sub(r'^APP=.*$','APP='+shlex.quote(bp(app)),source,flags=re.M)
    source=re.sub(r'^SERVICE=.*$','SERVICE='+shlex.quote(bp(service)),source,flags=re.M)
    source=re.sub(r'^LOCK=.*$','LOCK='+shlex.quote(bp(lock)),source,flags=re.M)
    source=source.replace('/jci/version.ini',bp(version)).replace('/proc/mounts',bp(mounts)).replace('/sys/class/gpio/Watchdog\\ Disable/value',bp(gpio)).replace('/tmp/mnt/resources',bp(resources))
    write(worker,source);checksum(worker)
    entry=usb/'ssh.sh';shutil.copyfile(REPO/'ssh.sh',entry);checksum(entry)
    env=dict(os.environ,PATH=bp(bins)+':/usr/bin:/bin')
    def run(action,code=0,contains='',restored=True):
        global checks
        r=subprocess.run([SHELL,bp(entry),action],capture_output=True,text=True,env=env,timeout=20)
        assert r.returncode==code,(action,r.returncode,r.stdout,r.stderr)
        assert contains in r.stdout+r.stderr,(action,r.stdout,r.stderr)
        assert not lock.exists()
        assert gpio.read_text().strip()=='0'
        if restored:assert 'root / relfs ro ' in mounts.read_text() and bp(resources)+' relfs ro ' in mounts.read_text()
        if code:assert 'completed.' not in r.stdout,(action,r.stdout)
        checks+=1;return r
    assert run('status').stdout=='uninstalled\n'
    write(tmp/'foreign-port','yes');run('install',1,'prerequisites failed');assert app.read_bytes()==original;(tmp/'foreign-port').unlink()
    run('install',contains='install completed');assert app.read_bytes()!=original and (service/'enabled').is_file()
    assert run('status').stdout=='installed\n'
    saved=app.with_name(app.name+'.org').stat().st_mtime_ns
    run('install',contains='already present');assert app.with_name(app.name+'.org').stat().st_mtime_ns==saved
    (service/'enabled').unlink();run('status',1,'enabled marker');write(service/'enabled','enabled\n')
    saved_payload=(service/'service.sh').read_bytes();(service/'service.sh').unlink();run('status',1,'payload is missing or changed');(service/'service.sh').write_bytes(saved_payload)
    run('uninstall',contains='uninstall completed');assert app.read_bytes()==original and not service.exists()
    assert run('status').stdout=='uninstalled\n'
    write(tmp/'fail-start','yes');run('install',1,'did not start');assert app.read_bytes()==original;(tmp/'fail-start').unlink();run('uninstall')
    run('install');write(tmp/'fail-stop','yes');run('uninstall',2,'Do NOT reboot');(tmp/'fail-stop').unlink();run('uninstall')
    write(tmp/'fail-write','yes');run('install',1,'previous file was restored');assert app.read_bytes()==original
    write(tmp/'fail-rollback','yes');run('install',2,'rollback failed');assert app.read_bytes()!=original
    (tmp/'fail-write').unlink();(tmp/'fail-rollback').unlink();app.write_bytes(original)
    write(tmp/'fail-cleanup','yes');run('install',2,'Cleanup failed',False);(tmp/'fail-cleanup').unlink();reset_mounts();run('uninstall')
    app.with_name(app.name+'.org').write_bytes(b'bad backup');run('install',1,'known OEM original');assert app.read_bytes()==original
print('Passed',checks,'isolated SSH worker checks (including payload status, rollback severity, cleanup and native-grep compatibility).')
