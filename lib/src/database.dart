import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:extendedip/extendedip.dart';

import 'package:maxminddb/src/data_provider.dart';

/// A [MaxMindDatabase] is the dart equivalent of a mmdb-file.
class MaxMindDatabase {
  /// The number of nodes in the database.
  final int nodeCount;

  @Deprecated("Use nodeCount instead.")
  // ignore: non_constant_identifier_names
  int get node_count => nodeCount;

  /// The size of each record in the database.
  /// One node contains two records.
  final int recordSize;

  @Deprecated("Use recordSize instead.")
  // ignore: non_constant_identifier_names
  int get record_size => recordSize;

  /// The IP version this database is for.
  /// An v4 address can also be searched in a v6 database.
  final int ipVersion;

  @Deprecated("Use ipVersion instead.")
  // ignore: non_constant_identifier_names
  int get ip_version => ipVersion;

  /// The database type.
  /// See specification.
  final String databaseType;

  @Deprecated("Use databaseType instead.")
  // ignore: non_constant_identifier_names
  String get database_type => databaseType;

  /// An list of locale codes.
  /// A record may contain data items that have been localized to some or all of these locales.
  /// Records should not contain localized data for locales not included in this array.
  final List<String> languages;

  /// The major version of the specification this database uses.
  final int binaryFormatMajorVersion;

  @Deprecated("Use binaryFormatMajorVersion instead.")
  // ignore: non_constant_identifier_names
  int get binary_format_major_version => binaryFormatMajorVersion;

  /// The minor version of the specification this database uses.
  final int binaryFormatMinorVersion;

  @Deprecated("Use binaryFormatMinorVersion instead.")
  // ignore: non_constant_identifier_names
  int get binary_format_minor_version => binaryFormatMinorVersion;

  /// The database build timestamp as a Unix epoch value.
  final int buildEpoch;

  @Deprecated("Use buildEpoch instead.")
  // ignore: non_constant_identifier_names
  int get build_epoch => buildEpoch;

  /// A database description.
  /// The codes may include additional information such as script or country identifiers,
  /// like “zh-TW” or “mn-Cyrl-MN”.
  /// The additional identifiers will be separated by a dash character (“-“).
  final Map<String, String> description;

  /// The datasource of this database.
  final DataProvider data;

  /// Create a [MaxMindDatabase] instance from metadata.
  MaxMindDatabase._({
    required this.nodeCount,
    required this.recordSize,
    required this.ipVersion,
    required this.databaseType,
    required this.languages,
    required this.binaryFormatMajorVersion,
    required this.binaryFormatMinorVersion,
    required this.buildEpoch,
    required this.description,
    required this.data,
  });

  /// Create a [MaxMindDatabase] instance from a mmdb-[file].
  static Future<MaxMindDatabase> file(File file) {
    return MaxMindDatabase.dataProvider(DataProvider(file));
  }

  /// Create a [MaxMindDatabase] instance from the loaded [data] of an mmdb-file.
  static Future<MaxMindDatabase> memory(Uint8List data) {
    return MaxMindDatabase.dataProvider(DataProvider.memory(data));
  }

