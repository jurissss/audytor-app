import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/audit.dart';
import '../models/audit_photo.dart';
import '../models/defect.dart';
import '../models/site.dart';

class ReportResult {
  final Uint8List bytes;
  final String path;
  final String filename;
  const ReportResult({required this.bytes, required this.path, required this.filename});
}

class ReportService {
  static const double _w = 1240;
  static const double _h = 1754;
  static const double _m = 58;
  static const int _defectsPerPage = 6;
  static final DateFormat _dateTime = DateFormat('dd.MM.yyyy HH:mm');

  static Future<ReportResult> generate({
    required Site site,
    required Audit audit,
    required List<Defect> defects,
    required Map<int, List<AuditPhoto>> photos,
  }) async {
    final pdf = pw.Document();
    _addRasterPage(pdf, await _renderCover(site, audit, defects));

    // KLUCZOWA ZMIANA: grupujemy USTERKI po 6, a nie zdjęcia jednej usterki.
    for (var start = 0; start < defects.length; start += _defectsPerPage) {
      final end = (start + _defectsPerPage).clamp(0, defects.length);
      final batch = defects.sublist(start, end);
      _addRasterPage(pdf, await _renderDefectsGrid(batch, photos));
    }

    final bytes = await pdf.save();
    final docs = await getApplicationDocumentsDirectory();
    final reports = Directory(p.join(docs.path, 'reports'));
    if (!await reports.exists()) await reports.create(recursive: true);
    final safeSite = _safe(site.name);
    final auditStamp = DateFormat('yyyyMMdd_HHmm').format(audit.startedAt);
    final generatedStamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filename = 'Audyt_${safeSite}_${auditStamp}_aktualny_$generatedStamp.pdf';
    final file = File(p.join(reports.path, filename));
    await file.writeAsBytes(bytes, flush: true);
    return ReportResult(bytes: bytes, path: file.path, filename: filename);
  }

  static Future<void> share(ReportResult report) async =>
      Printing.sharePdf(bytes: report.bytes, filename: report.filename);

  static Future<void> printReport(ReportResult report) async =>
      Printing.layoutPdf(name: report.filename, onLayout: (_) async => report.bytes);

