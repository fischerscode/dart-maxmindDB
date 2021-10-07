import 'dart:io';

import 'package:maxminddb/maxminddb.dart';

void main(List<String> args) async {
  final database = await MaxMindDatabase.file(File('GeoLite2-City.mmdb'));
  for (var arg in args) {
    print(await database.search(arg));
  }
}