  /// Create a [MaxMindDatabase] instance while getting the [data] from a [DataProvider].
  static Future<MaxMindDatabase> dataProvider(DataProvider data) async {
    // METADATA_BEGIN_MARKER
    final metadataBeginMarker =
        [0xAB, 0xCD, 0xEF] + ascii.encoder.convert('MaxMind.com');

    final metaDataStart = (await data.searchLastSequence(metadataBeginMarker))!;

    final meta = (await _decodeData(
      data,
      metaDataStart + metadataBeginMarker.length,
      metaDataStart,
    ))
        .data as Map<dynamic, dynamic>;

    return MaxMindDatabase._(
      data: data,
      binaryFormatMajorVersion: meta['binary_format_major_version'] as int,
      binaryFormatMinorVersion: meta['binary_format_minor_version'] as int,
      buildEpoch: meta['build_epoch'] as int,
      databaseType: meta['database_type'] as String,
      description:
          ((meta['description'] ?? <String, dynamic>{}) as Map<String, dynamic>)
              .map((key, value) => MapEntry(key, value as String)),
      ipVersion: meta['ip_version'] as int,
      languages: ((meta['languages'] ?? <dynamic>[]) as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      nodeCount: meta['node_count'] as int,
      recordSize: meta['record_size'] as int,
    );
  }

  /// Search the database for an ip [address] in [String] format.
  Future<dynamic> search(String address) {
    return searchAddress(InternetAddress(address));
  }

  /// Search the database for an ip [address] that has been parsed to a [InternetAddress].
  Future<dynamic> searchAddress(InternetAddress address) {
    if (address.type == InternetAddressType.IPv4 && ipVersion == 6) {
      return searchAddress(address.toIPv6());
    }

    if (address.type == InternetAddressType.IPv6 && ipVersion == 4) {
      throw Exception(
        "An IPv6 address can't be processed by this IPv4 database.",
      );
    }

    return _search(data, 0, address.rawAddress.bits);
  }

  /// Recursively search the remaining [address] in the [data] by
  /// reading the next bit from the [address] and reading the new position from
  /// the [node] accordingly.
  Future<dynamic> _search(
    DataProvider data,
    int node,
    List<bool> address,
  ) async {
    final bytes = Uint8List(8);
    if (recordSize % 8 == 0) {
      final length = recordSize ~/ 8;

      bytes.setRange(
        8 - length,
        8,
        await data.readBytes(
          node * length * 2 + address[0] * length,
          node * length * 2 + length + address[0] * length,
        ),
      );
    } else {
      final length = recordSize / 8;
      final ceiledLength = length.ceil();
      final flooredLength = length.floor();
      if (!address[0]) {
        bytes.setRange(
          8 - flooredLength,
          8,
          await data.readBytes(
            (node * length * 2).floor(),
            (node * length * 2).floor() + flooredLength,
          ),
        );
        bytes[8 - length.ceil()] =
            await data[(node * length * 2).floor() + flooredLength] >>
                recordSize % 8;
      } else {
        bytes.setRange(
          8 - length.floor(),
          8,
          await data.readBytes(
            (node * length * 2).floor() + ceiledLength,
            (node * length * 2).floor() + ceiledLength + length.floor(),
          ),
        );
        bytes[8 - length.ceil()] =
            await data[(node * length * 2).floor() + length.floor()] &
                calculateMask(recordSize % 8);
      }
    }

    final location = ByteData.sublistView(bytes).getUint64(0);

    if (location > nodeCount) {
      final searchTreeSize = (recordSize / 4 * nodeCount).floor();

      return (await _decodeData(
        data,
        location - nodeCount + searchTreeSize,
        searchTreeSize + 16,
      ))
          .data;
    } else if (location == nodeCount) {
      return null;
    } else {
      return _search(data, location, address..removeAt(0));
    }
  }

  int calculateMask(int length) {
    var result = 0;
    for (var i = 0; i < length; i++) {
      result += pow(2, i).floor();
    }
    return result;
  }

  @Deprecated("Will be removed in 2.0.0")
  // ignore: library_private_types_in_public_api
  static Future<_Data> decodeData(
    DataProvider data,
    int position,
    int start,
  ) =>
      _decodeData(data, position, start);

  static Future<_Data> _decodeData(
    DataProvider data,
    int position,
    int start,
  ) async {
    var currentPosition = position;
    var type = await data[currentPosition] >> 5;
    var size = await data[currentPosition] & 0x1F;

    if (type != 1) {
      if (type == 0) {
        currentPosition++;
        type = await data[currentPosition] + 7;
      }

      currentPosition++; // first after type specifying bytes
      if (size < 29) {
        //payload size
      } else if (size == 29) {
        // If the value is 29, then the size is 29 + the next byte after the type specifying bytes as an unsigned integer.
        size = 29 + await data[currentPosition];
        currentPosition++;
      } else if (size == 30) {
        // If the value is 30, then the size is 285 + the next two bytes after the type specifying bytes as a single unsigned integer.
        size = 285 +
            (await data[currentPosition] << 8) +
            await data[currentPosition + 1];
        currentPosition += 2;
      } else if (size == 31) {
        // If the value is 31, then the size is 65,821 + the next three bytes after the type specifying bytes as a single unsigned integer.
        size = 65821 +
            (await data[currentPosition] << 16) +
            (await data[currentPosition + 1] << 8) +
            await data[currentPosition + 2];
        currentPosition += 3;
      }
    }

    switch (_DataType.get(type)) {
      case _Type.pointer:
        final pointerType = (await data[currentPosition] >> 3) & 0x3;

        var value = pointerType < 3 ? await data[currentPosition] & 0x7 : 0;
        for (var i = 0; i <= pointerType; i++) {
          currentPosition++;
          value = value << 8;
          value = value | await data[currentPosition];
        }

        switch (pointerType) {
          case 1:
            value += 2048;
            break;
          case 2:
            value += 526336;
            break;
        }

        return _Data(
          currentPosition + 1,
          (await _decodeData(data, start + value, start)).data,
        );
      case _Type.string:
        return _Data<String>(
          currentPosition + size,
          utf8.decode(
            await data.readBytes(currentPosition, currentPosition + size),
          ),
        );
      case _Type.double:
        assert(size == 8);

        final bytes = ByteData.sublistView(
          await data.readBytes(currentPosition, currentPosition + 8),
        );

        return _Data<double>(currentPosition + 8, bytes.getFloat64(0));
      case _Type.bytes:
        return _Data(
          currentPosition + size,
          await data.readBytes(currentPosition, currentPosition + size),
        );
      case _Type.uInt16:
        var value = BigInt.from(0);

        for (var i = 0; i < size; i++) {
          value = value << 8;
          value = value + BigInt.from(await data[currentPosition]);
          currentPosition++;
        }
        return _Data<int>(
          currentPosition,
          value.toUnsigned(16).toInt().toUnsigned(16),
        );
      case _Type.uInt32:
        var value = BigInt.from(0);

        for (var i = 0; i < size; i++) {
          value = value << 8;
          value = value + BigInt.from(await data[currentPosition]);
          currentPosition++;
        }
        return _Data<int>(
          currentPosition,
          value.toUnsigned(32).toInt().toUnsigned(32),
        );
      case _Type.map:
        final map = <String, dynamic>{};
        for (var i = 0; i < size; i++) {
          final key = await _decodeData(data, currentPosition, start);
          currentPosition = key.possitionAfter;
          final value = await _decodeData(data, currentPosition, start);
          currentPosition = value.possitionAfter;
          map[key.data as String] = value.data;
        }
        return _Data<Map<String, dynamic>>(currentPosition, map);
      case _Type.int32:
        var value = BigInt.from(0);

        for (var i = 0; i < size; i++) {
          value = value << 8;
          value = value + BigInt.from(await data[currentPosition]);
          currentPosition++;
        }
        return _Data<int>(currentPosition, value.toInt());
      case _Type.uInt64:
        var value = BigInt.from(0);

        for (var i = 0; i < size; i++) {
          value = value << 8;
          value = value + BigInt.from(await data[currentPosition]);
          currentPosition++;
        }
        return _Data<int>(
          currentPosition,
          value.toUnsigned(64).toInt().toUnsigned(64),
        );
      case _Type.uInt128:
        var value = BigInt.from(0);

        for (var i = 0; i < size; i++) {
          value = value << 8;
          value = value + BigInt.from(await data[currentPosition]);
          currentPosition++;
        }
        return _Data<BigInt>(currentPosition, value.toUnsigned(128));
      case _Type.array:
        final array = [];
        for (var i = 0; i < size; i++) {
          final value = await _decodeData(data, currentPosition, start);
          currentPosition = value.possitionAfter;
          array.add(value.data);
        }
        return _Data(currentPosition, array);
      case _Type.boolean:
        return _Data(currentPosition, size == 1);
      case _Type.float:
        assert(size == 4);
        return _Data(
          currentPosition + 4,
          ByteData.sublistView(
            await data.readBytes(currentPosition, currentPosition + 4),
          ).getFloat32(0),
        );
      default:
        return _Data(currentPosition, null);
    }
  }
}

extension on bool {
  int operator *(int value) {
    return this ? value : 0;
  }
}

extension on Uint8List {
  List<bool> get bits {
    return map((byte) {
      final res = <bool>[];
      for (var i = 0; i < 8; i++) {
        res.add((byte & (128 >> i)) > 0);
      }
      return res;
    }).fold([], (previousValue, element) => previousValue..addAll(element));
  }
}

class _Data<T> {
  final int possitionAfter;
  final T data;

