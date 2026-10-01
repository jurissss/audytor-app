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
import '../models/defect_note.dart';

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

class ReportBatchResult {
  final List<ReportResult> parts;
  final int limitBytes;

  const ReportBatchResult({
    required this.parts,
    required this.limitBytes,
  });

  bool get isSplit => parts.length > 1;
}

class _PreparedPhoto {
  final Uint8List thumbnail;
  final Uint8List large;

  const _PreparedPhoto({
    required this.thumbnail,
    required this.large,
  });
}

class _ReportPhoto {
  final String path;
  final String label;
  final DateTime createdAt;

  const _ReportPhoto({
    required this.path,
    required this.label,
    required this.createdAt,
  });
}

class ReportService {
  static const double _w = 1240;
  static const double _h = 1754;
  static const double _m = 42;
  static const int _defectsPerPage = 8;
  static const int _mainPhotosPerDefect = 5;
  static const int _pdfLimitBytes = 23 * 1024 * 1024;
  static const int _largePhotoTargetBytes = 250 * 1024;
  static const int _thumbnailTargetBytes = 48 * 1024;
  static final DateFormat _dateTime = DateFormat('dd.MM.yyyy HH:mm');

  static Future<ReportBatchResult> generate({
    required Audit audit,
    required List<Defect> defects,
    required Map<int, List<AuditPhoto>> photos,
    required Map<int, List<DefectNote>> notes,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'reports'));
    if (!await dir.exists()) await dir.create(recursive: true);

    final reportPhotos = _buildReportPhotos(defects, photos, notes);
    final prepared = await _prepareAllPhotos(reportPhotos);
    final chunks = _planChunks(defects, reportPhotos, prepared);

    final parts = <ReportResult>[];
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final auditStamp = DateFormat('yyyyMMdd_HHmm').format(audit.startedAt);
    final baseName =
        'Audyt_${_safe(audit.client)}_${_safe(audit.storeNumber)}_${auditStamp}_aktualny';

    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final globalStart =
          defects.isEmpty || chunk.isEmpty ? 0 : defects.indexOf(chunk.first);

      var bytes = await _buildPdfBytes(
        audit: audit,
        defects: chunk,
        reportPhotos: reportPhotos,
        notes: notes,
        globalStartIndex: globalStart,
        prepared: prepared,
      );

      // Bezpiecznik rzeczywistego rozmiaru PDF.
      if (bytes.length > _pdfLimitBytes && chunk.length > 1) {
        var candidate = List<Defect>.from(chunk);

        while (bytes.length > _pdfLimitBytes && candidate.length > 1) {
          candidate = candidate.sublist(0, candidate.length - 1);
          bytes = await _buildPdfBytes(
            audit: audit,
            defects: candidate,
            reportPhotos: reportPhotos,
            notes: notes,
            globalStartIndex: globalStart,
            prepared: prepared,
          );
        }

        final removed = chunk.sublist(candidate.length);
        chunks[i] = candidate;
        if (removed.isNotEmpty) chunks.insert(i + 1, removed);
      }

      final suffix = chunks.length == 1
          ? ''
          : '_czesc_${(i + 1).toString().padLeft(2, '0')}';
      final filename = '${baseName}${suffix}_$stamp.pdf';
      final file = File(p.join(dir.path, filename));
      await file.writeAsBytes(bytes, flush: true);

