#!/usr/bin/env python3
"""Fabrique `anki_latest.apkg`, un paquet Anki au format récent (collection
SQLite de schéma 18 compressée en zstd, métadonnées et médias en protobuf),
pour tester l'import. Nécessite le module `zstandard` (compresseur de
référence) : `pip install zstandard`. À relancer seulement si le jeu d'essai
change ; le résultat est versionné.

Tout le contenu est inventé pour les tests."""
import hashlib
import sqlite3
import struct
import tempfile
import os
import zlib
import zipfile

import zstandard

CRT = 1700000000  # création de la collection (secondes)
ZSTD = zstandard.ZstdCompressor(level=3)


# --------------------------------------------------------------- protobuf
def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def field_bytes(num, data):
    if isinstance(data, str):
        data = data.encode()
    return varint(num << 3 | 2) + varint(len(data)) + data


def field_varint(num, value):
    return varint(num << 3) + varint(value)


# ------------------------------------------------------------------ images
def png(rgb):
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b''.join(b'\x00' + bytes(rgb) * 4 for _ in range(4))
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', 4, 4, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw))
            + chunk(b'IEND', b''))


MEDIA = [
    ('paste-abc.png', png((200, 30, 30))),
    ('sound.mp3', b'ID3fake-audio'),
    ('vector.svg', b'<svg xmlns="http://www.w3.org/2000/svg"/>'),
    ('my image.png', png((30, 30, 200))),
]


# ------------------------------------------------------------- collection
def unicase(a, b):
    a, b = a.lower(), b.lower()
    return (a > b) - (a < b)


SCHEMA = """
CREATE TABLE col (id integer PRIMARY KEY, crt integer NOT NULL, mod integer NOT NULL,
  scm integer NOT NULL, ver integer NOT NULL, dty integer NOT NULL, usn integer NOT NULL,
  ls integer NOT NULL, conf text NOT NULL, models text NOT NULL, decks text NOT NULL,
  dconf text NOT NULL, tags text NOT NULL);
CREATE TABLE notes (id integer PRIMARY KEY, guid text NOT NULL, mid integer NOT NULL,
  mod integer NOT NULL, usn integer NOT NULL, tags text NOT NULL, flds text NOT NULL,
  sfld integer NOT NULL, csum integer NOT NULL, flags integer NOT NULL, data text NOT NULL);
CREATE TABLE cards (id integer PRIMARY KEY, nid integer NOT NULL, did integer NOT NULL,
  ord integer NOT NULL, mod integer NOT NULL, usn integer NOT NULL, type integer NOT NULL,
  queue integer NOT NULL, due integer NOT NULL, ivl integer NOT NULL, factor integer NOT NULL,
  reps integer NOT NULL, lapses integer NOT NULL, left integer NOT NULL, odue integer NOT NULL,
  odid integer NOT NULL, flags integer NOT NULL, data text NOT NULL);
CREATE TABLE revlog (id integer PRIMARY KEY, cid integer NOT NULL, usn integer NOT NULL,
  ease integer NOT NULL, ivl integer NOT NULL, lastIvl integer NOT NULL, factor integer NOT NULL,
  time integer NOT NULL, type integer NOT NULL);
CREATE TABLE graves (usn integer NOT NULL, oid integer NOT NULL, type integer NOT NULL);
"""

SCHEMA18 = """
CREATE TABLE fields (ntid integer NOT NULL, ord integer NOT NULL,
  name text NOT NULL COLLATE unicase, config blob NOT NULL, PRIMARY KEY (ntid, ord)) without rowid;
CREATE TABLE templates (ntid integer NOT NULL, ord integer NOT NULL,
  name text NOT NULL COLLATE unicase, mtime_secs integer NOT NULL, usn integer NOT NULL,
  config blob NOT NULL, PRIMARY KEY (ntid, ord)) without rowid;
CREATE TABLE notetypes (id integer NOT NULL PRIMARY KEY, name text NOT NULL COLLATE unicase,
  mtime_secs integer NOT NULL, usn integer NOT NULL, config blob NOT NULL);
CREATE UNIQUE INDEX idx_notetypes_name ON notetypes (name);
CREATE TABLE decks (id integer PRIMARY KEY NOT NULL, name text NOT NULL COLLATE unicase,
  mtime_secs integer NOT NULL, usn integer NOT NULL, common blob NOT NULL, kind blob NOT NULL);
CREATE UNIQUE INDEX idx_decks_name ON decks (name);
"""

