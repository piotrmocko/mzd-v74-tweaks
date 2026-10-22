"""Port only the original AIO main-menu focus-boundary changes to v74."""
import hashlib
from pathlib import Path
import sys

data = Path(sys.argv[1]).read_bytes()
assert hashlib.md5(data).hexdigest() == '40ccb293b8c6f80960f0b953dd2e173e'
for before, after in [(b'if (index < 0)\n    {\n        index = 0;', b'if (index < 0)\n    {\n        index = 4;'),
                      (b'if (index > 4)\n    {\n        index = 4;', b'if (index > 4)\n    {\n        index = 0;')]:
    assert data.count(before) == 1
    data = data.replace(before, after)
assert hashlib.md5(data).hexdigest() == 'ae272c9befc1350b93f23511568f13c7'
Path(sys.argv[2]).write_bytes(data)
