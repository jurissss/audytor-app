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
  static const double _m = 58;
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

    _addRasterPage(pdf, await _renderCover(site, audit, defects));

    for (var start = 0; start < defects.length; start += _defectsPerPage) {
      final end = (start + _defectsPerPage).clamp(0, defects.length);
      _addRasterPage(
        pdf,
        await _renderDefectsPage(defects.sublist(start, end), photos),
      );
    }

    // Dodatkowe strony zdjęciowe. Dzięki temu żadne zdjęcie nie znika z PDF.
    for (final defect in defects) {
      final all = photos[defect.id] ?? const <AuditPhoto>[];
      if (all.length <= 6) continue;

      for (var start = 0; start < all.length; start += 12) {
        final end = (start + 12).clamp(0, all.length);
        _addRasterPage(
          pdf,
          await _renderPhotoContinuation(
            defect,
            all.sublist(start, end),
            startIndex: start,
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
                'Galeria zdjęć',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 18),
              pw.Text(
                'Pełna galeria zdjęć znajduje się w pliku ZDJECIA.html dołączonym do paczki audytu.',
              ),
              pw.SizedBox(height: 14),
              pw.UrlLink(
                destination: galleryHref,
                child: pw.Text(
                  'Otwórz ZDJECIA.html',
                  style: const pw.TextStyle(
                    color: PdfColors.blue,
                    decoration: pw.TextDecoration.underline,
                  ),
                ),
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

  static void _addRasterPage(pw.Document pdf, Uint8List image) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.SizedBox.expand(
          child: pw.Image(
            pw.MemoryImage(image),
            fit: pw.BoxFit.fill,
          ),
        ),
      ),
    );
  }

  static Future<Uint8List> _renderDefectsPage(
    List<Defect> defects,
    Map<int, List<AuditPhoto>> photos,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, _w, _h));
    _background(canvas);

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, 104),
      Paint()..color = const Color(0xFF16324F),
    );

    _text(
      canvas,
      'USTERKI',
      const Rect.fromLTWH(_m, 29, 600, 48),
      size: 32,
      weight: FontWeight.w700,
      color: Colors.white,
    );

    const top = 126.0;
    const gap = 16.0;
    final bottom = _h - 82;
    final cardH = (bottom - top - gap * 3) / 4;
    final cardW = _w - 2 * _m;

    for (var i = 0; i < defects.length; i++) {
      final defect = defects[i];
      final rect = Rect.fromLTWH(
        _m,
        top + i * (cardH + gap),
        cardW,
        cardH,
      );

      final all = photos[defect.id] ?? const <AuditPhoto>[];
      final issue = all.where((x) => x.isIssue).toList();
      final nameplate = all.where((x) => x.isNameplate).toList();
      final resolution = all.where((x) => x.isResolution).toList();

      ui.Image? issueImage;
      ui.Image? nameplateImage;
      final resolutionImages = <ui.Image>[];

      try {
        if (issue.isNotEmpty) {
          issueImage = await _loadThumbnail(issue.first.path);
        }
      } catch (_) {}

      try {
        if (nameplate.isNotEmpty) {
          nameplateImage = await _loadThumbnail(nameplate.first.path);
        }
      } catch (_) {}

      for (final photo in resolution.take(4)) {
        try {
          resolutionImages.add(await _loadThumbnail(photo.path));
        } catch (_) {}
      }

      _drawDefectCard(
        canvas,
        rect,
        defect,
        issue: issueImage,
        nameplate: nameplateImage,
        resolutions: resolutionImages,
        resolutionCount: resolution.length,
      );

      issueImage?.dispose();
      nameplateImage?.dispose();
      for (final image in resolutionImages) {
        image.dispose();
      }
    }

    _footer(
      canvas,
      '4 usterki na stronie • zdjęcia zachowują proporcje • wszystkie zdjęcia znajdują się w dalszej części PDF/paczce audytu',
    );

    return _pictureToJpeg(recorder, quality: 68);
  }

  static void _drawDefectCard(
    Canvas canvas,
    Rect r,
    Defect defect, {
    ui.Image? issue,
    ui.Image? nameplate,
    required List<ui.Image> resolutions,
    required int resolutionCount,
  }) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(14)),
      Paint()..color = const Color(0xFFF7F9FB),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(14)),
      Paint()
        ..color = const Color(0xFFDDE4EB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final priorityColor = switch (defect.priority) {
      'Krytyczny' => const Color(0xFFB42318),
      'Wysoki' => const Color(0xFFD97706),
      'Niski' => const Color(0xFF2E7D32),
      _ => const Color(0xFF2D7DD2),
    };

    _text(
      canvas,
      'Poz. ${defect.positionNo}',
      Rect.fromLTWH(r.left + 14, r.top + 11, 220, 30),
      size: 20,
      weight: FontWeight.w700,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.right - 142, r.top + 9, 128, 30),
        const Radius.circular(15),
      ),
      Paint()..color = priorityColor,
    );

    _text(
      canvas,
      defect.priority,
      Rect.fromLTWH(r.right - 138, r.top + 14, 120, 20),
      size: 12,
      weight: FontWeight.w700,
      color: Colors.white,
      align: TextAlign.center,
    );

    final photoTop = r.top + 48;
    const photoH = 150.0;
    const gap = 8.0;
    final available = r.width - 28;
    const cells = 6;
    final cellW = (available - gap * (cells - 1)) / cells;

    var x = r.left + 14;

    _photo(
      canvas,
      issue,
      Rect.fromLTWH(x, photoTop, cellW, photoH),
      'USTERKA',
    );
    x += cellW + gap;

    final plateLabel = nameplate != null
        ? 'TABLICZKA'
        : defect.nameplateUnavailable
            ? 'BRAK TABLICZKI'
            : 'TABLICZKA - BRAK ZDJ.';

    _photo(
      canvas,
      nameplate,
      Rect.fromLTWH(x, photoTop, cellW, photoH),
      plateLabel,
    );
    x += cellW + gap;

    for (var i = 0; i < 4; i++) {
      final image = i < resolutions.length ? resolutions[i] : null;
      _photo(
        canvas,
        image,
        Rect.fromLTWH(x, photoTop, cellW, photoH),
        image == null ? '—' : 'PO NAPRAWIE',
      );
      x += cellW + gap;
    }

    if (resolutionCount > 4) {
      _text(
        canvas,
        '+${resolutionCount - 4} dalszych',
        Rect.fromLTWH(r.right - 170, photoTop + 7, 155, 24),
        size: 13,
        weight: FontWeight.w700,
        color: const Color(0xFF16324F),
        align: TextAlign.right,
      );
    }

    var y = photoTop + photoH + 9;

    if (defect.location.trim().isNotEmpty) {
      _text(
        canvas,
        'Lokalizacja: ${defect.location}',
        Rect.fromLTWH(r.left + 14, y, r.width - 28, 23),
        size: 13,
        weight: FontWeight.w600,
        maxLines: 1,
      );
      y += 23;
    }

    _text(
      canvas,
      defect.description,
      Rect.fromLTWH(r.left + 14, y, r.width - 28, 45),
      size: 14,
      color: const Color(0xFF24364A),
      maxLines: 2,
    );
    y += 47;

    final status = defect.isResolved ? 'USUNIĘTA' : 'DO USUNIĘCIA';
    final statusColor = defect.isResolved
        ? const Color(0xFF2E7D32)
        : const Color(0xFFB42318);

    _text(
      canvas,
      status,
      Rect.fromLTWH(r.left + 14, y, 150, 22),
      size: 13,
      weight: FontWeight.w700,
      color: statusColor,
    );

    if (defect.isResolved && defect.resolvedAt != null) {
      _text(
        canvas,
        'Data: ${_dateTime.format(defect.resolvedAt!)}',
        Rect.fromLTWH(r.left + 170, y, 265, 22),
        size: 12,
        color: const Color(0xFF526579),
      );
    }

    if (defect.isResolved && defect.resolutionNote.trim().isNotEmpty) {
      _text(
        canvas,
        'Komentarz: ${defect.resolutionNote}',
        Rect.fromLTWH(r.left + 440, y, r.width - 454, 38),
        size: 12,
        color: const Color(0xFF526579),
        maxLines: 2,
      );
    }
  }

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
      Paint()..color = const Color(0xFF16324F),
    );

    _text(
      canvas,
      'ZDJĘCIA • Poz. ${defect.positionNo}',
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

      final label = switch (photos[i].kind) {
        'resolution' => 'Po naprawie',
        'nameplate' => 'Tabliczka znamionowa',
        _ => 'Usterka',
      };

      _photo(
        canvas,
        image,
        rect,
        '${startIndex + i + 1}/$total • $label',
      );

      image?.dispose();
    }

    _footer(
      canvas,
      'Dokumentacja zdjęciowa • wszystkie zdjęcia zachowują proporcje',
    );

    return _pictureToJpeg(recorder, quality: 66);
  }

  static void _photo(
    Canvas canvas,
    ui.Image? image,
    Rect rect,
    String label,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = const Color(0xFFECEFF2),
    );

    if (image != null) {
      _drawContainedPhoto(canvas, image, rect);
    }

    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.bottom - 24, rect.width, 24),
      Paint()..color = const Color(0x99000000),
    );

    _text(
      canvas,
      label,
      Rect.fromLTWH(rect.left + 4, rect.bottom - 20, rect.width - 8, 17),
      size: 9,
      weight: FontWeight.w700,
      color: Colors.white,
      align: TextAlign.center,
      maxLines: 1,
    );
  }

  static void _drawContainedPhoto(
    Canvas canvas,
    ui.Image image,
    Rect target,
  ) {
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
    canvas.clipRRect(
      RRect.fromRectAndRadius(target, const Radius.circular(8)),
    );

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      ),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );

    canvas.restore();
  }

  static Future<Uint8List> _renderCover(
    Site site,
    Audit audit,
    List<Defect> defects,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, _w, _h));
    _background(canvas);

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, 250),
      Paint()..color = const Color(0xFF16324F),
    );

    _text(
      canvas,
      'RAPORT Z AUDYTU',
      const Rect.fromLTWH(82, 82, 1076, 75),
      size: 52,
      weight: FontWeight.w700,
      color: Colors.white,
    );

    _text(
      canvas,
      audit.auditType,
      const Rect.fromLTWH(82, 164, 1076, 48),
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

    y = _labelValue(
      canvas,
      y,
      'DATA ROZPOCZĘCIA',
      _dateTime.format(audit.startedAt),
    );

    if (audit.completedAt != null) {
      y = _labelValue(
        canvas,
        y,
        'DATA ZAKOŃCZENIA',
        _dateTime.format(audit.completedAt!),
      );
    }

    y = _labelValue(canvas, y, 'AUDYTOR', audit.auditor);

    y += 25;

    _text(
      canvas,
      'Usterki: ${defects.length}   •   Usunięte: ${defects.where((d) => d.isResolved).length}',
      Rect.fromLTWH(82, y, 1076, 55),
      size: 27,
      weight: FontWeight.w700,
    );

    _footer(
      canvas,
      'Raport Audytor • układ 1 × 4 • wersja 0.7.0',
    );

    return _pictureToJpeg(recorder, quality: 70);
  }

  static double _labelValue(
    Canvas canvas,
    double y,
    String label,
    String value,
  ) {
    _text(
      canvas,
      label,
      Rect.fromLTWH(82, y, 300, 30),
      size: 17,
      weight: FontWeight.w700,
      color: const Color(0xFF6A7A8C),
    );

    _text(
      canvas,
      value,
      Rect.fromLTWH(82, y + 38, 1076, 70),
      size: 28,
      weight: FontWeight.w500,
      color: const Color(0xFF1B2B3D),
      maxLines: 2,
    );

    return y + 118;
  }

  static void _background(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, _h),
      Paint()..color = Colors.white,
    );
  }

  static void _footer(Canvas canvas, String text) {
    canvas.drawLine(
      const Offset(_m, _h - 70),
      const Offset(_w - _m, _h - 70),
      Paint()
        ..color = const Color(0xFFE1E6EB)
        ..strokeWidth = 2,
    );

    _text(
      canvas,
      text,
      const Rect.fromLTWH(_m, _h - 55, _w - 2 * _m, 30),
      size: 14,
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

    painter.paint(
      canvas,
      Offset(rect.left, rect.top),
    );
  }

  static Future<ui.Image> _loadThumbnail(
    String path, {
    int width = 520,
  }) async {
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
    int quality = 68,
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
      data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ),
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