      parts.add(
        ReportResult(
          bytes: bytes,
          path: file.path,
          filename: filename,
        ),
      );
    }

    return ReportBatchResult(parts: parts, limitBytes: _pdfLimitBytes);
  }

  static Map<int, List<_ReportPhoto>> _buildReportPhotos(
    List<Defect> defects,
    Map<int, List<AuditPhoto>> photos,
    Map<int, List<DefectNote>> notes,
  ) {
    final result = <int, List<_ReportPhoto>>{};

    for (final defect in defects) {
      final id = defect.id;
      if (id == null) continue;

      final list = <_ReportPhoto>[];
      final regular = [...(photos[id] ?? const <AuditPhoto>[])];

      int rank(AuditPhoto photo) => switch (photo.kind) {
            'issue' => 0,
            'nameplate' => 1,
            'resolution' => 3,
            _ => 4,
          };

      regular.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return a.createdAt.compareTo(b.createdAt);
      });

      for (final photo in regular) {
        list.add(
          _ReportPhoto(
            path: photo.path,
            label: switch (photo.kind) {
              'nameplate' => 'TABLICZKA',
              'resolution' => 'PO NAPRAWIE',
              _ => 'USTERKA',
            },
            createdAt: photo.createdAt,
          ),
        );
      }

      for (final note in notes[id] ?? const <DefectNote>[]) {
        for (final path in note.photoPaths) {
          list.add(
            _ReportPhoto(
              path: path,
              label: 'UWAGA',
              createdAt: note.createdAt,
            ),
          );
        }
      }

      result[id] = list;
    }

    return result;
  }

  static Future<Map<String, _PreparedPhoto>> _prepareAllPhotos(
    Map<int, List<_ReportPhoto>> reportPhotos,
  ) async {
    final paths = <String>{};
    for (final list in reportPhotos.values) {
      for (final photo in list) {
        paths.add(photo.path);
      }
    }

    final result = <String, _PreparedPhoto>{};
    final queue = paths.toList();
    const workers = 3;
    var index = 0;

    Future<void> worker() async {
      while (true) {
        final current = index++;
        if (current >= queue.length) return;

        final path = queue[current];

        try {
          final raw = await File(path).readAsBytes();
          final decoded = img.decodeImage(raw);

          if (decoded == null) {
            result[path] = _PreparedPhoto(
              thumbnail: raw,
              large: raw,
            );
            continue;
          }

          final oriented = img.bakeOrientation(decoded);
          result[path] = _PreparedPhoto(
            thumbnail: _encodeToTarget(
              oriented,
              maxDimension: 900,
              targetBytes: _thumbnailTargetBytes,
            ),
            large: _encodeToTarget(
              oriented,
              maxDimension: 1800,
              targetBytes: _largePhotoTargetBytes,
            ),
          );
        } catch (_) {
          // Uszkodzone zdjęcie nie zatrzymuje generowania raportu.
        }
      }
    }

    await Future.wait(List.generate(workers, (_) => worker()));
    return result;
  }

  static Uint8List _encodeToTarget(
    img.Image source, {
    required int maxDimension,
    required int targetBytes,
  }) {
    Uint8List? smallest;

    final dimensions = <int>[
      maxDimension,
      1600,
      1450,
      1300,
      1150,
      1000,
      900,
      800,
      700,
    ].where((x) => x <= maxDimension).toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    for (final dimension in dimensions) {
      img.Image working = source;
      final longest =
          working.width > working.height ? working.width : working.height;

      if (longest > dimension) {
        working = working.width >= working.height
            ? img.copyResize(
                working,
                width: dimension,
                interpolation: img.Interpolation.average,
              )
            : img.copyResize(
                working,
                height: dimension,
                interpolation: img.Interpolation.average,
              );
      }

      for (final quality in const <int>[82, 76, 70, 64, 58, 52, 46, 40]) {
        final encoded = Uint8List.fromList(
          img.encodeJpg(working, quality: quality),
        );

        if (smallest == null || encoded.length < smallest.length) {
          smallest = encoded;
        }

        if (encoded.length <= targetBytes) return encoded;
      }
    }

    return smallest ??
        Uint8List.fromList(img.encodeJpg(source, quality: 70));
  }

  static List<List<Defect>> _planChunks(
    List<Defect> defects,
    Map<int, List<_ReportPhoto>> reportPhotos,
    Map<String, _PreparedPhoto> prepared,
  ) {
    if (defects.isEmpty) return <List<Defect>>[<Defect>[]];

    final chunks = <List<Defect>>[];
    var current = <Defect>[];
    var currentBytes = 350 * 1024;
    const planningLimit = 22 * 1024 * 1024;

    for (final defect in defects) {
      var defectBytes = 120 * 1024;

      for (final photo
          in reportPhotos[defect.id] ?? const <_ReportPhoto>[]) {
        final item = prepared[photo.path];
        if (item != null) {
          defectBytes += item.large.length;
          defectBytes += item.thumbnail.length;
          defectBytes += 12 * 1024;
        }
      }

      if (current.isNotEmpty &&
          currentBytes + defectBytes > planningLimit) {
        chunks.add(current);
        current = <Defect>[];
        currentBytes = 350 * 1024;
      }

      current.add(defect);
      currentBytes += defectBytes;
    }

    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  static Future<Uint8List> _buildPdfBytes({
    required Audit audit,
    required List<Defect> defects,
    required Map<int, List<_ReportPhoto>> reportPhotos,
    required Map<int, List<DefectNote>> notes,
    required int globalStartIndex,
    required Map<String, _PreparedPhoto> prepared,
  }) async {
    final pdf = pw.Document();
    final pageCount =
        defects.isEmpty ? 1 : (defects.length / _defectsPerPage).ceil();

    if (defects.isEmpty) {
      final page = await _renderTablePage(
        audit,
        const <Defect>[],
        reportPhotos,
        notes,
        startIndex: globalStartIndex,
        pageNo: 1,
        pageCount: 1,
        totalDefects: 0,
      );
      await _addCompositePage(pdf, page, prepared: prepared);
    } else {
      for (var start = 0;
          start < defects.length;
          start += _defectsPerPage) {
        final end =
            (start + _defectsPerPage).clamp(0, defects.length);

        final page = await _renderTablePage(
          audit,
          defects.sublist(start, end),
          reportPhotos,
          notes,
          startIndex: globalStartIndex + start,
          pageNo: (start ~/ _defectsPerPage) + 1,
          pageCount: pageCount,
          totalDefects: defects.length,
        );

        await _addCompositePage(
          pdf,
          page,
          prepared: prepared,
        );
      }
    }

    for (final defect in defects) {
      final history =
          notes[defect.id] ?? const <DefectNote>[];

      if (history.isNotEmpty) {
        _addNotesHistoryPage(
          pdf,
          defect: defect,
          notes: history,
        );
      }

      final ordered =
          reportPhotos[defect.id] ?? const <_ReportPhoto>[];

      for (var i = 0; i < ordered.length; i++) {
        await _addLargePhotoPage(
          pdf,
          defect: defect,
          photo: ordered[i],
          photoNumber: i + 1,
          totalPhotos: ordered.length,
          prepared: prepared,
        );
      }
    }

    return pdf.save();
  }

  static Future<void> printReport(ReportResult report) {
    return Printing.layoutPdf(
      name: report.filename,
      onLayout: (_) async => report.bytes,
    );
  }

  static Future<void> _addCompositePage(
    pw.Document pdf,
    _RenderedPage page, {
    required Map<String, _PreparedPhoto> prepared,
  }) async {
    final overlays = <_PdfOverlay>[];

    for (final overlay in page.overlays) {
      final cached = prepared[overlay.path];
      if (cached == null) continue;

      overlays.add(
        _PdfOverlay(
          rect: overlay.rect,
          bytes: cached.thumbnail,
          destination: overlay.destination,
        ),
      );
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
    Audit audit,
    List<Defect> defects,
    Map<int, List<_ReportPhoto>> reportPhotos,
    Map<int, List<DefectNote>> notes, {
    required int startIndex,
    required int pageNo,
    required int pageCount,
    required int totalDefects,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas =
        Canvas(recorder, const Rect.fromLTWH(0, 0, _w, _h));
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
    y = _metaLine(canvas, y, 'Klient:', audit.client);
    y = _metaLine(canvas, y, 'Numer sklepu:', audit.storeNumber);
    y = _metaLine(canvas, y, 'Adres:', audit.address);
    y = _metaLine(canvas, y, 'Audytor:', audit.auditor);
    y = _metaLine(
      canvas,
      y,
      'Data:',
      _dateTime.format(audit.startedAt),
    );
    _metaLine(canvas, y, 'Liczba usterek:', '$totalDefects');

    const tableTop = 300.0;
    const headerH = 52.0;
    final tableW = _w - 2 * _m;

    const lpW = 50.0;
    const posW = 88.0;
    const devW = 144.0;
    const descW = 231.0;
    final photoW = tableW - lpW - posW - devW - descW;

    final widths = <double>[
      lpW,
      posW,
      devW,
      descW,
      photoW,
    ];

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
        Rect.fromLTWH(
          x + 6,
          tableTop + 13,
          widths[i] - 12,
          32,
        ),
        size: 12,
        weight: FontWeight.w700,
        color: Colors.white,
        align: i == 0 ? TextAlign.center : TextAlign.left,
        maxLines: 2,
      );
      x += widths[i];
    }

    final availableH =
        _h - tableTop - headerH - 78;
    final rowH = availableH / _defectsPerPage;

    final overlays = <_PhotoOverlay>[];
    final anchors = <_PageAnchor>[];

    for (var row = 0; row < _defectsPerPage; row++) {
      final rowTop =
          tableTop + headerH + row * rowH;
      final rowRect =
          Rect.fromLTWH(_m, rowTop, tableW, rowH);

      canvas.drawRect(
        rowRect,
        Paint()
          ..color = row.isEven
              ? Colors.white
              : const Color(0xFFF7F9FB),
      );

      canvas.drawRect(
        rowRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFFB8C3CE),
      );

      var lineX = _m;

      for (final width
          in widths.take(widths.length - 1)) {
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

      final ordered =
          reportPhotos[defect.id] ?? const <_ReportPhoto>[];
      final visible =
          ordered.take(_mainPhotosPerDefect).toList();

      x = _m;

      _text(
        canvas,
        '${startIndex + row + 1}',
        Rect.fromLTWH(
          x + 4,
          rowTop + 8,
          lpW - 8,
          24,
        ),
        size: 11,
        weight: FontWeight.w600,
        align: TextAlign.center,
      );

      x += lpW;

      _text(
        canvas,
        defect.positionNo,
        Rect.fromLTWH(
          x + 5,
          rowTop + 8,
          posW - 10,
          rowH - 16,
        ),
        size: 10,
        weight: FontWeight.w600,
        maxLines: 4,
      );

      x += posW;

      _text(
        canvas,
        defect.location.trim().isEmpty
            ? '—'
            : defect.location,
        Rect.fromLTWH(
          x + 5,
          rowTop + 8,
          devW - 10,
          rowH - 16,
        ),
        size: 10,
        maxLines: 5,
      );

      x += devW;

      var desc = defect.description;

      if (defect.recommendation.trim().isNotEmpty) {
        desc +=
            '\nZalecenie: ${defect.recommendation}';
      }

      final history =
          notes[defect.id] ?? const <DefectNote>[];

      if (history.isNotEmpty) {
        desc += '\nUwagi po audycie: ${history.length}';
      }

      if (defect.isResolved) {
        desc += '\nUSUNIĘTA';

        if (defect.resolvedAt != null) {
          desc +=
              ' • ${_dateTime.format(defect.resolvedAt!)}';
        }

        if (defect.resolutionNote.trim().isNotEmpty) {
          desc += '\n${defect.resolutionNote}';
        }
      }

      _text(
        canvas,
        desc,
        Rect.fromLTWH(
          x + 5,
          rowTop + 8,
          descW - 10,
          rowH - 16,
        ),
        size: 10,
        color: const Color(0xFF24364A),
        maxLines: 7,
      );

      x += descW;

      const gapX = 5.0;
      const innerX = 7.0;
      const innerY = 7.0;
      const labelH = 15.0;

      final cellW =
          (photoW -
                  2 * innerX -
                  gapX * (_mainPhotosPerDefect - 1)) /
              _mainPhotosPerDefect;

      final cellH = rowH - 2 * innerY;
      final imageH = cellH - labelH;

      for (var i = 0;
          i < _mainPhotosPerDefect;
          i++) {
        final box = Rect.fromLTWH(
          x + innerX + i * (cellW + gapX),
          rowTop + innerY,
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
          Paint()
            ..color = const Color(0xFFF0F2F4),
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
            visible[i].label,
            Rect.fromLTWH(
              box.left + 2,
              box.top + imageH + 2,
              box.width - 4,
              labelH - 2,
            ),
            size: 7,
            weight: FontWeight.w700,
            color: const Color(0xFF4B5F73),
            align: TextAlign.center,
            maxLines: 1,
          );
        }
      }

      if (ordered.length >
          _mainPhotosPerDefect) {
        _text(
          canvas,
          '+${ordered.length - _mainPhotosPerDefect} dalszych',
          Rect.fromLTWH(
            x + photoW - 110,
            rowTop + 3,
            100,
            14,
          ),
          size: 7,
          weight: FontWeight.w700,
          color: const Color(0xFF16324F),
          align: TextAlign.right,
          maxLines: 1,
        );
      }
    }

    _footer(
      canvas,
      'Strona $pageNo z $pageCount • 8 usterek na stronie • kliknij miniaturę, aby otworzyć duże zdjęcie',
    );

    return _RenderedPage(
      background:
          await _pictureToJpeg(recorder, quality: 82),
      overlays: overlays,
      anchors: anchors,
    );
  }

  static void _addNotesHistoryPage(
    pw.Document pdf, {
    required Defect defect,
    required List<DefectNote> notes,
  }) {
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (_) => pw.Row(
          mainAxisAlignment:
              pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Historia uwag • pozycja ${defect.positionNo}',
              style: pw.TextStyle(
                fontSize: 17,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Link(
              destination: _defectAnchor(defect),
              child: pw.Text(
                'Powrót do usterki',
                style: pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.blue800,
                  decoration:
                      pw.TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        footer: (_) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Link(
            destination: _defectAnchor(defect),
            child: pw.Text(
              'Powrót do usterki',
              style: pw.TextStyle(
                fontSize: 9,
                color: PdfColors.blue800,
                decoration:
                    pw.TextDecoration.underline,
              ),
            ),
          ),
        ),
        build: (_) => [
          pw.SizedBox(height: 14),
          ...notes.map(
            (note) => pw.Container(
              margin:
                  const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: PdfColors.grey400,
                  width: 0.6,
                ),
                color: PdfColors.grey100,
              ),
              child: pw.Column(
                crossAxisAlignment:
                    pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _dateTime.format(note.createdAt),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (note.text.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 5),
                    pw.Text(
                      note.text,
                      style:
                          const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                  if (note.photoPaths.isNotEmpty) ...[
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'Zdjęcia: ${note.photoPaths.length}',
                      style:
                          const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _addLargePhotoPage(
    pw.Document pdf, {
    required Defect defect,
    required _ReportPhoto photo,
    required int photoNumber,
    required int totalPhotos,
    required Map<String, _PreparedPhoto> prepared,
  }) async {
    final cached = prepared[photo.path];
    if (cached == null) return;

    final photoAnchor =
        _photoAnchor(defect, photoNumber - 1);
    final defectAnchor = _defectAnchor(defect);

    pw.Widget backLink() => pw.Link(
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
                decoration:
                    pw.TextDecoration.underline,
              ),
            ),
          ),
        );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          30,
          25,
          30,
          25,
        ),
        build: (_) => pw.Anchor(
          name: photoAnchor,
          child: pw.Column(
            crossAxisAlignment:
                pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment:
                    pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment:
                    pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment:
                          pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Dokumentacja zdjęciowa',
                          style: pw.TextStyle(
                            fontSize: 21,
                            fontWeight:
                                pw.FontWeight.bold,
                            color: PdfColors.grey900,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Pozycja ${defect.positionNo} • ${photo.label}',
                          style: const pw.TextStyle(
                            fontSize: 12,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        '$photoNumber / $totalPhotos',
                        style: const pw.TextStyle(
                          fontSize: 11,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      backLink(),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 9),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(
                    color: PdfColors.grey400,
                    width: 0.7,
                  ),
                ),
                height: PdfPageFormat.a4.height - 188,
                alignment: pw.Alignment.center,
                child: pw.Image(
                  pw.MemoryImage(cached.large),
                  fit: pw.BoxFit.contain,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment:
                    pw.MainAxisAlignment.spaceBetween,
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
                  backLink(),
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

  static String _photoAnchor(
    Defect defect,
    int index,
  ) {
    final key = defect.id != null
        ? 'id${defect.id}'
        : 'pos_${_safe(defect.positionNo)}';
    return 'photo_${key}_${index + 1}';
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
      Rect.fromLTWH(
        _m + 155,
        y,
        _w - 2 * _m - 155,
        27,
      ),
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

  static void _footer(
    Canvas canvas,
    String text,
  ) {
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
      const Rect.fromLTWH(
        _m,
        _h - 43,
        _w - 2 * _m,
        24,
      ),
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
      ellipsis:
          maxLines == null ? null : '…',
      locale: const Locale('pl', 'PL'),
    )..layout(maxWidth: rect.width);

    painter.paint(
      canvas,
      Offset(rect.left, rect.top),
    );
  }

  static Future<Uint8List> _pictureToJpeg(
    ui.PictureRecorder recorder, {
    int quality = 82,
  }) async {
    final picture = recorder.endRecording();
    final image =
        await picture.toImage(_w.toInt(), _h.toInt());
    picture.dispose();

    final data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();

    if (data == null) {
      throw StateError(
        'Nie udało się wyrenderować strony raportu.',
      );
    }

    final decoded = img.decodePng(
      data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ),
    );

    if (decoded == null) {
      throw StateError(
        'Nie udało się skompresować strony raportu.',
      );
    }

    return Uint8List.fromList(
      img.encodeJpg(decoded, quality: quality),
    );
  }

  static String _safe(String input) {
    final cleaned = input.trim().replaceAll(
          RegExp(
            r'[^a-zA-Z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ_-]+',
          ),
          '_',
        );

    return cleaned.isEmpty ? 'audyt' : cleaned;
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
