import test from 'node:test';
import assert from 'node:assert/strict';
import { BOARD_SIZE, CENTER, PREMIUM, evaluateMove, applyMove } from './engine.js';
import { tileSetReport, createTileBag } from './tiles.js';

const blankBoard = () => Array(BOARD_SIZE * BOARD_SIZE).fill(null);
const placement = (row, col, letter) => ({
  row, col, tile: { letter, points: 1, isBlank: false }
});

test('the standard board is 15x15 with exactly 61 premium squares', () => {
  assert.equal(BOARD_SIZE, 15);
  assert.equal(CENTER, 112);
  assert.equal(PREMIUM.length, 225);
  assert.equal(PREMIUM.filter(Boolean).length, 61);
});

test('the first word must cover the center and scores its double-word square', () => {
  const result = evaluateMove(blankBoard(), [
    placement(7, 7, 'A'),
    placement(7, 8, 'T')
  ]);
  assert.equal(result.valid, true);
  assert.equal(result.words.length, 1);
  assert.equal(result.words[0].letters, 'AT');
  assert.equal(result.total, 4);
});

test('a first move away from the center is rejected', () => {
  const result = evaluateMove(blankBoard(), [
    placement(6, 6, 'A'),
    placement(6, 7, 'T')
  ]);
  assert.equal(result.valid, false);
  assert.equal(result.reason, 'must-cover-center');
});

test('a word cannot contain a gap between newly placed tiles', () => {
  const result = evaluateMove(blankBoard(), [
    placement(7, 7, 'A'),
    placement(7, 9, 'T')
  ]);
  assert.equal(result.valid, false);
  assert.equal(result.reason, 'gap-in-word');
});

test('later words must connect to the existing board', () => {
  const board = blankBoard();
  board[CENTER] = { letter: 'A', points: 1 };
  const result = evaluateMove(board, [placement(7, 8, 'T')]);
  assert.equal(result.valid, true);
  assert.equal(result.words[0].letters, 'AT');
  assert.equal(result.total, 2);
});

test('using all seven rack tiles grants the 50-point bingo bonus', () => {
  const move = Array.from({ length: 7 }, (_, i) => placement(7, i + 4, 'A'));
  const result = evaluateMove(blankBoard(), move);
  assert.equal(result.valid, true);
  assert.equal(result.bingo, 50);
  assert.equal(result.total, 64);
});

test('applying a valid move writes the new tiles to the board', () => {
  const result = applyMove(blankBoard(), [
    placement(7, 7, 'A'),
    placement(7, 8, 'T')
  ]);
  assert.equal(result.valid, true);
  assert.equal(result.board[CENTER].letter, 'A');
  assert.equal(result.board[CENTER + 1].letter, 'T');
});

test('Arabic and English tile bags match their declared totals', () => {
  assert.equal(tileSetReport('ar').actualTotal, 108);
  assert.equal(tileSetReport('ar').matchesDeclaredTotal, true);
  assert.equal(tileSetReport('en').actualTotal, 100);
  assert.equal(tileSetReport('en').matchesDeclaredTotal, true);
  assert.equal(createTileBag('ar').length, 108);
  assert.equal(createTileBag('en').length, 100);
});

test('a previously used double-word square does not multiply later words', () => {
  const board = blankBoard();
  board[CENTER] = { letter: 'A', points: 1 };
  const result = evaluateMove(board, [placement(7, 8, 'T')]);
  assert.equal(result.valid, true);
  assert.equal(result.total, 2);
});

test('cross words are each scored when a move intersects existing tiles', () => {
  const board = blankBoard();
  board[7 * 15 + 7] = { letter: 'A', points: 1 };
  const result = evaluateMove(board, [
    placement(6, 6, 'C'),
    placement(7, 6, 'T')
  ]);
  assert.equal(result.valid, true);
  assert.deepEqual(result.words.map(word => word.letters).sort(), ['CT', 'TA']);
  assert.equal(result.total, 5);
});

test('a blank tile represents a letter but always scores zero', () => {
  const result = evaluateMove(blankBoard(), [
    { row: 7, col: 7, tile: { id: 'blank-1', letter: '★', points: 0, isBlank: true, blankAs: 'A' } },
    { row: 7, col: 8, tile: { id: 'tile-2', letter: 'T', points: 1, isBlank: false } }
  ]);
  assert.equal(result.valid, true);
  assert.equal(result.words[0].letters, 'AT');
  assert.equal(result.total, 2);
});

test('the same physical rack tile cannot be placed twice', () => {
  const result = evaluateMove(blankBoard(), [
    { row: 7, col: 7, tile: { id: 'same-tile', letter: 'A', points: 1 } },
    { row: 7, col: 8, tile: { id: 'same-tile', letter: 'T', points: 1 } }
  ]);
  assert.equal(result.valid, false);
  assert.equal(result.reason, 'duplicate-tile');
});

test('all supplied premium coordinates are represented exactly once', () => {
  const expected = {
    TW: [0,7,14,105,119,210,217,224],
    DW: [18,26,32,42,46,58,64,70,112,154,160,166,178,182,192,198,206],
    TL: [20,24,76,80,84,88,136,140,144,148,200,204],
    DL: [3,11,36,38,45,52,59,92,96,98,102,108,116,122,126,128,132,165,172,179,186,188,213,221]
  };
  for (const [kind, indexes] of Object.entries(expected)) {
    assert.deepEqual(PREMIUM.flatMap((value, index) => value === kind ? [index] : []), indexes);
  }
});
