import 'dart:io';

import 'dart:typed_data';

abstract class DataProvider {
  Future<int> readByte(int position);
  Future<Uint8List> readBytes(int start, int end);

  DataProvider._();

  factory DataProvider(File file) {
    return _FileDataProvider(file);
  }

  factory DataProvider.memory(Uint8List data) {
    return _MemoryDataProvider(data);
  }

  Future<int> operator [](int position) => readByte(position);

  Future<int> get length;
}

class _FileDataProvider extends DataProvider {
  final RandomAccessFile _file;

  _FileDataProvider._(this._file) : super._();

  factory _FileDataProvider(File file) {
    return _FileDataProvider._(file.openSync());
  }

  @override
  Future<int> readByte(int position) async {
    await _file.setPosition(position);
    return _file.readByte();
  }

  @override
  Future<Uint8List> readBytes(int start, int end) async {
    await _file.setPosition(start);
    return _file.read(end - start);
  }

  @override
  Future<int> get length => _file.length();
}

class _MemoryDataProvider extends DataProvider {
  final Uint8List _data;

  _MemoryDataProvider(this._data) : super._();

  @override
  Future<int> readByte(int position) async {
    return _data[position];
  }

  @override
  Future<Uint8List> readBytes(int start, int end) async {
    return _data.sublist(start, end);
  }

  @override
  Future<int> get length async => _data.length;
}