  _Data(this.possitionAfter, this.data);
}

enum _Type {
  pointer,
  string,
  double,
  bytes,
  uInt16,
  uInt32,
  map,
  int32,
  uInt64,
  uInt128,
  array,
  boolean,
  float,
}

extension _DataType on _Type {
  static _Type? get(int i) {
    switch (i) {
      case 1:
        return _Type.pointer;
      case 2:
        return _Type.string;
      case 3:
        return _Type.double;
      case 4:
        return _Type.bytes;
      case 5:
        return _Type.uInt16;
      case 6:
        return _Type.uInt32;
      case 7:
        return _Type.map;
      case 8:
        return _Type.int32;
      case 9:
        return _Type.uInt64;
      case 10:
        return _Type.uInt128;
      case 11:
        return _Type.array;
      case 14:
        return _Type.boolean;
      case 15:
        return _Type.float;
    }
    return null;
  }
}

extension on DataProvider {
  // Future<int?> searchFirstSequence(List<int> sequence) async {
  //   var position = 0;
  //   for (var i = 0; i < await length; i++) {
  //     if (await this[i] == sequence[position]) {
  //       position++;
  //       if (position == sequence.length) {
  //         return i - position + 1;
  //       }
  //     } else {
  //       position = 0;
  //     }
  //   }
  //   return null;
  // }

  Future<int?> searchLastSequence(List<int> sequence) async {
    var position = sequence.length - 1;
    for (var i = await length - 1; i >= 0; i--) {
      if (await this[i] == sequence[position]) {
        position--;
        if (position == -1) {
          return i;
        }
      } else {
        position = sequence.length - 1;
      }
    }
    return null;
  }
}
