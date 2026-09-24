import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/services/export/export_manifest.dart';
import 'package:secure_evidence_app/services/export/manifest_pdf.dart';

void main() {
  ExportManifest manifest({String reason = 'Failed verification.'}) {
    return ExportManifest(
      generatedAt: '2026-09-24T10:00:00.000Z',
      passwordProtected: true,
      logIntact: true,
      logStatus: 'intact',
      logEntries: 12,
      logHeadHash: 'f' * 64,
      items: [
        ExportedItem(
          bundleName: 'item-01.jpg',
          evidenceId: 'cfe6ebed-a2e9-4329-bfb5-4bfa5e7d1aef',
          type: 'photo',
          capturedAt: '2026-09-15T16:05:00.000Z',
          sizeBytes: 6291456,
          sha256: 'a' * 64,
          storedFileSha256: 'b' * 64,
          verdict: 'verifiedOnThisPhone',
          serverCheck: 'unavailable',
          serverNote: 'there is no internet connection.',
          custody: const [
            CustodyEvent(
              seq: 3,
              at: '2026-09-15T16:05:01.000Z',
              event: 'captured',
            ),
            CustodyEvent(
              seq: 9,
              at: '2026-09-20T09:00:00.000Z',
              event: 'verified',
            ),
          ],
        ),
      ],
      notExported: [
        NotExportedItem(
          evidenceId: 'd1e2',
          type: 'video',
          capturedAt: '2026-09-16T10:00:00.000Z',
          reason: reason,
        ),
      ],
    );
  }

  test('renders a PDF', () async {
    final bytes = await ManifestPdf.render(
      manifest(),
      manifestSha256: 'c' * 64,
    );

    expect(ascii.decode(bytes.sublist(0, 4)), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });

  // The standard fonts cover Latin-1 only. Reasons come from error
  // messages elsewhere in the app, which use em dashes and arrows.
  test('text outside Latin-1 does not break it', () async {
    final bytes = await ManifestPdf.render(
      manifest(reason: 'Server disagrees — Recorded ↔ Server … “moved” 🚫'),
      manifestSha256: 'c' * 64,
    );

    expect(ascii.decode(bytes.sublist(0, 4)), '%PDF');
  });

  test('the README names the manifest fingerprint and how to check files', () {
    final readme = manifest().readme(manifestSha256: 'c' * 64);

    expect(readme, contains('c' * 64));
    expect(readme, contains('certutil -hashfile'));
    expect(readme, contains('shasum -a 256'));
    expect(readme, contains('7-Zip'));
    expect(readme, contains('cannot guarantee'));
  });
}
