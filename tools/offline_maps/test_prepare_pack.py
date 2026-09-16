import base64
from contextlib import closing
import json
import sqlite3
import struct
import tempfile
import unittest
import zlib
from pathlib import Path
from prepare_pack import prepare, coordinates


def png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>2I5B', 256, 256, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\0' + b'\xee\xee\xee' * 256) * 256)) + chunk(b'IEND', b'')


class PackTest(unittest.TestCase):
    def test_tms_conversion_and_incomplete_pack_preserves_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source, output = root / 'test.mbtiles', root / 'field-region.json'
            with closing(sqlite3.connect(source)) as db, db:
                db.execute('CREATE TABLE metadata(name TEXT, value TEXT)')
                db.execute('CREATE TABLE tiles(zoom_level INTEGER,tile_column INTEGER,tile_row INTEGER,tile_data BLOB)')
                db.executemany('INSERT INTO tiles VALUES(?,?,?,?)', [(z, x, (1 << z) - 1 - y, png()) for z, x, y in coordinates()])
            prepare(source, output, 'Test fixture only')
            before = output.read_bytes()
            data = json.loads(before)
            self.assertEqual(set(data['tiles']), {f'{z}/{x}/{y}' for z, x, y in coordinates()})
            self.assertEqual(base64.b64decode(next(iter(data['tiles'].values()))), png())
            with closing(sqlite3.connect(source)) as db, db:
                db.execute('DELETE FROM tiles WHERE rowid=1')
            with self.assertRaises(ValueError):
                prepare(source, output, 'Test fixture only')
            self.assertEqual(output.read_bytes(), before)

if __name__ == '__main__':
    unittest.main()

