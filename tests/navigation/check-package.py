"""Exercise the release workflow's local file-copy recipe, without publishing."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import zipfile

repo = Path(__file__).resolve().parents[2]
shell = sys.argv[1] if len(sys.argv) > 1 else ('C:/Program Files/Git/bin/bash.exe' if os.name == 'nt' else '/bin/sh')
workflow = (repo / '.github/workflows/release.yml').read_text(encoding='utf-8')
copies = [line.strip() for line in workflow.splitlines()
          if line.strip().startswith('cp -R ') and '"$package/"' in line]
assert len(copies) == 2 and ' services ' in copies[0]

with tempfile.TemporaryDirectory(prefix='mzd-release-check-') as folder:
    stage = Path(folder) / 'package'
    stage.mkdir()
    path = stage.as_posix()
    if len(path) > 1 and path[1] == ':': path = '/' + path[0].lower() + path[2:]
    for line in copies:
        subprocess.run([shell, '-c', line.replace('"$package/"', '"$1/"'), 'package-test', path],
                       cwd=repo, check=True)
    archive = Path(folder) / 'usb.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as out:
        for file in stage.rglob('*'):
            if file.is_file(): out.write(file, file.relative_to(stage).as_posix())
    with zipfile.ZipFile(archive) as package:
        for file in ['ssh.sh', 'list-tweaks.sh', 'main-menu-loop.sh',
                     'services/ssh/service.sh', 'services/ssh/sshd_config',
                     'services/ssh/password.hash', 'services/ssh/usb-log-marker.txt',
                     'jci-org/stage_wifi.sh.org', 'jci-org/List2Ctrl.js.org',
                     'jci-org/MainMenuCtrl.js.org', 'jci-mods/MainMenuCtrl.js'] + [
                         f'jci-mods/List2Ctrl-{i}.js' for i in range(1, 8)]:
            content = package.read(file)
            assert content == (repo / file).read_bytes(), file
            assert hashlib.md5(content).hexdigest() == package.read(file + '.md5').decode().split()[0], file
        assert package.testzip() is None
        assert 'services/ssh/service.sh' in package.namelist()
        print(f'Release copy recipe passed; {len(package.namelist())} files in the local USB ZIP.')