  static void _addRasterPage(pw.Document pdf, Uint8List pageImage) {
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.SizedBox.expand(
        child: pw.Image(pw.MemoryImage(pageImage), fit: pw.BoxFit.fill),
      ),
    ));
  }

  static Future<Uint8List> _renderDefectsGrid(
    List<Defect> defects,
    Map<int, List<AuditPhoto>> photos,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, _w, _h));
    _paintBackground(canvas);

    canvas.drawRect(const Rect.fromLTWH(0, 0, _w, 118),
        Paint()..color = const Color(0xFF16324F));
    _text(canvas, 'USTERKI', const Rect.fromLTWH(_m, 34, 600, 52),
        size: 34, weight: FontWeight.w700, color: Colors.white);

    const gapX = 22.0, gapY = 22.0;
    final top = 148.0;
    final bottom = _h - 92;
    final cardW = (_w - 2 * _m - gapX) / 2;
    final cardH = (bottom - top - gapY * 2) / 3;

    for (var i = 0; i < defects.length; i++) {
      final d = defects[i];
      final col = i % 2, row = i ~/ 2;
      final rect = Rect.fromLTWH(
        _m + col * (cardW + gapX),
        top + row * (cardH + gapY),
        cardW, cardH,
      );

      ui.Image? issueImage;
      ui.Image? resolutionImage;
      final all = photos[d.id] ?? const <AuditPhoto>[];
      final issue = all.where((x) => !x.isResolution).toList();
      final resolution = all.where((x) => x.isResolution).toList();
      try { if (issue.isNotEmpty) issueImage = await _loadThumbnail(issue.first.path); } catch (_) {}
      try { if (resolution.isNotEmpty) resolutionImage = await _loadThumbnail(resolution.first.path); } catch (_) {}

      _drawDefectCard(canvas, rect, d, issueImage, resolutionImage, issue.length, resolution.length);
      issueImage?.dispose();
      resolutionImage?.dispose();
    }

    _footer(canvas, '6 usterek na stronie • zdjęcia w PDF są miniaturami');
    return _pictureToJpeg(recorder, quality: 68);
  }

  static void _drawDefectCard(
    Canvas canvas, Rect r, Defect d, ui.Image? issue, ui.Image? resolution,
    int issueCount, int resolutionCount,
  ) {
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(16)),
        Paint()..color = const Color(0xFFF7F9FB));
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(16)),
        Paint()..color = const Color(0xFFDDE4EB)..style = PaintingStyle.stroke..strokeWidth = 2);

    final chipColor = switch (d.priority) {
      'Krytyczny' => const Color(0xFFB42318),
      'Wysoki' => const Color(0xFFD97706),
      'Niski' => const Color(0xFF2E7D32),
      _ => const Color(0xFF2D7DD2),
    };
    _text(canvas, 'Poz. ${d.positionNo}', Rect.fromLTWH(r.left + 16, r.top + 14, 210, 34),
        size: 22, weight: FontWeight.w700);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(r.right - 150, r.top + 12, 134, 34), const Radius.circular(17)),
      Paint()..color = chipColor,
    );
    _text(canvas, d.priority, Rect.fromLTWH(r.right - 144, r.top + 17, 122, 24),
        size: 14, weight: FontWeight.w700, color: Colors.white, align: TextAlign.center);

    final photoTop = r.top + 58;
    final photoH = 190.0;
    final photoW = resolution != null ? (r.width - 44) / 2 : r.width - 32;
    final firstRect = Rect.fromLTWH(r.left + 16, photoTop, photoW, photoH);
    _photoOrPlaceholder(canvas, issue, firstRect, issueCount == 0 ? 'Brak zdjęcia' : 'Zdjęcie usterki');
    if (resolution != null) {
      final secondRect = Rect.fromLTWH(firstRect.right + 12, photoTop, photoW, photoH);
      _photoOrPlaceholder(canvas, resolution, secondRect, 'Po usunięciu');
    }

    var y = photoTop + photoH + 12;
    if (d.location.trim().isNotEmpty) {
      _text(canvas, 'Lokalizacja: ${d.location}', Rect.fromLTWH(r.left + 16, y, r.width - 32, 38),
          size: 16, weight: FontWeight.w600, maxLines: 1);
      y += 34;
    }
    _text(canvas, d.description, Rect.fromLTWH(r.left + 16, y, r.width - 32, 72),
        size: 17, color: const Color(0xFF24364A), maxLines: 3);
    y += 78;

    final status = d.isResolved ? 'USUNIĘTA' : 'DO USUNIĘCIA';
    final statusColor = d.isResolved ? const Color(0xFF2E7D32) : const Color(0xFFB42318);
    _text(canvas, status, Rect.fromLTWH(r.left + 16, y, 170, 30),
        size: 15, weight: FontWeight.w700, color: statusColor);

    if (d.isResolved && d.resolvedAt != null) {
      _text(canvas, _dateTime.format(d.resolvedAt!), Rect.fromLTWH(r.left + 190, y, r.width - 206, 30),
          size: 14, color: const Color(0xFF526579), align: TextAlign.right);
    }
    if (d.isResolved && d.resolutionNote.trim().isNotEmpty) {
      _text(canvas, 'Po naprawie: ${d.resolutionNote}',
          Rect.fromLTWH(r.left + 16, y + 30, r.width - 32, 46),
          size: 14, color: const Color(0xFF526579), maxLines: 2);
    }
  }

  static void _photoOrPlaceholder(Canvas canvas, ui.Image? image, Rect r, String label) {
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)),
        Paint()..color = const Color(0xFFECEFF2));
    if (image != null) {
      _drawPhoto(canvas, image, r);
    } else {
      _text(canvas, label, Rect.fromLTWH(r.left + 8, r.top + r.height/2 - 12, r.width - 16, 28),
          size: 14, color: const Color(0xFF7B8794), align: TextAlign.center);
    }
  }

  static Future<Uint8List> _renderCover(Site site, Audit audit, List<Defect> defects) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, _w, _h));
    _paintBackground(canvas);
    canvas.drawRect(const Rect.fromLTWH(0, 0, _w, 250), Paint()..color = const Color(0xFF16324F));
    _text(canvas, 'RAPORT Z AUDYTU', const Rect.fromLTWH(82, 82, 1076, 75),
        size: 52, weight: FontWeight.w700, color: Colors.white);
    _text(canvas, audit.auditType, const Rect.fromLTWH(82, 164, 1076, 48),
        size: 26, color: const Color(0xFFD9E7F5));
    var y = 340.0;
    y = _labelValue(canvas, y, 'OBIEKT', site.name);
    if (site.code.trim().isNotEmpty) y = _labelValue(canvas, y, 'NR / KOD OBIEKTU', site.code);
    if (site.address.trim().isNotEmpty) y = _labelValue(canvas, y, 'ADRES', site.address);
    y = _labelValue(canvas, y, 'DATA ROZPOCZĘCIA', _dateTime.format(audit.startedAt));
    if (audit.completedAt != null) y = _labelValue(canvas, y, 'DATA ZAKOŃCZENIA', _dateTime.format(audit.completedAt!));
    y = _labelValue(canvas, y, 'AUDYTOR', audit.auditor);
    y += 25;
    _text(canvas, 'Usterki: ${defects.length}   •   Usunięte: ${defects.where((d)=>d.isResolved).length}',
        Rect.fromLTWH(82, y, 1076, 55), size: 27, weight: FontWeight.w700);
    _footer(canvas, 'Raport wygenerowany w aplikacji Audytor • wersja układu 6 usterek / strona');
    return _pictureToJpeg(recorder, quality: 70);
  }

  static double _labelValue(Canvas canvas, double y, String label, String value) {
    _text(canvas, label, Rect.fromLTWH(82, y, 300, 30), size: 17,
        weight: FontWeight.w700, color: const Color(0xFF6A7A8C));
    _text(canvas, value, Rect.fromLTWH(82, y + 38, 1076, 70), size: 28,
        weight: FontWeight.w500, color: const Color(0xFF1B2B3D), maxLines: 2);
    return y + 118;
  }

  static void _paintBackground(Canvas canvas) =>
      canvas.drawRect(const Rect.fromLTWH(0, 0, _w, _h), Paint()..color = Colors.white);

  static void _drawPhoto(Canvas canvas, ui.Image image, Rect target) {
    final ir = image.width / image.height, tr = target.width / target.height;
    double sw, sh, sx, sy;
    if (ir > tr) {
      sh = image.height.toDouble(); sw = sh * tr;
      sx = (image.width - sw) / 2; sy = 0;
    } else {
      sw = image.width.toDouble(); sh = sw / tr;
      sx = 0; sy = (image.height - sh) / 2;
    }
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(target, const Radius.circular(10)));
    canvas.drawImageRect(image, Rect.fromLTWH(sx, sy, sw, sh), target,
        Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  static void _footer(Canvas canvas, String text) {
    canvas.drawLine(const Offset(_m, _h - 70), const Offset(_w - _m, _h - 70),
        Paint()..color = const Color(0xFFE1E6EB)..strokeWidth = 2);
    _text(canvas, text, const Rect.fromLTWH(_m, _h - 55, _w - 2 * _m, 30),
        size: 14, color: const Color(0xFF7B8794), align: TextAlign.center);
  }

  static void _text(Canvas canvas, String text, Rect rect, {
    double size = 24, FontWeight weight = FontWeight.w400, Color color = Colors.black,
    TextAlign align = TextAlign.left, int? maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, fontWeight: weight, color: color, height: 1.18)),
      textDirection: ui.TextDirection.ltr, textAlign: align, maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…', locale: const Locale('pl','PL'),
    )..layout(maxWidth: rect.width);
    painter.paint(canvas, Offset(rect.left, rect.top));
  }

  static Future<ui.Image> _loadThumbnail(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 520, targetHeight: 360);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static Future<Uint8List> _pictureToJpeg(ui.PictureRecorder recorder, {int quality = 68}) async {
    final picture = recorder.endRecording();
    final image = await picture.toImage(_w.toInt(), _h.toInt());
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('Nie udało się wyrenderować strony raportu.');
    final decoded = img.decodePng(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    if (decoded == null) throw StateError('Nie udało się skompresować strony raportu.');
    return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
  }

  static String _safe(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'[^a-zA-Z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ_-]+'), '_');
    return cleaned.isEmpty ? 'obiekt' : cleaned;
  }
}
