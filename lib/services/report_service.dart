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
  static const double _m = 42;
  static const int _defectsPerPage = 4;
  static const int _mainPhotosPerDefect = 6;
  static final DateFormat _dateTime = DateFormat('dd.MM.yyyy HH:mm');

  static Future<ReportResult> generate({
    required Site site,
    required Audit audit,
    required List<Defect> defects,
    required Map<int, List<AuditPhoto>> photos,
    String? galleryHref,
  }) async {
    final pdf = pw.Document();

    final pageCount = defects.isEmpty
        ? 1
        : (defects.length / _defectsPerPage).ceil();

    if (defects.isEmpty) {
      final page = await _renderTablePage(
        site,
        audit,
        const <Defect>[],
        photos,
        startIndex: 0,
        pageNo: 1,
        pageCount: 1,
        totalDefects: 0,
      );
      await _addCompositePage(pdf, page);
    } else {
      for (var start = 0;
          start < defects.length;
          start += _defectsPerPage) {
        final end = (start + _defectsPerPage).clamp(0, defects.length);
        final page = await _renderTablePage(
          site,
          audit,
          defects.sublist(start, end),
          photos,
          startIndex: start,
          pageNo: (start ~/ _defectsPerPage) + 1,
          pageCount: pageCount,
          totalDefects: defects.length,
        );
        await _addCompositePage(pdf, page);
      }
    }

    // Pełna dokumentacja zdjęciowa na końcu raportu.
    // Każda miniatura z tabeli prowadzi do dużego zdjęcia na osobnej stronie.
    for (final defect in defects) {
      final ordered = _orderedPhotos(
        photos[defect.id] ?? const <AuditPhoto>[],
      );

      for (var i = 0; i < ordered.length; i++) {
        await _addLargePhotoPage(
          pdf,
          defect: defect,
          photo: ordered[i],
          photoNumber: i + 1,
          totalPhotos: ordered.length,
        );
      }
    }

    if (galleryHref != null && galleryHref.trim().isNotEmpty) {
      // Celowo nie dodajemy lokalnych linków do plików z ZIP-a.
      // Na Androidzie były one zawodne. Wszystkie zdjęcia są już w PDF.
    }

    final bytes = await pdf.save();
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'reports'));
    if (!await dir.exists()) await dir.create(recursive: true);

    final filename =
        'Audyt_${_safe(site.name)}_${DateFormat('yyyyMMdd_HHmm').format(audit.startedAt)}_aktualny_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes, flush: true);

    return ReportResult(
      bytes: bytes,
      path: file.path,
      filename: filename,
    );
  }

  static Future<void> share(ReportResult report) {
    return Printing.sharePdf(
      bytes: report.bytes,
      filename: report.filename,
    );
  }

  static Future<void> printReport(ReportResult report) {
    return Printing.layoutPdf(
      name: report.filename,
      onLayout: (_) async => report.bytes,
    );
  }

  static Future<void> _addCompositePage(
    pw.Document pdf,
    _RenderedPage page,
  ) async {
    final overlays = <_PdfOverlay>[];

    for (final overlay in page.overlays) {
      try {
        final bytes = await _preparePdfPhoto(overlay.path);
        overlays.add(
          _PdfOverlay(
            rect: overlay.rect,
            bytes: bytes,
            destination: overlay.destination,
          ),
        );
      } catch (_) {
        // Uszkodzone lub usunięte zdjęcie nie blokuje całego raportu.
      }
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) {
          final sx = PdfPageFormat.a4.width / _w;
          final sy = PdfPageFormat.a4.height / _h;

          return pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.Image(
                  pw.MemoryImage(page.background),
                  fit: pw.BoxFit.fill,
                ),
              ),
              ...page.anchors.map(
                (anchor) => pw.Positioned(
                  left: anchor.x * sx,
                  top: anchor.y * sy,
                  child: pw.Anchor(
                    name: anchor.name,
                    child: pw.SizedBox(width: 1, height: 1),
                  ),
                ),
              ),
              ...overlays.map(
                (overlay) => pw.Positioned(
                  left: overlay.rect.left * sx,
                  top: overlay.rect.top * sy,
                  right: PdfPageFormat.a4.width -
                      ((overlay.rect.left + overlay.rect.width) * sx),
                  bottom: PdfPageFormat.a4.height -
                      ((overlay.rect.top + overlay.rect.height) * sy),
                  child: pw.Link(
                    destination: overlay.destination,
                    child: pw.Container(
                      alignment: pw.Alignment.center,
                      child: pw.Image(
                        pw.MemoryImage(overlay.bytes),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<_RenderedPage> _renderTablePage(
    Site site,
    Audit audit,
    List<Defect> defects,
    Map<int, List<AuditPhoto>> photos, {
    required int startIndex,
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
      const Rect.fromLTWH(_m, 42, _w - 2 * _m, 52),
      size: 32,
      weight: FontWeight.w700,
      color: const Color(0xFF17283A),
    );

    var y = 104.0;
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

    const tableTop = 300.0;
    const headerH = 52.0;
    final tableW = _w - 2 * _m;

    const lpW = 56.0;
    const posW = 125.0;
    const devW = 205.0;
    const descW = 330.0;
    final photoW = tableW - lpW - posW - devW - descW;

    final widths = <double>[lpW, posW, devW, descW, photoW];
    const labels = <String>[
      'Lp.',
      'Pozycja',
      'Nazwa urządzenia',
      'Opis usterki',
      'Zdjęcia',
    ];

    canvas.drawRect(
      Rect.fromLTWH(_m, tableTop, tableW, headerH),
      Paint()..color = const Color(0xFF17283A),
    );

    var x = _m;
    for (var i = 0; i < labels.length; i++) {
      _text(
        canvas,
        labels[i],
        Rect.fromLTWH(x + 6, tableTop + 13, widths[i] - 12, 32),
        size: 14,
        weight: FontWeight.w700,
        color: Colors.white,
        align: i == 0 ? TextAlign.center : TextAlign.left,
        maxLines: 2,
      );
      x += widths[i];
    }

    final availableH = _h - tableTop - headerH - 78;
    final rowH = availableH / _defectsPerPage;
    final overlays = <_PhotoOverlay>[];
    final anchors = <_PageAnchor>[];

    for (var row = 0; row < _defectsPerPage; row++) {
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
          ..strokeWidth = 1.2
          ..color = const Color(0xFFB8C3CE),
      );

      var lineX = _m;
      for (final width in widths.take(widths.length - 1)) {
        lineX += width;
        canvas.drawLine(
          Offset(lineX, rowTop),
          Offset(lineX, rowTop + rowH),
          Paint()
            ..strokeWidth = 1
            ..color = const Color(0xFFC5CED7),
        );
      }

      if (row >= defects.length) continue;

      final defect = defects[row];
      anchors.add(
        _PageAnchor(
          name: _defectAnchor(defect),
          x: _m + lpW,
          y: rowTop + 4,
        ),
      );

      final ordered = _orderedPhotos(
        photos[defect.id] ?? const <AuditPhoto>[],
      );
      final visible = ordered.take(_mainPhotosPerDefect).toList();

      x = _m;
      _text(
        canvas,
        '${startIndex + row + 1}',
        Rect.fromLTWH(x + 5, rowTop + 12, lpW - 10, 30),
        size: 14,
        weight: FontWeight.w600,
        align: TextAlign.center,
      );
      x += lpW;

      _text(
        canvas,
        defect.positionNo,
        Rect.fromLTWH(x + 7, rowTop + 12, posW - 14, rowH - 24),
        size: 14,
        weight: FontWeight.w600,
        maxLines: 5,
      );
      x += posW;

      _text(
        canvas,
        defect.location.trim().isEmpty ? '—' : defect.location,
        Rect.fromLTWH(x + 7, rowTop + 12, devW - 14, rowH - 24),
        size: 13,
        maxLines: 7,
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
        Rect.fromLTWH(x + 7, rowTop + 12, descW - 14, rowH - 24),
        size: 13,
        color: const Color(0xFF24364A),
        maxLines: 12,
      );
      x += descW;

      const gapX = 7.0;
      const gapY = 7.0;
      const innerX = 8.0;
      const innerY = 8.0;
      const labelH = 18.0;
      final cellW = (photoW - 2 * innerX - 2 * gapX) / 3;
      final cellH = (rowH - 2 * innerY - gapY) / 2;
      final imageH = cellH - labelH;

      for (var i = 0; i < _mainPhotosPerDefect; i++) {
        final col = i % 3;
        final rr = i ~/ 3;
        final box = Rect.fromLTWH(
          x + innerX + col * (cellW + gapX),
          rowTop + innerY + rr * (cellH + gapY),
          cellW,
          cellH,
        );
        final imageRect = Rect.fromLTWH(
          box.left,
          box.top,
          box.width,
          imageH,
        );

        canvas.drawRect(
          imageRect,
          Paint()..color = const Color(0xFFF0F2F4),
        );
        canvas.drawRect(
          imageRect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = const Color(0xFFD2D8DE),
        );

        if (i < visible.length) {
          overlays.add(
            _PhotoOverlay(
              path: visible[i].path,
              rect: imageRect.deflate(2),
              destination: _photoAnchor(defect, i),
            ),
          );
          _text(
            canvas,
            _photoLabel(visible[i]),
            Rect.fromLTWH(
              box.left + 2,
              box.top + imageH + 2,
              box.width - 4,
              labelH - 2,
            ),
            size: 8,
            weight: FontWeight.w700,
            color: const Color(0xFF4B5F73),
            align: TextAlign.center,
            maxLines: 1,
          );
        }
      }

      if (ordered.length > _mainPhotosPerDefect) {
        _text(
          canvas,
          '+${ordered.length - _mainPhotosPerDefect} na kolejnych stronach',
          Rect.fromLTWH(x + 8, rowTop + rowH - 20, photoW - 16, 16),
          size: 8,
          weight: FontWeight.w700,
          color: const Color(0xFF16324F),
          align: TextAlign.center,
          maxLines: 1,
        );
      }
    }

    _footer(
      canvas,
      'Strona $pageNo z $pageCount • kliknij miniaturę, aby otworzyć duże zdjęcie',
    );

    return _RenderedPage(
      background: await _pictureToJpeg(recorder, quality: 82),
      overlays: overlays,
      anchors: anchors,
    );
  }

  static Future<void> _addLargePhotoPage(
    pw.Document pdf, {
    required Defect defect,
    required AuditPhoto photo,
    required int photoNumber,
    required int totalPhotos,
  }) async {
    Uint8List bytes;
    try {
      bytes = await _preparePdfPhoto(
        photo.path,
        maxDimension: 2200,
        quality: 90,
      );
    } catch (_) {
      return;
    }

    final photoAnchor = _photoAnchor(defect, photoNumber - 1);
    final defectAnchor = _defectAnchor(defect);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 30, 30, 28),
        build: (_) => pw.Anchor(
          name: photoAnchor,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Dokumentacja zdjęciowa',
                          style: pw.TextStyle(
                            fontSize: 21,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey900,
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          'Pozycja ${defect.positionNo} • ${_photoLabel(photo)}',
                          style: const pw.TextStyle(
                            fontSize: 12,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Text(
                    '$photoNumber / $totalPhotos',
                    style: const pw.TextStyle(
                      fontSize: 11,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(
                    color: PdfColors.grey400,
                    width: 0.7,
                  ),
                ),
                height: PdfPageFormat.a4.height - 170,
                alignment: pw.Alignment.center,
                child: pw.Image(
                  pw.MemoryImage(bytes),
                  fit: pw.BoxFit.contain,
                ),
              ),
              pw.SizedBox(height: 9),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      defect.description,
                      maxLines: 2,
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Link(
                    destination: defectAnchor,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        border: pw.Border.all(
                          color: PdfColors.grey400,
                          width: 0.6,
                        ),
                      ),
                      child: pw.Text(
                        'Powrót do usterki',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue800,
                          decoration: pw.TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _defectAnchor(Defect defect) {
    final key = defect.id != null
        ? 'id${defect.id}'
        : 'pos_${_safe(defect.positionNo)}';
    return 'defect_$key';
  }

  static String _photoAnchor(Defect defect, int index) {
    final key = defect.id != null
        ? 'id${defect.id}'
        : 'pos_${_safe(defect.positionNo)}';
    return 'photo_${key}_${index + 1}';
  }

  static List<AuditPhoto> _orderedPhotos(List<AuditPhoto> photos) {
    final indexed = photos.asMap().entries.toList();
    int rank(AuditPhoto p) => switch (p.kind) {
          'issue' => 0,
          'nameplate' => 1,
          'resolution' => 2,
          _ => 3,
        };

    indexed.sort((a, b) {
      final r = rank(a.value).compareTo(rank(b.value));
      if (r != 0) return r;
      final d = a.value.createdAt.compareTo(b.value.createdAt);
      if (d != 0) return d;
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }

  static String _photoLabel(AuditPhoto photo) => switch (photo.kind) {
        'resolution' => 'PO NAPRAWIE',
        'nameplate' => 'TABLICZKA',
        _ => 'USTERKA',
      };

  static Future<Uint8List> _preparePdfPhoto(
    String path, {
    int maxDimension = 1400,
    int quality = 82,
  }) async {
    final raw = await File(path).readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;

    var working = img.bakeOrientation(decoded);
    final longest = working.width > working.height
        ? working.width
        : working.height;

    if (longest > maxDimension) {
      if (working.width >= working.height) {
        working = img.copyResize(
          working,
          width: maxDimension,
          interpolation: img.Interpolation.average,
        );
      } else {
        working = img.copyResize(
          working,
          height: maxDimension,
          interpolation: img.Interpolation.average,
        );
      }
    }

    return Uint8List.fromList(
      img.encodeJpg(working, quality: quality),
    );
  }

  static double _metaLine(
    Canvas canvas,
    double y,
    String label,
    String value,
  ) {
    _text(
      canvas,
      label,
      Rect.fromLTWH(_m, y, 155, 27),
      size: 15,
      weight: FontWeight.w700,
      color: const Color(0xFF24364A),
    );
    _text(
      canvas,
      value,
      Rect.fromLTWH(_m + 155, y, _w - 2 * _m - 155, 27),
      size: 15,
      color: const Color(0xFF24364A),
      maxLines: 1,
    );
    return y + 29;
  }

  static void _background(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, _h),
      Paint()..color = Colors.white,
    );
  }

  static void _footer(Canvas canvas, String text) {
    canvas.drawLine(
      const Offset(_m, _h - 56),
      const Offset(_w - _m, _h - 56),
      Paint()
        ..color = const Color(0xFFE1E6EB)
        ..strokeWidth = 2,
    );
    _text(
      canvas,
      text,
      const Rect.fromLTWH(_m, _h - 43, _w - 2 * _m, 24),
      size: 12,
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
          height: 1.12,
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

  static Future<Uint8List> _pictureToJpeg(
    ui.PictureRecorder recorder, {
    int quality = 82,
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

    return Uint8List.fromList(
      img.encodeJpg(decoded, quality: quality),
    );
  }

  static String _safe(String input) {
    final cleaned = input.trim().replaceAll(
          RegExp(r'[^a-zA-Z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ_-]+'),
          '_',
        );
    return cleaned.isEmpty ? 'obiekt' : cleaned;
  }
}

class _RenderedPage {
  final Uint8List background;
  final List<_PhotoOverlay> overlays;
  final List<_PageAnchor> anchors;

  const _RenderedPage({
    required this.background,
    required this.overlays,
    this.anchors = const <_PageAnchor>[],
  });
}

class _PhotoOverlay {
  final String path;
  final Rect rect;
  final String destination;

  const _PhotoOverlay({
    required this.path,
    required this.rect,
    required this.destination,
  });
}

class _PageAnchor {
  final String name;
  final double x;
  final double y;

  const _PageAnchor({
    required this.name,
    required this.x,
    required this.y,
  });
}

class _PdfOverlay {
  final Rect rect;
  final Uint8List bytes;
  final String destination;

  const _PdfOverlay({
    required this.rect,
    required this.bytes,
    required this.destination,
  });
}