NOTETYPES = [
    # id, nom, cloze?, champs, modèles (nom, question, réponse)
    (1, 'Basique', False, ['Recto', 'Verso'],
     [('Carte 1', '{{Recto}}', '{{FrontSide}}\n\n<hr id=answer>\n\n{{Verso}}')]),
    (2, 'Basique (et carte inversée)', False, ['Recto', 'Verso'],
     [('Carte 1', '{{Recto}}', '{{FrontSide}}\n\n<hr id=answer>\n\n{{Verso}}'),
      ('Carte 2', '{{Verso}}', '{{FrontSide}}\n\n<hr id=answer>\n\n{{Recto}}')]),
    (3, 'Texte à trous', True, ['Texte', 'Extra'],
     [('Texte à trous', '{{cloze:Texte}}', '{{cloze:Texte}}<br>\n{{Extra}}')]),
    (4, 'Occlusion d\'image', True, ['Occlusion', 'Image', 'Header', 'Back Extra', 'Comments'],
     [('Occlusion d\'image', '{{#Header}}<div>{{Header}}</div>{{/Header}}<div style="display: none">{{cloze:Occlusion}}</div><div>{{Image}}</div>',
       '{{Header}}{{Image}}{{#Back Extra}}<div>{{Back Extra}}</div>{{/Back Extra}}')]),
    (5, 'Anatomie', False, ['Nom', 'Description', 'Schéma'],
     [('Nom', '{{Nom}}', '{{FrontSide}}<hr id=answer>{{Description}}'),
      ('Schéma', '{{#Schéma}}{{Schéma}}{{/Schéma}}', '{{FrontSide}}<hr id=answer>{{Nom}}')]),
    (6, 'Basique (saisir la réponse)', False, ['Recto', 'Verso'],
     [('Carte 1', '{{Recto}}\n\n{{type:Verso}}', '{{Recto}}\n\n<hr id=answer>\n\n{{type:Verso}}')]),
]


def build_collection(path, with_unicase=True):
    con = sqlite3.connect(path)
    if with_unicase:
        con.create_collation('unicase', unicase)
    con.executescript(SCHEMA)
    con.executescript(SCHEMA18)
    con.execute("INSERT INTO col VALUES (1, ?, 0, 0, 18, 0, 0, 0, '{}', '', '', '', '')", (CRT,))

    for ntid, name, cloze, fields, templates in NOTETYPES:
        cfg = (field_varint(1, 1) if cloze else b'') + field_bytes(3, '.card { }')
        con.execute('INSERT INTO notetypes VALUES (?, ?, 0, 0, ?)', (ntid, name, cfg))
        for i, f in enumerate(fields):
            con.execute('INSERT INTO fields VALUES (?, ?, ?, ?)', (ntid, i, f, b''))
        for i, (tname, q, a) in enumerate(templates):
            tcfg = field_bytes(1, q) + field_bytes(2, a)
            con.execute('INSERT INTO templates VALUES (?, ?, ?, 0, 0, ?)', (ntid, i, tname, tcfg))

    normal = b'\x0a\x00'
    filtered = b'\x12\x00'
    con.execute('INSERT INTO decks VALUES (1, ?, 0, 0, ?, ?)', ('Par défaut', b'', normal))
    con.execute('INSERT INTO decks VALUES (2, ?, 0, 0, ?, ?)', ('Cardio\x1fCœur', b'', normal))
    con.execute('INSERT INTO decks VALUES (3, ?, 0, 0, ?, ?)', ('Étude filtrée', b'', filtered))

    def note(nid, guid, mid, tags, flds, mod=1700100000):
        con.execute('INSERT INTO notes VALUES (?, ?, ?, ?, 0, ?, ?, 0, 0, 0, \'\')',
                    (nid, guid, mid, mod, tags, '\x1f'.join(flds)))

    def card(cid, nid, did, ord_, type_=0, queue=0, due=1, ivl=0, factor=0, reps=0,
             lapses=0, odue=0, odid=0, data=''):
        con.execute('INSERT INTO cards VALUES (?, ?, ?, ?, 0, 0, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, 0, ?)',
                    (cid, nid, did, ord_, type_, queue, due, ivl, factor, reps, lapses, odue, odid, data))

    # 1. Basique avec image, son, étiquettes hiérarchiques
    note(1700000000001, 'guidBasic01', 1, ' anat cœur::valves ',
         ['<b>Aorte</b>', 'Naît du <i>VG</i><br><img src="paste-abc.png">[sound:sound.mp3]'])
    card(101, 1700000000001, 2, 0)

    # 2. Avec carte inversée : première carte en révision, seconde suspendue
    note(1700000000002, 'guidRevers02', 2, '', ['Systole', 'Contraction'])
    card(201, 1700000000002, 2, 0, type_=2, queue=2, due=50, ivl=20, factor=2300, reps=6,
         lapses=1, data='{"s":31.5,"d":4.2}')
    card(202, 1700000000002, 2, 1, queue=-1)
    for i, (ease, ivl, typ) in enumerate([(3, -600, 0), (3, 4, 1), (1, 20, 1)]):
        con.execute('INSERT INTO revlog VALUES (?, 201, 0, ?, ?, 0, 2500, 4000, ?)',
                    (1700200000000 + i * 86400000, ease, ivl, typ))
    con.execute('INSERT INTO revlog VALUES (1700300000000, 201, 0, 0, 0, 0, 0, 0, 4)')  # report manuel

    # 3. Texte à trous (deux trous) + complément ; ensuite un texte à trous imbriqués
    note(1700000000003, 'guidCloze03', 3, ' physio ',
         ['Le {{c1::cœur}} bat <b>{{c2::60}}</b> fois/min', 'Normal au repos'])
    card(301, 1700000000003, 2, 0, type_=2, queue=2, due=80, ivl=7, factor=2500, reps=3)
    card(302, 1700000000003, 2, 1)
    note(1700000000004, 'guidNested04', 3, '', ['{{c1::a {{c2::b}} c}}', ''])
    card(401, 1700000000004, 2, 0)
    card(402, 1700000000004, 2, 1)

    # 4. Occlusion d'image (nom de fichier avec espace encodé)
    occ = ('{{c1::image-occlusion:rect:left=.1:top=.2:width=.3:height=.1:oi=1}}<br>'
           '{{c2::image-occlusion:ellipse:left=.5:top=.5:rx=.1:ry=.05:oi=1}}<br>'
           '{{c2::image-occlusion:rect:left=.7:top=.1:width=.1:height=.1:oi=1}}')
    note(1700000000005, 'guidOcc05', 4, ' schema ',
         [occ, '<img src="my%20image.png">', 'Cœur', 'Vue de face', ''])
    card(501, 1700000000005, 2, 0)
    card(502, 1700000000005, 2, 1)

    # 5. Type personnalisé à deux cartes qui ne sont pas inverses l'une de l'autre
    note(1700000000006, 'guidCustom06', 5, '',
         ['Ventricule gauche', 'Pompe vers l\'aorte', '<img src="paste-abc.png">'])
    card(601, 1700000000006, 2, 0)
    card(602, 1700000000006, 2, 1)

    # 6. Saisie de la réponse
    note(1700000000007, 'guidTyped07', 6, '', ['Capitale de la France ?', 'Paris'])
    card(701, 1700000000007, 2, 0)

    # 7. Type de note inconnu
    note(1700000000008, 'guidGhost08', 999, '', ['x', 'y'])
    card(801, 1700000000008, 2, 0)

    # 8. Carte dans un paquet filtré : son vrai paquet est dans odid
    note(1700000000009, 'guidFiltered09', 1, '', ['Valve mitrale', 'Entre OG et VG'])
    card(901, 1700000000009, 3, 0, type_=2, queue=2, due=1234, ivl=5, factor=2500, reps=2,
         odue=90, odid=2)

    # 9. Note dans le paquet par défaut
    note(1700000000010, 'guidDefault10', 1, '', ['Sans paquet', 'Paquet par défaut'])
    card(1001, 1700000000010, 1, 0)

    con.commit()
    con.close()


