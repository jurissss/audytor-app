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

  const ReportResult({
    required this.bytes,
    required this.path,
    required this.filename,
  });
}

class ReportService {
  static const double _w = 1240;
  static const double _h = 1754;
  static const double _m = 82;

  static final DateFormat _dateTime = DateFormat('dd.MM.yyyy HH:mm');

  static Future<ReportResult> generate({
    required Site site,
    required Audit audit,
    required List<Defect> defects,
    required Map<int, List<AuditPhoto>> photos,
  }) async {
    final pdf = pw.Document();

    final cover = await _renderCover(site, audit, defects);
    _addRasterPage(pdf, cover);

    for (final defect in defects) {
      final defectPhotos = photos[defect.id] ?? const <AuditPhoto>[];
      final issuePhotos = defectPhotos.where((p) => !p.isResolution).toList();
      final resolutionPhotos = defectPhotos.where((p) => p.isResolution).toList();

      const perPage = 4;
      if (issuePhotos.isEmpty) {
        final page = await _renderDefectPage(defect, const [], 0, 1, resolution: false);
        _addRasterPage(pdf, page);
      } else {
        final pages = (issuePhotos.length / perPage).ceil();
        for (var i = 0; i < pages; i++) {
          final start = i * perPage;
          final end = (start + perPage).clamp(0, issuePhotos.length).toInt();
          final batch = issuePhotos.sublist(start, end);
          final page = await _renderDefectPage(defect, batch, i, pages, resolution: false);
          _addRasterPage(pdf, page);
        }
      }

      if (defect.resolutionNote.trim().isNotEmpty || resolutionPhotos.isNotEmpty) {
        if (resolutionPhotos.isEmpty) {
          final page = await _renderDefectPage(defect, const [], 0, 1, resolution: true);
          _addRasterPage(pdf, page);
        } else {
          final pages = (resolutionPhotos.length / perPage).ceil();
          for (var i = 0; i < pages; i++) {
            final start = i * perPage;
            final end = (start + perPage).clamp(0, resolutionPhotos.length).toInt();
            final batch = resolutionPhotos.sublist(start, end);
            final page = await _renderDefectPage(defect, batch, i, pages, resolution: true);
            _addRasterPage(pdf, page);
          }
        }
      }
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

  static Future<void> share(ReportResult report) async {
    await Printing.sharePdf(bytes: report.bytes, filename: report.filename);
  }

  static Future<void> printReport(ReportResult report) async {
    await Printing.layoutPdf(
      name: report.filename,
      onLayout: (_) async => report.bytes,
    );
  }

  static void _addRasterPage(pw.Document pdf, Uint8List pageImage) {
    final image = pw.MemoryImage(pageImage);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.SizedBox.expand(
          child: pw.Image(image, fit: pw.BoxFit.fill),
        ),
      ),
    );
  }

