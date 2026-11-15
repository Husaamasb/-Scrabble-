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
  assert.equal(tileSetReport('ar').actualTotal, 110);
  assert.equal(tileSetReport('ar').matchesDeclaredTotal, true);
  assert.equal(tileSetReport('en').actualTotal, 100);
  assert.equal(tileSetReport('en').matchesDeclaredTotal, true);
  assert.equal(createTileBag('ar').length, 110);
  assert.equal(createTileBag('en').length, 100);
});
