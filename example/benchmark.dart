import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:maxminddb/maxminddb.dart';

void main(List<String> args) async {
  late MaxMindDatabase database;
  if (args.isNotEmpty && args[0] == 'memory') {
    database = await MaxMindDatabase.memory(
      File('GeoLite2-City.mmdb').readAsBytesSync(),
    );
  } else {
    database = await MaxMindDatabase.file(File('GeoLite2-City.mmdb'));
  }

  final random = Random();
  final addresses = <String>[];

  for (var i = 0; i < 10000; i++) {
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = random.nextInt(0xff);
    }
    addresses.add(InternetAddress.fromRawAddress(bytes).address);
  }

  final start = DateTime.now();
  for (final address in addresses) {
    await database.search(address);
  }
  print(DateTime.now().difference(start));
}
