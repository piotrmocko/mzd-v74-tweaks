"""Rebuild a v74 List2 variant: bit 1 = no beep, 2 = shorter delay, 4 = loop."""
import hashlib
from pathlib import Path
import re
import sys

source, output, mask = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3])
assert 0 <= mask <= 7
data = source.read_bytes()
assert hashlib.md5(data).hexdigest() == 'e111883b9dcbeb6bb154521826fcacac'
text = data.decode('utf-8')

if mask & 1:
    before = "    this._beep('Long', 'Multicontroller');"
    assert text.count(before) == 2
    text = text.replace(before, "//  this._beep('Long', 'Multicontroller');")
if mask & 2:
    for before, after in [('autoscrollTier1Timeout :                1500,', 'autoscrollTier1Timeout :                150,'),
                          ('autoscrollTier2Timeout :                5000,', 'autoscrollTier2Timeout :                300,'),
                          ('autoscrollTier1Interval :               500,', 'autoscrollTier1Interval :               200,'),
                          ('autoscrollTier2Interval :               1000,', 'autoscrollTier2Interval :               300,')]:
        assert text.count(before) == 1
        text = text.replace(before, after)
if mask & 4:
    handlers = Path(__file__).with_name('list-loop-functions.js').read_text(encoding='utf-8')
    for name in ['_handleMCCW', '_handleMCCCW', '_handleMCDown', '_handleMCUp']:
        pattern = r'^List2Ctrl\.prototype\.' + name + r' = function\(\)\n.*?^};'
        replacement = re.search(pattern, handlers, re.M | re.S).group()
        text, count = re.subn(pattern, lambda match: replacement, text, flags=re.M | re.S)
        assert count == 1
output.write_bytes(text.encode('utf-8'))