def build_dummy(path):
    con = sqlite3.connect(path)
    con.executescript(SCHEMA)
    con.execute("INSERT INTO col VALUES (1, ?, 0, 0, 11, 0, 0, 0, '{}', '{}', '{}', '{}', '{}')", (CRT,))
    con.execute("INSERT INTO notes VALUES (1, 'dummy', 1, 0, 0, '', ?, 0, 0, 0, '')",
                ('Please update to the latest Anki version, then import the .colpkg/.apkg file again.',))
    con.commit()
    con.close()


def main(out):
    with tempfile.TemporaryDirectory() as tmp:
        real = os.path.join(tmp, 'real.sqlite')
        dummy = os.path.join(tmp, 'dummy.sqlite')
        build_collection(real)
        build_dummy(dummy)
        media_list = b''
        for i, (name, data) in enumerate(MEDIA):
            entry = (field_bytes(1, name) + field_varint(2, len(data))
                     + field_bytes(3, hashlib.sha1(data).digest()))
            media_list += field_bytes(1, entry)
        with zipfile.ZipFile(out, 'w', zipfile.ZIP_STORED) as z:
            z.writestr('collection.anki21b', ZSTD.compress(open(real, 'rb').read()))
            z.writestr('collection.anki2', open(dummy, 'rb').read())
            z.writestr('meta', field_varint(1, 3))
            z.writestr('media', ZSTD.compress(media_list))
            for i, (_, data) in enumerate(MEDIA):
                z.writestr(str(i), ZSTD.compress(data))


if __name__ == '__main__':
    here = os.path.dirname(os.path.abspath(__file__))
    main(os.path.join(here, 'anki_latest.apkg'))