  static Future<Uint8List> _renderCover(
    Site site,
    Audit audit,
    List<Defect> defects,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, _w, _h));
    _paintBackground(canvas);

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, 250),
      Paint()..color = const Color(0xFF16324F),
    );

    _text(
      canvas,
      'RAPORT Z AUDYTU',
      const Rect.fromLTWH(_m, 82, _w - 2 * _m, 75),
      size: 52,
      weight: FontWeight.w700,
      color: Colors.white,
    );
    _text(
      canvas,
      audit.auditType,
      const Rect.fromLTWH(_m, 164, _w - 2 * _m, 48),
      size: 26,
      color: const Color(0xFFD9E7F5),
    );

    var y = 340.0;
    y = _labelValue(canvas, y, 'OBIEKT', site.name);
    if (site.code.trim().isNotEmpty) {
      y = _labelValue(canvas, y, 'NR / KOD OBIEKTU', site.code);
    }
    if (site.address.trim().isNotEmpty) {
      y = _labelValue(canvas, y, 'ADRES', site.address);
    }
    y = _labelValue(canvas, y, 'DATA ROZPOCZĘCIA', _dateTime.format(audit.startedAt));
    if (audit.completedAt != null) {
      y = _labelValue(canvas, y, 'DATA ZAKOŃCZENIA', _dateTime.format(audit.completedAt!));
    }
    y = _labelValue(canvas, y, 'AUDYTOR', audit.auditor);
    y = _labelValue(canvas, y, 'RAPORT WYGENEROWANO', _dateTime.format(DateTime.now()), compact: true);

    y += 24;
    _sectionTitle(canvas, y, 'PODSUMOWANIE');
    y += 70;

    final priorityCounts = <String, int>{};
    for (final d in defects) {
      priorityCounts[d.priority] = (priorityCounts[d.priority] ?? 0) + 1;
    }
    final resolvedCount = defects.where((d) => d.isResolved).length;
    final openCount = defects.length - resolvedCount;

    final boxes = <MapEntry<String, String>>[
      MapEntry('Usterki', defects.length.toString()),
      MapEntry('Usunięte', resolvedCount.toString()),
      MapEntry('Do usunięcia', openCount.toString()),
      MapEntry('Krytyczne', (priorityCounts['Krytyczny'] ?? 0).toString()),
    ];
    final boxGap = 22.0;
    final boxW = (_w - 2 * _m - boxGap * 3) / 4;
    for (var i = 0; i < boxes.length; i++) {
      final x = _m + i * (boxW + boxGap);
      final rect = Rect.fromLTWH(x, y, boxW, 150);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(18)),
        Paint()..color = const Color(0xFFF0F4F8),
      );
      _text(canvas, boxes[i].value, Rect.fromLTWH(x + 18, y + 26, boxW - 36, 58),
          size: 40, weight: FontWeight.w700, align: TextAlign.center);
      _text(canvas, boxes[i].key, Rect.fromLTWH(x + 12, y + 93, boxW - 24, 38),
          size: 20, color: const Color(0xFF526579), align: TextAlign.center);
    }

    y += 220;
    if (audit.notes.trim().isNotEmpty) {
      _sectionTitle(canvas, y, 'UWAGI DO AUDYTU');
      y += 60;
      _text(
        canvas,
        audit.notes,
        Rect.fromLTWH(_m, y, _w - 2 * _m, 190),
        size: 23,
        color: const Color(0xFF24364A),
        maxLines: 5,
      );
      y += 210;
    }

    _footer(canvas, 'Raport wygenerowany w aplikacji Audytor • zdjęcia pomniejszone dla mniejszego pliku PDF');
    return _pictureToJpeg(recorder);
  }

  static Future<Uint8List> _renderDefectPage(
    Defect defect,
    List<AuditPhoto> pagePhotos,
    int pageIndex,
    int totalPages, {
    required bool resolution,
  }) async {
    final decoded = <ui.Image>[];
    for (final photo in pagePhotos) {
      try {
        decoded.add(await _loadImage(photo.path));
      } catch (_) {
        // Uszkodzonego/nieistniejącego zdjęcia nie zatrzymujemy raportu.
      }
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, _w, _h));
    _paintBackground(canvas);

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, 170),
      Paint()..color = const Color(0xFF16324F),
    );
    _text(
      canvas,
      resolution ? 'POTWIERDZENIE USUNIĘCIA • ${defect.positionNo}' : 'POZYCJA ${defect.positionNo}',
      const Rect.fromLTWH(_m, 48, 760, 68),
      size: resolution ? 36 : 42,
      weight: FontWeight.w700,
      color: Colors.white,
    );
    _priorityChip(canvas, defect.priority, _w - _m - 270, 52);

    var y = 230.0;
    if (pageIndex == 0) {
      if (resolution) {
        y = _labelValue(
          canvas,
          y,
          'STATUS USTERKI',
          defect.isResolved ? 'USTERKA USUNIĘTA' : 'USTERKA DO USUNIĘCIA',
          compact: true,
          maxLines: 2,
        );
        if (defect.resolvedAt != null) {
          y = _labelValue(canvas, y, 'DATA USUNIĘCIA', _dateTime.format(defect.resolvedAt!), compact: true);
        }
        if (defect.resolutionNote.trim().isNotEmpty) {
          y = _labelValue(
            canvas,
            y,
            'KOMENTARZ PO USUNIĘCIU',
            defect.resolutionNote,
            compact: true,
            maxLines: 6,
          );
        }
      } else {
        y = _labelValue(
          canvas,
          y,
          'STATUS',
          defect.isResolved ? 'USUNIĘTA' : 'DO USUNIĘCIA',
          compact: true,
          maxLines: 2,
        );
        if (defect.location.trim().isNotEmpty) {
          y = _labelValue(canvas, y, 'LOKALIZACJA', defect.location, compact: true);
        }
        y = _labelValue(canvas, y, 'OPIS USTERKI', defect.description, compact: true, maxLines: 5);
        if (defect.recommendation.trim().isNotEmpty) {
          y = _labelValue(
            canvas,
            y,
            'ZALECENIE',
            defect.recommendation,
            compact: true,
            maxLines: 4,
          );
        }
      }
      y += 10;
    } else {
      _text(
        canvas,
        resolution
            ? 'Zdjęcia po usunięciu – ciąg dalszy (${pageIndex + 1}/$totalPages)'
            : 'Zdjęcia z audytu – ciąg dalszy (${pageIndex + 1}/$totalPages)',
        Rect.fromLTWH(_m, y, _w - 2 * _m, 45),
        size: 23,
        color: const Color(0xFF526579),
      );
      y += 70;
    }

    _sectionTitle(canvas, y, resolution ? 'ZDJĘCIA PO USUNIĘCIU USTERKI' : 'ZDJĘCIA Z AUDYTU');
    y += 64;

    final bottom = _h - 130;
    final availableH = bottom - y;
    if (decoded.isEmpty) {
      final rect = Rect.fromLTWH(_m, y, _w - 2 * _m, 420);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(16)),
        Paint()..color = const Color(0xFFF4F6F8),
      );
      _text(
        canvas,
        'Brak dostępnego pliku zdjęcia',
        Rect.fromLTWH(_m + 20, y + 180, _w - 2 * _m - 40, 50),
        size: 24,
        color: const Color(0xFF6B7785),
        align: TextAlign.center,
      );
    } else {
      const gap = 22.0;
      final columns = decoded.length == 1 ? 1 : 2;
      final rows = (decoded.length / columns).ceil();
      final cellW = (_w - 2 * _m - gap * (columns - 1)) / columns;
      final cellH = (availableH - gap * (rows - 1)) / rows;
      for (var i = 0; i < decoded.length; i++) {
        final col = i % columns;
        final row = i ~/ columns;
        final rect = Rect.fromLTWH(
          _m + col * (cellW + gap),
          y + row * (cellH + gap),
          cellW,
          cellH,
        );
        _drawPhoto(canvas, decoded[i], rect);
      }
    }

    _footer(canvas, '${resolution ? 'Potwierdzenie usunięcia • ' : ''}Pozycja ${defect.positionNo} • strona ${pageIndex + 1}/$totalPages • zdjęcia pomniejszone');
    final bytes = await _pictureToJpeg(recorder);
    for (final image in decoded) {
      image.dispose();
    }
    return bytes;
  }

  static void _paintBackground(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, _h),
      Paint()..color = Colors.white,
    );
  }

  static double _labelValue(
    Canvas canvas,
    double y,
    String label,
    String value, {
    bool compact = false,
    int maxLines = 3,
  }) {
    _text(
      canvas,
      label,
      Rect.fromLTWH(_m, y, 300, 32),
      size: 17,
      weight: FontWeight.w700,
      color: const Color(0xFF6A7A8C),
    );
    final h = _measureHeight(value, _w - 2 * _m, compact ? 25 : 29, maxLines);
    _text(
      canvas,
      value,
      Rect.fromLTWH(_m, y + 38, _w - 2 * _m, h + 8),
      size: compact ? 25 : 29,
      weight: FontWeight.w500,
      color: const Color(0xFF1B2B3D),
      maxLines: maxLines,
    );
    return y + 38 + h + (compact ? 28 : 42);
  }

  static void _sectionTitle(Canvas canvas, double y, String title) {
    canvas.drawRect(
      Rect.fromLTWH(_m, y + 11, 9, 34),
      Paint()..color = const Color(0xFF2D7DD2),
    );
    _text(
      canvas,
      title,
      Rect.fromLTWH(_m + 26, y, _w - 2 * _m - 26, 52),
      size: 25,
      weight: FontWeight.w700,
      color: const Color(0xFF24364A),
    );
  }

  static void _priorityChip(Canvas canvas, String priority, double x, double y) {
    final color = switch (priority) {
      'Krytyczny' => const Color(0xFFB42318),
      'Wysoki' => const Color(0xFFD97706),
      'Niski' => const Color(0xFF2E7D32),
      _ => const Color(0xFF2D7DD2),
    };
    final rect = Rect.fromLTWH(x, y, 270, 58);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(29)),
      Paint()..color = color,
    );
    _text(
      canvas,
      priority.toUpperCase(),
      Rect.fromLTWH(x + 14, y + 10, 242, 36),
      size: 20,
      weight: FontWeight.w700,
      color: Colors.white,
      align: TextAlign.center,
    );
  }

  static void _drawPhoto(Canvas canvas, ui.Image image, Rect target) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(target, const Radius.circular(16)),
      Paint()..color = const Color(0xFFF0F2F4),
    );
    final imageRatio = image.width / image.height;
    final targetRatio = target.width / target.height;
    late final double drawW;
    late final double drawH;
    if (imageRatio > targetRatio) {
      drawW = target.width;
      drawH = drawW / imageRatio;
    } else {
      drawH = target.height;
      drawW = drawH * imageRatio;
    }
    final dst = Rect.fromLTWH(
      target.left + (target.width - drawW) / 2,
      target.top + (target.height - drawH) / 2,
      drawW,
      drawH,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  static void _footer(Canvas canvas, String text) {
    canvas.drawLine(
      const Offset(_m, _h - 92),
      const Offset(_w - _m, _h - 92),
      Paint()
        ..color = const Color(0xFFE1E6EB)
        ..strokeWidth = 2,
    );
    _text(
      canvas,
      text,
      const Rect.fromLTWH(_m, _h - 75, _w - 2 * _m, 36),
      size: 16,
      color: const Color(0xFF7B8794),
      align: TextAlign.center,
    );
  }

  static void _text(
    Canvas canvas,
    String text,
    Rect rect, {
    double size = 24,
    FontWeight weight = FontWeight.w400,
    Color color = Colors.black,
    TextAlign align = TextAlign.left,
    int? maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1.25,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
      locale: const Locale('pl', 'PL'),
    )..layout(maxWidth: rect.width);
    painter.paint(canvas, Offset(rect.left, rect.top));
  }

  static double _measureHeight(String text, double width, double size, int maxLines) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, height: 1.25),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: width);
    return painter.height;
  }

  static Future<ui.Image> _loadImage(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static Future<Uint8List> _pictureToJpeg(ui.PictureRecorder recorder) async {
    final picture = recorder.endRecording();
    final image = await picture.toImage(_w.toInt(), _h.toInt());
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('Nie udało się wyrenderować strony raportu.');

    final decoded = img.decodePng(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    if (decoded == null) throw StateError('Nie udało się skompresować strony raportu.');
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 72));
  }

  static String _safe(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'[^a-zA-Z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ_-]+'), '_');
    return cleaned.isEmpty ? 'obiekt' : cleaned;
  }
}
