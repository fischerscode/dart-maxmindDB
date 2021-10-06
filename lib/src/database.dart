import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'dart:typed_data';

import 'data_provider.dart';
import 'package:extendedip/extendedip.dart';

class MaxMindDatabase {
  final int node_count;
  final int record_size;
  final int ip_version;
  final String database_type;
  final List<String> languages;
  final int binary_format_major_version;
  final int binary_format_minor_version;
  final int build_epoch;
  final Map<String, String> description;
  final DataProvider data;

  MaxMindDatabase._({
    required this.node_count,
    required this.record_size,
    required this.ip_version,
    required this.database_type,
    required this.languages,
    required this.binary_format_major_version,
    required this.binary_format_minor_version,
    required this.build_epoch,
    required this.description,
    required this.data,
  });

  static Future<MaxMindDatabase> file(File file) {
    return MaxMindDatabase.dataProvider(DataProvider(file));
  }

  static Future<MaxMindDatabase> memory(Uint8List data) {
    return MaxMindDatabase.dataProvider(DataProvider.memory(data));
  }

  static Future<MaxMindDatabase> dataProvider(DataProvider data) async {
    var METADATA_BEGIN_MARKER =
        [0xAB, 0xCD, 0xEF] + ascii.encoder.convert('MaxMind.com');

    var metaDataStart = (await data.searchLastSequence(METADATA_BEGIN_MARKER))!;

    Map<dynamic, dynamic> meta = (await decodeData(
            data, metaDataStart + METADATA_BEGIN_MARKER.length, metaDataStart))
        .data;

    return MaxMindDatabase._(
      data: data,
      binary_format_major_version: meta['binary_format_major_version'],
      binary_format_minor_version: meta['binary_format_minor_version'],
      build_epoch: meta['build_epoch'],
      database_type: meta['database_type'],
      description: (meta['description'] as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, value as String)),
      ip_version: meta['ip_version'],
      languages:
          (meta['languages'] as List<dynamic>).map((e) => e as String).toList(),
      node_count: meta['node_count'],
      record_size: meta['record_size'],
    );
  }

  Future<dynamic?> search(String address) {
    return searchAddress(InternetAddress(address));
  }

  Future<dynamic?> searchAddress(InternetAddress address) {
    if (address.type == InternetAddressType.IPv4 && ip_version == 6) {
      return searchAddress(address.toIPv6());
    }

    if (address.type == InternetAddressType.IPv6 && ip_version == 4) {
      throw Exception(
          "An IPv6 address can't be processed by this IPv4 database.");
    }

    return _search(data, 0, address.rawAddress.bits);
  }

  Future<dynamic> _search(
      DataProvider data, int node, List<bool> address) async {
    var bytes = Uint8List(8);
    if (record_size % 8 == 0) {
      var length = record_size ~/ 8;

      bytes.setRange(
          8 - length,
          8,
          await data.readBytes(node * length * 2 + address[0] * length,
              node * length * 2 + length + address[0] * length));
    } else {
      var length = record_size / 8;
      var ceiledLength = length.ceil();
      var flooredLength = length.floor();
      if (!address[0]) {
        bytes.setRange(
            8 - flooredLength,
            8,
            await data.readBytes((node * length * 2).floor(),
                (node * length * 2).floor() + flooredLength));
        bytes[8 - length.ceil()] =
            await data[(node * length * 2).floor() + flooredLength] >>
                record_size % 8;
      } else {
        bytes.setRange(
            8 - length.floor(),
            8,
            await data.readBytes((node * length * 2).floor() + length.ceil(),
                (node * length * 2).floor() + length.ceil() + length.floor()));
        bytes[8 - length.ceil()] =
            await data[(node * length * 2).floor() + length.floor()] &
                calculateMask(record_size % 8);
      }
    }

    var location = ByteData.sublistView(bytes).getUint64(0);

    if (location > node_count) {
      var search_tree_size = (record_size / 4 * node_count).floor();

      return (await decodeData(data, location - node_count + search_tree_size,
              search_tree_size + 16))
          .data;
    } else if (location == node_count) {
      return null;
    } else {
      return _search(data, location, address..removeAt(0));
    }
  }

  int calculateMask(var length) {
    var result = 0;
    for (var i = 0; i < length; i++) {
      result += pow(2, i).floor();
    }
    return result;
  }

  static Future<Data> decodeData(
      DataProvider data, int position, int start) async {
    var type = await data[position] >> 5;
    var size = await data[position] & 0x1F;

    if (type != 1) {
      if (type == 0) {
        position++;
        type = await data[position] + 7;
      }

      position++; // first after type specifying bytes
      if (size < 29) {
        //payload size
      } else if (size == 29) {
        // If the value is 29, then the size is 29 + the next byte after the type specifying bytes as an unsigned integer.
        size = 29 + await data[position];
        position++;
      } else if (size == 30) {
        // If the value is 30, then the size is 285 + the next two bytes after the type specifying bytes as a single unsigned integer.
        size = 285 + (await data[position] << 8) + await data[position + 1];
        position += 2;
      } else if (size == 31) {
        // If the value is 31, then the size is 65,821 + the next three bytes after the type specifying bytes as a single unsigned integer.
        size = 65821 +
            (await data[position] << 16) +
            (await data[position + 1] << 8) +
            await data[position + 2];
        position += 3;
      }
    }

    switch (_DataType.get(type)) {
      case _Type.Pointer:
        var pointerType = ((await data[position] >> 3) & 0x3);

        var value = pointerType < 3 ? await data[position] & 0x7 : 0;
        for (var i = 0; i <= pointerType; i++) {
          position++;
          value = value << 8;
          value = value | await data[position];
        }

        switch (pointerType) {
          case 1:
            value += 2048;
            break;
          case 2:
            value += 526336;
            break;
        }

        return Data(
            position + 1, (await decodeData(data, start + value, start)).data);
      case _Type.String:
        return Data(position + size,
            utf8.decode(await data.readBytes(position, position + size)));
      case _Type.Double:
        assert(size == 8);

        var bytes =
            ByteData.sublistView(await data.readBytes(position, position + 8));

        return Data(position + 8, bytes.getFloat64(0));
      case _Type.Bytes:
        return Data(
            position + size, await data.readBytes(position, position + size));
      case _Type.uInt16:
        var value = BigInt.from(0);

        for (var i = 0; i < size; i++) {
          value = value << 8;
          value = value + BigInt.from(await data[position]);
          position++;
        }
        return Data(position, value.toUnsigned(16).toInt().toUnsigned(16));
      case _Type.uInt32:
        var value = BigInt.from(0);

        for (var i = 0; i < size; i++) {
          value = value << 8;
          value = value + BigInt.from(await data[position]);
          position++;
        }
        return Data(position, value.toUnsigned(32).toInt().toUnsigned(32));
      case _Type.Map:
        var map = <String, dynamic>{};
        for (var i = 0; i < size; i++) {
          var key = await decodeData(data, position, start);
          position = key.possitionAfter;
          var value = await decodeData(data, position, start);
          position = value.possitionAfter;
          map[key.data] = value.data;
        }
        return Data(position, map);
      case _Type.Int32:
        var value = BigInt.from(0);

        for (var i = 0; i < size; i++) {
          value = value << 8;
          value = value + BigInt.from(await data[position]);
          position++;
        }
        return Data(position, value.toInt());
      case _Type.uInt64:
        var value = BigInt.from(0);

        for (var i = 0; i < size; i++) {
          value = value << 8;
          value = value + BigInt.from(await data[position]);
          position++;
        }
        return Data(position, value.toUnsigned(64).toInt().toUnsigned(64));
      case _Type.uInt128:
        var value = BigInt.from(0);

        for (var i = 0; i < size; i++) {
          value = value << 8;
          value = value + BigInt.from(await data[position]);
          position++;
        }
        return Data(position, value.toUnsigned(128));
      case _Type.Array:
        var array = [];
        for (var i = 0; i < size; i++) {
          var value = await decodeData(data, position, start);
          position = value.possitionAfter;
          array.add(value.data);
        }
        return Data(position, array);
      case _Type.Boolean:
        return Data(position, size == 1);
      case _Type.Float:
        assert(size == 4);
        return Data(
            position + 4,
            ByteData.sublistView(await data.readBytes(position, position + 4))
                .getFloat32(0));
      default:
        return Data(position, null);
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
      var res = <bool>[];
      for (var i = 0; i < 8; i++) {
        res.add((byte & (128 >> i)) > 0);
      }
      return res;
    }).fold([], (previousValue, element) => previousValue..addAll(element));
  }
}

