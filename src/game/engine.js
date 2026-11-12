export const BOARD_SIZE = 15;
export const CENTER = 112;

const coords = (pairs) => new Set(pairs.map(([r,c]) => r * BOARD_SIZE + c));
const mirror = (pairs) => pairs.flatMap(([r,c]) => [[r,c],[r,14-c],[14-r,c],[14-r,14-c]]);
export const PREMIUM = (() => {
  const map = Array(225).fill(null);
  const put = (pairs, type) => pairs.forEach(([r,c]) => { map[r*15+c] = type; });
  put([[0,0],[0,7],[0,14],[7,0],[7,14],[14,0],[14,7],[14,14]], 'TW');
  put(mirror([[1,1],[2,2],[3,3],[4,4]]).concat([[7,7]]), 'DW');
  put(mirror([[1,5],[5,1],[5,5]]), 'TL');
  put([[0,3],[0,11],[2,6],[2,8],[3,0],[3,7],[3,14],[6,2],[6,6],[6,8],[6,12],[7,3],[7,11],[8,2],[8,6],[8,8],[8,12],[11,0],[11,7],[11,14],[12,6],[12,8],[14,3],[14,11]], 'DL');
  return Object.freeze(map);
})();

const key = (r,c) => r * 15 + c;
const tileAt = (board, placements, r, c) => placements.get(key(r,c)) ?? board[key(r,c)] ?? null;
const sameLine = (placements) => placements.every(p => p.row === placements[0].row) ||
  placements.every(p => p.col === placements[0].col);

function collectWord(board, placements, row, col, dr, dc) {
  let r = row, c = col;
  while (r-dr >= 0 && r-dr < 15 && c-dc >= 0 && c-dc < 15 && tileAt(board, placements, r-dr, c-dc)) {
    r -= dr; c -= dc;
  }
  const cells = [];
  while (r >= 0 && r < 15 && c >= 0 && c < 15 && tileAt(board, placements, r, c)) {
    cells.push({ row:r, col:c, tile:tileAt(board, placements, r, c) });
    r += dr; c += dc;
  }
  return cells;
}

function scoreWord(cells, placements) {
  let subtotal = 0, wordMultiplier = 1;
  for (const cell of cells) {
    const tile = cell.tile;
    let points = Number(tile.points) || 0;
    if (placements.has(key(cell.row,cell.col))) {
      const premium = PREMIUM[key(cell.row,cell.col)];
      if (premium === 'DL') points *= 2;
      if (premium === 'TL') points *= 3;
      if (premium === 'DW') wordMultiplier *= 2;
      if (premium === 'TW') wordMultiplier *= 3;
    }
    subtotal += points;
  }
  return subtotal * wordMultiplier;
}

export function evaluateMove(board, proposed) {
  if (!Array.isArray(proposed) || proposed.length === 0) return { valid:false, reason:'empty-move' };
  const placements = new Map();
  for (const p of proposed) {
    if (!Number.isInteger(p.row) || !Number.isInteger(p.col) || p.row<0 || p.row>=15 || p.col<0 || p.col>=15 || !p.tile) {
      return { valid:false, reason:'invalid-placement' };
    }
    const k = key(p.row,p.col);
    if (placements.has(k) || board[k]) return { valid:false, reason:'occupied-square' };
    placements.set(k,p.tile);
  }
  if (!sameLine(proposed)) return { valid:false, reason:'not-one-line' };

  const firstMove = !Object.values(board).some(Boolean);
  if (firstMove && !placements.has(CENTER)) return { valid:false, reason:'must-cover-center' };

  const horizontal = proposed.length === 1 || proposed.every(p=>p.row===proposed[0].row);
  const dr = horizontal ? 0 : 1, dc = horizontal ? 1 : 0;
  const ordered = [...proposed].sort((a,b)=>horizontal?a.col-b.col:a.row-b.row);
  const start = horizontal ? ordered[0].col : ordered[0].row;
  const end = horizontal ? ordered.at(-1).col : ordered.at(-1).row;
  const fixed = horizontal ? ordered[0].row : ordered[0].col;
  for (let n=start;n<=end;n++) {
    const r=horizontal?fixed:n, c=horizontal?n:fixed;
    if (!tileAt(board,placements,r,c)) return { valid:false, reason:'gap-in-word' };
  }

  if (!firstMove) {
    const connected = proposed.some(p => [[1,0],[-1,0],[0,1],[0,-1]].some(([a,b]) => {
      const r=p.row+a,c=p.col+b;
      return r>=0&&r<15&&c>=0&&c<15&&board[key(r,c)];
    }));
    if (!connected) return { valid:false, reason:'not-connected' };
  }

  const words = new Map();
  for (const p of proposed) {
    for (const [a,b] of [[0,1],[1,0]]) {
      const cells=collectWord(board,placements,p.row,p.col,a,b);
      if (cells.length>1) {
        const id=cells.map(x=>key(x.row,x.col)).join(',');
        words.set(id,cells);
      }
    }
  }
  if (words.size===0) return { valid:false, reason:'no-word-formed' };
  const scoredWords=[...words.values()].map(cells=>({
    letters:cells.map(x=>x.tile.blankAs ?? x.tile.letter).join(''),
    cells:cells.map(x=>key(x.row,x.col)),
    points:scoreWord(cells,placements)
  }));
  const bingo=proposed.length===7?50:0;
  return { valid:true, words:scoredWords, wordPoints:scoredWords.reduce((s,w)=>s+w.points,0), bingo, total:scoredWords.reduce((s,w)=>s+w.points,0)+bingo };
}

export function applyMove(board, proposed) {
  const result=evaluateMove(board,proposed);
  if (!result.valid) return result;
  const next={...board};
  proposed.forEach(p=>{next[key(p.row,p.col)]={...p.tile};});
  return {...result,board:next};
}
