import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
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
  static const double _m = 52;
  static const int _defectsPerPage = 4;
  static final DateFormat _dateTime = DateFormat('dd.MM.yyyy HH:mm');

  static Future<ReportResult> generate({
    required Site site,
    required Audit audit,
    required List<Defect> defects,
    required Map<int, List<AuditPhoto>> photos,
    String? galleryHref,
  }) async {
    final pdf = pw.Document();
    final pages = defects.isEmpty ? 1 : (defects.length / _defectsPerPage).ceil();

    if (defects.isEmpty) {
      _addRasterPage(
        pdf,
        await _renderTablePage(
          site,
          audit,
          const <Defect>[],
          photos,
          pageNo: 1,
          pageCount: 1,
          totalDefects: 0,
        ),
      );
    } else {
      for (var start = 0; start < defects.length; start += _defectsPerPage) {
        final end = (start + _defectsPerPage).clamp(0, defects.length);
        _addRasterPage(
          pdf,
          await _renderTablePage(
            site,
            audit,
            defects.sublist(start, end),
            photos,
            pageNo: (start ~/ _defectsPerPage) + 1,
            pageCount: pages,
            totalDefects: defects.length,
          ),
        );
      }
    }

    // Każde zdjęcie ponad pierwsze 4 miniatury trafia na strony dodatkowe.
    for (final defect in defects) {
      final all = photos[defect.id] ?? const <AuditPhoto>[];
      if (all.length <= 4) continue;
      final remaining = all.sublist(4);

      for (var start = 0; start < remaining.length; start += 12) {
        final end = (start + 12).clamp(0, remaining.length);
        _addRasterPage(
          pdf,
          await _renderPhotoContinuation(
            defect,
            remaining.sublist(start, end),
            startIndex: start + 4,
            total: all.length,
          ),
        );
      }
    }

    if (galleryHref != null && galleryHref.trim().isNotEmpty) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(42),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Dokumentacja dodatkowa',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 14),
              pw.Text(
                'Paczka audytu zawiera także plik ZDJECIA.html oraz skompresowane zdjęcia w pełnym rozmiarze. Na telefonie najpewniejszy podgląd dużych zdjęć jest dostępny bezpośrednio w aplikacji Audytor.',
              ),
            ],
          ),
        ),
      );
    }

    final bytes = await pdf.save();
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'reports'));
    if (!await dir.exists()) await dir.create(recursive: true);

    final filename =
        'Audyt_${_safe(site.name)}_${DateFormat('yyyyMMdd_HHmm').format(audit.startedAt)}_aktualny_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes, flush: true);

    return ReportResult(bytes: bytes, path: file.path, filename: filename);
  }

  static Future<void> share(ReportResult report) {
    return Printing.sharePdf(bytes: report.bytes, filename: report.filename);
  }

  static Future<void> printReport(ReportResult report) {
    return Printing.layoutPdf(
      name: report.filename,
      onLayout: (_) async => report.bytes,
    );
  }

  static void _addRasterPage(pw.Document pdf, Uint8List image) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.SizedBox.expand(
          child: pw.Image(pw.MemoryImage(image), fit: pw.BoxFit.fill),
        ),
      ),
    );
  }

  static Future<Uint8List> _renderTablePage(
    Site site,
    Audit audit,
    List<Defect> defects,
    Map<int, List<AuditPhoto>> photos, {
    required int pageNo,
    required int pageCount,
    required int totalDefects,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, _w, _h));
    _background(canvas);

    _text(
      canvas,
      'Raport po audycie urządzeń chłodniczych',
      const Rect.fromLTWH(_m, 52, _w - 2 * _m, 55),
      size: 34,
      weight: FontWeight.w700,
      color: const Color(0xFF17283A),
    );

    var y = 118.0;
    y = _metaLine(canvas, y, 'Obiekt:', site.name);
    if (site.code.trim().isNotEmpty) {
      y = _metaLine(canvas, y, 'Kod obiektu:', site.code);
    }
    if (site.address.trim().isNotEmpty) {
      y = _metaLine(canvas, y, 'Adres:', site.address);
    }
    y = _metaLine(canvas, y, 'Audytor:', audit.auditor);
    y = _metaLine(canvas, y, 'Data:', _dateTime.format(audit.startedAt));
    y = _metaLine(canvas, y, 'Liczba usterek:', '$totalDefects');

    // Prawidłowa łączna liczba jest pokazywana w nagłówku stopki stron tabeli.
    final tableTop = 330.0;
    const headerH = 58.0;
    final tableW = _w - 2 * _m;

    const lpW = 62.0;
    const posW = 145.0;
    const devW = 215.0;
    const descW = 360.0;
    final photoW = tableW - lpW - posW - devW - descW;

    final widths = <double>[lpW, posW, devW, descW, photoW];
    final labels = <String>['Lp.', 'Pozycja', 'Nazwa urządzenia', 'Opis usterki', 'Zdjęcia'];

    canvas.drawRect(
      Rect.fromLTWH(_m, tableTop, tableW, headerH),
      Paint()..color = const Color(0xFF17283A),
    );

    var x = _m;
    for (var i = 0; i < labels.length; i++) {
      _text(
        canvas,
        labels[i],
        Rect.fromLTWH(x + 7, tableTop + 15, widths[i] - 14, 32),
        size: 15,
        weight: FontWeight.w700,
        color: Colors.white,
        align: i == 0 ? TextAlign.center : TextAlign.left,
        maxLines: 2,
      );
      x += widths[i];
    }

    final availableH = _h - tableTop - headerH - 94;
    final rowH = availableH / 4;

    for (var row = 0; row < 4; row++) {
      final rowTop = tableTop + headerH + row * rowH;
      final rowRect = Rect.fromLTWH(_m, rowTop, tableW, rowH);
      canvas.drawRect(
        rowRect,
        Paint()
          ..color = row.isEven ? Colors.white : const Color(0xFFF7F9FB),
      );
      canvas.drawRect(
        rowRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = const Color(0xFFBFC8D2),
      );

      var lineX = _m;
      for (final width in widths.take(widths.length - 1)) {
        lineX += width;
        canvas.drawLine(
          Offset(lineX, rowTop),
          Offset(lineX, rowTop + rowH),
          Paint()
            ..strokeWidth = 1
            ..color = const Color(0xFFCAD2DA),
        );
      }

      if (row >= defects.length) continue;
      final defect = defects[row];
      final all = photos[defect.id] ?? const <AuditPhoto>[];

      x = _m;
      _text(
        canvas,
        defect.positionNo,
        Rect.fromLTWH(x + 5, rowTop + 14, lpW - 10, 40),
        size: 15,
        align: TextAlign.center,
      );
      x += lpW;

      _text(
        canvas,
        defect.positionNo,
        Rect.fromLTWH(x + 8, rowTop + 14, posW - 16, rowH - 28),
        size: 15,
        weight: FontWeight.w600,
        maxLines: 4,
      );
      x += posW;

      _text(
        canvas,
        defect.location.trim().isEmpty ? '—' : defect.location,
        Rect.fromLTWH(x + 8, rowTop + 14, devW - 16, rowH - 28),
        size: 15,
        maxLines: 6,
      );
      x += devW;

      var desc = defect.description;
      if (defect.recommendation.trim().isNotEmpty) {
        desc += '\nZalecenie: ${defect.recommendation}';
      }
      if (defect.isResolved) {
        desc += '\n\nUSUNIĘTA';
        if (defect.resolvedAt != null) {
          desc += ' • ${_dateTime.format(defect.resolvedAt!)}';
        }
        if (defect.resolutionNote.trim().isNotEmpty) {
          desc += '\n${defect.resolutionNote}';
        }
      }

      _text(
        canvas,
        desc,
        Rect.fromLTWH(x + 8, rowTop + 14, descW - 16, rowH - 28),
        size: 14,
        color: const Color(0xFF24364A),
        maxLines: 10,
      );
      x += descW;

      final visible = all.take(4).toList();
      const gap = 7.0;
      final cellW = (photoW - 24 - gap) / 2;
      final cellH = (rowH - 28 - gap) / 2;

      for (var i = 0; i < 4; i++) {
        final col = i % 2;
        final rr = i ~/ 2;
        final rect = Rect.fromLTWH(
          x + 8 + col * (cellW + gap),
          rowTop + 10 + rr * (cellH + gap),
          cellW,
          cellH,
        );

        if (i >= visible.length) {
          _photo(canvas, null, rect, i == 0 ? 'BRAK' : '');
          continue;
        }

        final photo = visible[i];
        ui.Image? image;
        try {
          image = await _loadThumbnail(photo.path, width: 360);
        } catch (_) {}
        _photo(canvas, image, rect, _photoLabel(photo));
        image?.dispose();
      }

      if (all.length > 4) {
        _text(
          canvas,
          '+${all.length - 4} zdjęć na dalszych stronach',
          Rect.fromLTWH(x + 10, rowTop + rowH - 25, photoW - 20, 18),
          size: 10,
          weight: FontWeight.w700,
          color: const Color(0xFF16324F),
          align: TextAlign.center,
        );
      }
    }

    _footer(canvas, 'Strona $pageNo z $pageCount • Audytor 0.8.0');
    return _pictureToJpeg(recorder, quality: 72);
  }

  static double _metaLine(Canvas canvas, double y, String label, String value) {
    _text(
      canvas,
      label,
      Rect.fromLTWH(_m, y, 165, 28),
      size: 16,
      weight: FontWeight.w700,
      color: const Color(0xFF24364A),
    );
    _text(
      canvas,
      value,
      Rect.fromLTWH(_m + 165, y, _w - 2 * _m - 165, 28),
      size: 16,
      color: const Color(0xFF24364A),
      maxLines: 1,
    );
    return y + 31;
  }

  static String _photoLabel(AuditPhoto photo) => switch (photo.kind) {
        'resolution' => 'PO NAPRAWIE',
        'nameplate' => 'TABLICZKA',
        _ => 'USTERKA',
      };

  static Future<Uint8List> _renderPhotoContinuation(
    Defect defect,
    List<AuditPhoto> photos, {
    required int startIndex,
    required int total,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, _w, _h));
    _background(canvas);

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, 104),
      Paint()..color = const Color(0xFF17283A),
    );
    _text(
      canvas,
      'Zdjęcia • pozycja ${defect.positionNo}',
      const Rect.fromLTWH(_m, 29, 900, 48),
      size: 30,
      weight: FontWeight.w700,
      color: Colors.white,
    );

    const top = 140.0;
    const gap = 18.0;
    final availableW = _w - 2 * _m;
    final cellW = (availableW - gap * 2) / 3;
    const cellH = 340.0;

    for (var i = 0; i < photos.length; i++) {
      final col = i % 3;
      final row = i ~/ 3;
      final rect = Rect.fromLTWH(
        _m + col * (cellW + gap),
        top + row * (cellH + gap),
        cellW,
        cellH,
      );

      ui.Image? image;
      try {
        image = await _loadThumbnail(photos[i].path, width: 720);
      } catch (_) {}

      _photo(
        canvas,
        image,
        rect,
        '${startIndex + i + 1}/$total • ${_photoLabel(photos[i])}',
      );
      image?.dispose();
    }

    _footer(canvas, 'Pełna dokumentacja zdjęciowa • zachowane proporcje zdjęć');
    return _pictureToJpeg(recorder, quality: 68);
  }

  static void _photo(Canvas canvas, ui.Image? image, Rect rect, String label) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()..color = const Color(0xFFECEFF2),
    );

    if (image != null) {
      _drawContainedPhoto(canvas, image, rect);
    }

    if (label.isNotEmpty) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.bottom - 20, rect.width, 20),
        Paint()..color = const Color(0x99000000),
      );
      _text(
        canvas,
        label,
        Rect.fromLTWH(rect.left + 3, rect.bottom - 17, rect.width - 6, 14),
        size: 8,
        weight: FontWeight.w700,
        color: Colors.white,
        align: TextAlign.center,
        maxLines: 1,
      );
    }
  }

  static void _drawContainedPhoto(Canvas canvas, ui.Image image, Rect target) {
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

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(target, const Radius.circular(5)));
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  static void _background(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, _h),
      Paint()..color = Colors.white,
    );
  }

  static void _footer(Canvas canvas, String text) {
    canvas.drawLine(
      const Offset(_m, _h - 64),
      const Offset(_w - _m, _h - 64),
      Paint()
        ..color = const Color(0xFFE1E6EB)
        ..strokeWidth = 2,
    );
    _text(
      canvas,
      text,
      const Rect.fromLTWH(_m, _h - 49, _w - 2 * _m, 26),
      size: 13,
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
          height: 1.15,
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

  static Future<ui.Image> _loadThumbnail(String path, {int width = 520}) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: width,
      allowUpscaling: false,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static Future<Uint8List> _pictureToJpeg(
    ui.PictureRecorder recorder, {
    int quality = 70,
  }) async {
    final picture = recorder.endRecording();
    final image = await picture.toImage(_w.toInt(), _h.toInt());
    picture.dispose();

    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) {
      throw StateError('Nie udało się wyrenderować strony raportu.');
    }

    final decoded = img.decodePng(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    if (decoded == null) {
      throw StateError('Nie udało się skompresować strony raportu.');
    }

    return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
  }

  static String _safe(String input) {
    final cleaned = input.trim().replaceAll(
          RegExp(r'[^a-zA-Z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ_-]+'),
          '_',
        );
    return cleaned.isEmpty ? 'obiekt' : cleaned;
  }
}