class Data<T> {
  final int possitionAfter;
  final T data;

  Data(this.possitionAfter, this.data);
}

enum _Type {
  Pointer,
  String,
  Double,
  Bytes,
  uInt16,
  uInt32,
  Map,
  Int32,
  uInt64,
  uInt128,
  Array,
  Boolean,
  Float,
}

extension _DataType on _Type {
  static _Type? get(int i) {
    switch (i) {
      case 1:
        return _Type.Pointer;
      case 2:
        return _Type.String;
      case 3:
        return _Type.Double;
      case 4:
        return _Type.Bytes;
      case 5:
        return _Type.uInt16;
      case 6:
        return _Type.uInt32;
      case 7:
        return _Type.Map;
      case 8:
        return _Type.Int32;
      case 9:
        return _Type.uInt64;
      case 10:
        return _Type.uInt128;
      case 11:
        return _Type.Array;
      case 14:
        return _Type.Boolean;
      case 15:
        return _Type.Float;
    }
  }
}

extension on DataProvider {
  Future<int?> searchFirstSequence(List<int> sequence) async {
    var position = 0;
    for (var i = 0; i < await length; i++) {
      if (await this[i] == sequence[position]) {
        position++;
        if (position == sequence.length) {
          return i - position + 1;
        }
      } else {
        position = 0;
      }
    }
    return null;
  }

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
