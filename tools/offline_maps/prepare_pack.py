"""Prepare ONE bounded offline pack from legally obtained raster MBTiles.
No HTTP client, tile scraping or calls to OSM public tile servers.
Python 3 standard library only.
"""
import argparse
from contextlib import closing
import base64
import json
import math
import sqlite3
from pathlib import Path

REGION = 'syktyvkar-railway-v1'
SOUTH, NORTH, WEST, EAST = 61.654, 61.665, 50.786, 50.807
MAX_PACK = 12 * 1024 * 1024
MAX_DECODED = 8 * 1024 * 1024


def coordinates():
    for z in range(13, 17):
        n = 1 << z
        def x(lon):
            return math.floor((lon + 180) / 360 * n)
        def y(lat):
            r = math.radians(lat)
            return math.floor((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n)
        for tx in range(x(WEST), x(EAST) + 1):
            for ty in range(y(NORTH), y(SOUTH) + 1):
                yield z, tx, ty


def prepare(source, output, attribution):
    if not 0 < len(attribution) <= 300:
        raise ValueError('Attribution must contain 1..300 characters')
    tiles = {}
    total = 0
    with closing(sqlite3.connect(source.resolve().as_uri() + '?mode=ro', uri=True)) as db:
        metadata = dict(db.execute('SELECT name, value FROM metadata'))
        scheme = metadata.get('scheme', 'tms')
        if scheme not in ('tms', 'xyz'):
            raise ValueError('Unsupported tile coordinate scheme')
        for z, x, y in coordinates():
            row = y if scheme == 'xyz' else (1 << z) - 1 - y
            result = db.execute('SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?', (z, x, row)).fetchone()
            if result is None:
                raise ValueError(f'Missing tile {z}/{x}/{y}; partial packs are not accepted')
            png = result[0]
            total += len(png)
            if len(png) < 24 or png[:8] != b'\x89PNG\r\n\x1a\n' or int.from_bytes(png[16:20], 'big') != 256 or int.from_bytes(png[20:24], 'big') != 256:
                raise ValueError('Only raster PNG 256x256 MBTiles are supported (not vector PBF/JPEG)')
            if len(png) > 256 * 1024 or total > MAX_DECODED:
                raise ValueError('Tile/decompressed pack limit exceeded')
            tiles[f'{z}/{x}/{y}'] = base64.b64encode(png).decode('ascii')
    pack = dict(format='xyz-png-v1', region=REGION, offlineAllowed=True,
                attribution=attribution, tiles=tiles)
    encoded = json.dumps(pack, ensure_ascii=False, separators=(',', ':')).encode('utf8')
    if len(encoded) > MAX_PACK:
        raise ValueError('Pack exceeds 12 MiB')
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix('.json.tmp')
    temporary.write_bytes(encoded)
    temporary.replace(output)
    print(f'Prepared {len(tiles)} tiles, {len(encoded)} bytes: {output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mbtiles', type=Path)
    parser.add_argument('--output', type=Path, default=Path('tools/offline_maps/output/field-region.json'))
    parser.add_argument('--attribution', required=True, help='Required OSM data AND renderer/provider credits')
    parser.add_argument('--rights-confirmed', action='store_true', help='You have permission to redistribute/use these raster tiles offline')
    args = parser.parse_args()
    if not args.rights_confirmed:
        parser.error('Confirm offline redistribution rights with --rights-confirmed; public OSM tiles must not be bulk downloaded')
    prepare(args.mbtiles, args.output, args.attribution)

