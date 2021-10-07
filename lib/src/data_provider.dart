import 'dart:io';

import 'dart:typed_data';

/// An abstraction of a byte store like a [File] or [Uint8List].
abstract class DataProvider {
  /// Read the first byte at this [position].
  Future<int> readByte(int position);

  ///Read the bytes from [start] to [end].
  Future<Uint8List> readBytes(int start, int end);

  /// Create a new [DataProvider].
  /// Used for sub classes.
  DataProvider.create();

  /// Create a new [DataProvider] based on a [file].
  factory DataProvider(File file) {
    return FileDataProvider(file);
  }

  /// Create a new [DataProvider] based on [data] that is in memory.
  factory DataProvider.memory(Uint8List data) {
    return MemoryDataProvider(data);
  }

  /// Read the first byte at this [position].
  Future<int> operator [](int position) => readByte(position);

  /// Get the length of this data.
  Future<int> get length;
}

/// A [DataProvider] that uses a [File] as an data store.
class FileDataProvider extends DataProvider {
  /// The file that contains the data.
  final RandomAccessFile _file;

  /// Create a new [FileDataProvider].
  FileDataProvider(File file)
      : _file = file.openSync(),
        super.create();

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

/// A [DataProvider] that stores the data in memory.
class MemoryDataProvider extends DataProvider {
  /// The data.
  final Uint8List _data;

  /// Create a new [MemoryDataProvider].
  MemoryDataProvider(this._data) : super.create();

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
