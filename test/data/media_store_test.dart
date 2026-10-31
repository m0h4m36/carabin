import 'dart:io';
import 'dart:typed_data';

import 'package:carabin/data/errors.dart';
import 'package:carabin/data/media_store.dart';
import 'package:carabin/domain/note_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/png.dart';

void main() {
  late Directory tmp;
  late MediaStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('carabin_media_');
    store = MediaStore(p.join(tmp.path, 'media'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('le nom dépend du contenu : même image, même fichier', () {
    final png = solidPng(4, 3);
    final a = store.addBytes(png, 'png');
    final b = store.addBytes(Uint8List.fromList(png), 'png');
    expect(a, b);
    expect(mediaNamePattern.hasMatch(a), isTrue);
    expect(Directory(store.dir).listSync(), hasLength(1));
    expect(store.read(a), png);
  });

  test('deux images différentes ont deux noms', () {
    final a = store.addBytes(solidPng(4, 3), 'png');
    final b = store.addBytes(solidPng(4, 3, r: 1), 'png');
    expect(a, isNot(b));
  });

  test('addFile normalise l\'extension et refuse les autres formats', () {
    final src = File(p.join(tmp.path, 'Schéma.JPEG'))
      ..writeAsBytesSync(solidPng(2, 2));
    expect(store.addFile(src.path), endsWith('.jpg'));
    final pdf = File(p.join(tmp.path, 'x.pdf'))..writeAsBytesSync([1, 2, 3]);
    expect(() => store.addFile(pdf.path), throwsA(isA<UnsupportedFileError>()));
    expect(
      () => store.addBytes(Uint8List(3), 'svg'),
      throwsA(isA<UnsupportedFileError>()),
    );
  });

  test('aucun nom ne peut sortir du dossier', () {
    for (final bad in [
      '../carabin.db',
      '/etc/passwd',
      'a/b.png',
      'x.png',
      '',
    ]) {
      expect(store.exists(bad), isFalse, reason: bad);
      expect(() => store.file(bad), throwsA(isA<NotFoundError>()), reason: bad);
    }
  });

  test('le nettoyage retire seulement les médias que personne ne cite', () {
    final keep = store.addBytes(solidPng(2, 2), 'png');
    final drop = store.addBytes(solidPng(3, 3), 'png');
    File(p.join(store.dir, 'notes.txt')).writeAsStringSync('à moi');
    expect(store.unused({keep}), [drop]);
    expect(store.purge({keep}), 1);
    expect(store.exists(keep), isTrue);
    expect(store.exists(drop), isFalse);
    expect(File(p.join(store.dir, 'notes.txt')).existsSync(), isTrue);
  });
}
