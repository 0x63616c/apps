"""Validate offline design artifacts; no app dependencies or platform claims."""
from html.parser import HTMLParser
from pathlib import Path
import json
import re
import struct

ROOT = Path(__file__).resolve().parent
SCREENS = json.loads((ROOT / 'screens.json').read_text())


class Document(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.path = path
        self.actions = 0
        self.selected = 0
        self.feed(path.read_text())

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'button' in attrs.get('class', '').split():
            self.actions += 1
        if attrs.get('aria-current') == 'true':
            self.selected += 1
        for key in ('href', 'src'):
            url = attrs.get(key, '')
            if not url or re.match(r'^[a-z]+:|^#', url):
                continue
            target = (self.path.parent / url.split('#')[0]).resolve()
            assert target.is_relative_to(ROOT), (self.path.name, url)
            assert target.is_file(), (self.path.name, url)


assert len({s['slug'] for s in SCREENS}) == len(SCREENS)
assert {p.stem for p in ROOT.glob('*.html')} == {'index'} | {s['slug'] for s in SCREENS}
assert {p.stem for p in (ROOT / 'screenshots').glob('*.png')} == {'contact-sheet'} | {s['slug'] for s in SCREENS}
for screen in SCREENS:
    slug = screen['slug']
    path = ROOT / (slug + '.html')
    doc = Document(path)
    html = path.read_text()
    assert not re.search(r'blocker', html.replace('Blockr: App Blocker', ''), re.I), slug
    assert 'class="note"' not in html and '<p class="small' not in html, slug
    header = (ROOT / 'screenshots' / (slug + '.png')).read_bytes()[:24]
    assert header[:8] == b'\x89PNG\r\n\x1a\n', slug
    assert struct.unpack('>II', header[16:24]) == (screen['width'] * 2, screen['height'] * 2), slug
    if slug.startswith('22'):
        assert doc.actions == 1, slug
    if screen['platform'] == 'Mac':
        assert '<div class="status"' not in html and 'class="homebar"' not in html, slug
    if '<div class="choice"' in html:
        assert doc.selected == 1, slug
        choice = html.split('<div class="choice"')[1].split('</div>')[0]
        labels = re.findall(r'>([^<>]+)</a>', choice)
        assert labels in [['1h', '2h', '4h', '1d', '3d', '+'], ['1h', '1.5h', '2h', '4h', '1d', '3d', '+']], (slug, labels)
Document(ROOT / 'index.html')
report = json.loads((ROOT / 'render-report.json').read_text())
assert report['screenCount'] == len(SCREENS)
assert not report['errors']
assert all(not item['overflow'] and not item['outside'] for item in report['findings'])
assert {f['screen'] for f in report['findings']} == {s['slug'] for s in SCREENS}
print(f'Validated {len(SCREENS)} screens: inventory, local links, PNG sizes, names, shields, duration states and render findings.')
