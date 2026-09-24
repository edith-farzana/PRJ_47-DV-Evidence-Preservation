import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/audit/audit_entry.dart';
import 'export_manifest.dart';

/// Renders [ExportManifest] as the PDF a lawyer actually reads.
///
/// Uses the PDF standard fonts, which need no font file in the app but
/// cover Latin-1 only. Every piece of text that did not originate here
/// goes through [_plain], so a stray em dash in an error message cannot
/// come out as a box.
class ManifestPdf {
  ManifestPdf._();

  static Future<Uint8List> render(
    ExportManifest manifest, {
    required String manifestSha256,
  }) {
    final mono = pw.Font.courier();
    final bold = pw.Font.helveticaBold();

    final doc = pw.Document(
      title: 'Evidence export manifest',
      // Nothing that identifies a person or a device.
      creator: 'Secure Evidence',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        build: (context) => [
          pw.Text(
            'Evidence export - integrity manifest',
            style: pw.TextStyle(font: bold, fontSize: 18),
          ),
          pw.SizedBox(height: 14),

          _table([
            ('Generated (UTC)', manifest.generatedAt),
            ('Items in this bundle', '${manifest.items.length}'),
            ('Selected but not exported', '${manifest.notExported.length}'),
            (
              'Password protected',
              manifest.passwordProtected ? 'Yes (AES-256)' : 'No',
            ),
            (
              'Activity log',
              manifest.logIntact
                  ? 'Intact - ${manifest.logEntries} entries, every link verified'
                  : 'NOT INTACT - ${manifest.logStatus}',
            ),
          ]),
          pw.SizedBox(height: 6),
          _labelled('SHA-256 of manifest.json', manifestSha256, mono),

          pw.SizedBox(height: 18),
          _heading('Evidence in this bundle', bold),

          for (final item in manifest.items) _item(item, mono, bold),

          if (manifest.notExported.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _heading('Selected but not exported', bold),
            pw.Text(
              'These items were chosen for export but are not in the bundle, '
              'for the reason given. They are listed so that the gap is '
              'visible.',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 6),
            for (final item in manifest.notExported)
              pw.Bullet(
                text: _plain(
                  '${item.type}, captured ${item.capturedAt} '
                  '(evidence ${item.evidenceId}): ${item.reason}',
                ),
                style: const pw.TextStyle(fontSize: 9),
              ),
          ],

          pw.SizedBox(height: 14),
          _heading('Checking the files yourself', bold),
          pw.Text(
            "Each file's SHA-256 fingerprint was recorded when it was "
            'captured. Any change to a file, even a single byte, changes its '
            'fingerprint completely. Recompute it with a standard tool and '
            'compare it with the value above:',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Windows:        certutil -hashfile item-01.jpg SHA256\n'
            'macOS / Linux:  shasum -a 256 item-01.jpg',
            style: pw.TextStyle(font: mono, fontSize: 8),
          ),

          pw.SizedBox(height: 14),
          _heading('What this document does not claim', bold),
          for (final limit in const [
            'It cannot guarantee that a court will admit this evidence. That '
                'depends on the jurisdiction, how the evidence was collected, '
                'and the law.',
            "Times come from the phone's clock.",
            "Each item's fingerprint was also recorded at capture on a server "
                'where it cannot be changed or deleted by anyone, including '
                "the project's administrators. That record is held in the "
                "project's Firebase account.",
          ])
            pw.Bullet(text: limit, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _item(ExportedItem item, pw.Font mono, pw.Font bold) {
    final verdict = item.verdict == 'verified'
        ? 'Verified: decrypts to exactly what was captured, and matches the '
              'independent server record.'
        : 'Verified on this phone. The server record could not be '
              'confirmed: ${item.serverNote ?? item.serverCheck}';

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${item.bundleName}  (${item.type})',
            style: pw.TextStyle(font: bold, fontSize: 11),
          ),
          pw.SizedBox(height: 6),
          _table([
            ('Evidence ID', item.evidenceId),
            ('Captured (UTC)', item.capturedAt),
            ('Size', '${item.sizeBytes} bytes'),
            ('Verification', verdict),
          ]),
          pw.SizedBox(height: 4),
          _labelled('SHA-256 (the file)', item.sha256, mono),
          _labelled(
            'SHA-256 (as stored, encrypted)',
            item.storedFileSha256,
            mono,
          ),
          if (item.custody.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Custody, from the activity log',
              style: pw.TextStyle(font: bold, fontSize: 9),
            ),
            pw.SizedBox(height: 2),
            for (final event in item.custody)
              pw.Text(
                _plain(
                  '#${event.seq}   ${event.at}   ${_eventLabel(event.event)}',
                ),
                style: pw.TextStyle(font: mono, fontSize: 7.5),
              ),
          ],
        ],
      ),
    );
  }

  static String _eventLabel(String type) {
    for (final value in AuditEventType.values) {
      if (value.name == type) return value.label;
    }
    return type;
  }

  static pw.Widget _heading(String text, pw.Font bold) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Text(text, style: pw.TextStyle(font: bold, fontSize: 13)),
  );

  static pw.Widget _table(List<(String, String)> rows) => pw.Table(
    columnWidths: const {0: pw.FixedColumnWidth(150), 1: pw.FlexColumnWidth()},
    children: [
      for (final (label, value) in rows)
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
              child: pw.Text(
                label,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey800,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
              child: pw.Text(
                _plain(value),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
    ],
  );

  static pw.Widget _labelled(String label, String value, pw.Font mono) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
            ),
            pw.Text(
              _plain(value),
              style: pw.TextStyle(font: mono, fontSize: 8),
            ),
          ],
        ),
      );

  /// Latin-1 only, for the standard fonts. Common typography becomes its
  /// plain equivalent; anything else becomes `?` rather than a glyph box.
  static String _plain(String text) {
    const replacements = {
      '—': '-', // em dash
      '–': '-', // en dash
      '‘': "'",
      '’': "'",
      '“': '"',
      '”': '"',
      '…': '...',
      '↔': '<->',
    };

    final buffer = StringBuffer();

    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(replacements[char] ?? (rune <= 0xFF ? char : '?'));
    }

    return buffer.toString();
  }
}
