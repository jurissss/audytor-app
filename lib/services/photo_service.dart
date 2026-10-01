import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PhotoService {
  static final ImagePicker _picker = ImagePicker();

  static Future<XFile?> takePhoto() {
    return _picker.pickImage(source: ImageSource.camera, imageQuality: 95, maxWidth: 3000);
  }

  static Future<List<XFile>> pickFromGallery() {
    return _picker.pickMultiImage(imageQuality: 95, maxWidth: 3000);
  }

  static Future<String> persistPickedFile(XFile source) async {
    final bytes = await File(source.path).readAsBytes();
    return persistBytes(_compressForStorage(bytes), prefix: 'photo');
  }

  static Future<String> persistBytes(Uint8List bytes, {String prefix = 'photo'}) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'audit_photos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${prefix}_${DateTime.now().microsecondsSinceEpoch}.jpg'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<Uint8List> compressForEmailPackage(String sourcePath, {required int targetBytes}) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    var working = img.bakeOrientation(decoded);
    const dimensions = <int>[1600,1450,1300,1150,1000,900,800,700];
    const qualities = <int>[74,66,58,50,44,38,32];
    Uint8List? best;
    for (final dimension in dimensions) {
      working = _resizeToMax(working, dimension);
      for (final quality in qualities) {
        final encoded = Uint8List.fromList(img.encodeJpg(working, quality: quality));
        best = encoded;
        if (encoded.length <= targetBytes) return encoded;
      }
    }
    return best ?? bytes;
  }

  static Uint8List _compressForStorage(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    var working = img.bakeOrientation(decoded);
    working = _resizeToMax(working, 1920);
    for (final quality in const <int>[78,70,62]) {
      final encoded = Uint8List.fromList(img.encodeJpg(working, quality: quality));
      if (encoded.length <= 650 * 1024 || quality == 62) {
        if (encoded.length <= 850 * 1024) return encoded;
        working = _resizeToMax(working, 1600);
        return Uint8List.fromList(img.encodeJpg(working, quality: 64));
      }
    }
    return bytes;
  }

  static img.Image _resizeToMax(img.Image source, int maxDimension) {
    final longest = source.width > source.height ? source.width : source.height;
    if (longest <= maxDimension) return source;
    if (source.width >= source.height) {
      return img.copyResize(source, width: maxDimension, interpolation: img.Interpolation.average);
    }
    return img.copyResize(source, height: maxDimension, interpolation: img.Interpolation.average);
  }

  static Future<void> deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
