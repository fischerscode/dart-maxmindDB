[![](https://img.shields.io/pub/v/maxminddb)](https://pub.dev/packages/maxminddb)
[![CI](https://github.com/fischerscode/dart-maxmindDB/actions/workflows/ci.yaml/badge.svg)](https://github.com/fischerscode/dart-maxmindDB/actions/workflows/ci.yaml)

# dart-maxmindDB

This dart library is capable of searching ip addresses in [MAXMINDs mmdb databases](https://maxmind.github.io/MaxMind-DB/).

As its main use case, this library can be used to get the geo location of an IP address by using the [GeoLite2 Database](https://dev.maxmind.com/geoip/geolite2-free-geolocation-data).

## Usage:
1. Initialize the database:
   ```dart
   var database = await MaxMindDatabase.memory(
        File('GeoLite2-City.mmdb').readAsBytesSync());

   // OR

   var database = await MaxMindDatabase.file(File('GeoLite2-City.mmdb'));
   ```
2. Search the database:
   ```dart
   print(await database.search('8.8.8.8'));
   ```
The result might vary depending on the database you are using.

The database can either be loaded in memory or queried from a file system.
Depending on the compute power and **disk speed**, loading the database in memory should be roughly 20 times faster.

The library can be benchmarked using the [benchmark example](example/benshmark.dart).