import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/CloudDashboard.jsx', import.meta.url), 'utf8');

test('friends section displays a shareable public player QR code', () => {
  assert.match(source, /SCRABBLE-FRIEND:/);
  assert.match(source, /api\.qrserver\.com\/v1\/create-qr-code/);
  assert.match(source, /profile\?\.public_id/);
});

test('friends section can decode QR images and resolves only Scrabble friend payloads', () => {
  assert.match(source, /new BarcodeDetector\(\{formats:\['qr_code'\]\}\)/);
  assert.match(source, /raw\.startsWith\('SCRABBLE-FRIEND:'\)/);
  assert.match(source, /setSearch\(id\)/);
  assert.match(source, /accept=['"]image\/\*['"]/);
});
