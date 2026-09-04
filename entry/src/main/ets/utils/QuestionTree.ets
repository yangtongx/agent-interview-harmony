import { AnswerBlock, Question } from '../model/Types';

export function formatQuestionCode(id: string): string {
  const parts = id.split('.');
  const head = parts[0];
  const rest = parts.slice(1);
  if (head.startsWith('A')) {
    const n = head.slice(1);
    return rest.length ? [n, ...rest].join('.') : n;
  }
  const padded = head.padStart(2, '0');
  return rest.length ? [padded, ...rest].join('.') : padded;
}

export function displayQuestionCode(id: string): string {
  const parts = id.split('.');
  const head = parts[0];
  const rest = parts.slice(1);
  if (head.startsWith('A')) {
    const n = head.slice(1);
    const tail = rest.length ? `.${rest.join('.')}` : '';
    return `爱连 ${n}${tail}`;
  }
  return `Q${formatQuestionCode(id)}`;
}

export function flattenQuestions(nodes: Question[]): Question[] {
  const out: Question[] = [];
  const walk = (q: Question): void => {
    out.push(q);
    for (let i = 0; i < q.children.length; i++) {
      walk(q.children[i]);
    }
  };
  for (let i = 0; i < nodes.length; i++) {
    walk(nodes[i]);
  }
  return out;
}

export function countQuestions(nodes: Question[]): number {
  return flattenQuestions(nodes).length;
}

function nodeHaystack(q: Question): string {
  const pointText: string[] = [];
  for (let i = 0; i < q.points.length; i++) {
    const p: AnswerBlock = q.points[i];
    pointText.push(`${p.heading} ${p.body}`);
  }
  return [
    q.id,
    q.title,
    q.question,
    q.gist,
    q.fullAnswer,
    q.angle,
    q.bonus,
    q.redFlags,
    q.sourceLabel,
    pointText.join(' ')
  ].join('\n').toLowerCase();
}

export function nodeMatches(q: Question, query: string, onlyUnmastered: boolean, mastered: string[]): boolean {
  if (onlyUnmastered && mastered.includes(q.id)) {
    return false;
  }
  if (!query) {
    return true;
  }
  return nodeHaystack(q).includes(query);
}

export function treeMatches(q: Question, query: string, onlyUnmastered: boolean, mastered: string[]): boolean {
  if (nodeMatches(q, query, onlyUnmastered, mastered)) {
    return true;
  }
  for (let i = 0; i < q.children.length; i++) {
    if (treeMatches(q.children[i], query, onlyUnmastered, mastered)) {
      return true;
    }
  }
  return false;
}

export function descendantMatchesQuery(q: Question, query: string): boolean {
  if (!query) {
    return false;
  }
  for (let i = 0; i < q.children.length; i++) {
    const child = q.children[i];
    if (nodeHaystack(child).includes(query) || descendantMatchesQuery(child, query)) {
      return true;
    }
  }
  return false;
}

const OPENER =
  '这道题我按 Java 转 Agent 的口径讲：先给能上线的结论，再对照我以前做后端时怎么处理同类问题。';

export function composeFullAnswer(q: Question): string {
  const bodies: string[] = [];
  for (let i = 0; i < q.points.length; i++) {
    const body = q.points[i].body.trim();
    if (body) {
      bodies.push(body);
    }
  }
  const parts: string[] = [
    OPENER,
    `先给一个能写进笔记的结论：${q.gist.trim()}`,
    bodies.join('\n\n'),
    `如果时间还够，我主动补一句：${q.bonus.trim()}`,
    `这些说法我不会往外蹦：${q.redFlags.trim()}`
  ];
  return parts.filter((s: string) => s.length > 0).join('\n\n');
}

export function fullAnswerText(q: Question): string {
  const direct = q.fullAnswer.trim();
  return direct ? direct : composeFullAnswer(q);
}

export function splitForSpeech(text: string, maxLen: number = 160): string[] {
  const cleaned = text.replace(/\s+/g, ' ').trim();
  if (!cleaned) {
    return [];
  }
  const pieces: string[] = [];
  let current = '';
  for (let i = 0; i < cleaned.length; i++) {
    const ch = cleaned.charAt(i);
    current += ch;
    if ('。！？!?；;'.indexOf(ch) >= 0) {
      pieces.push(current);
      current = '';
    }
  }
  if (current) {
    pieces.push(current);
  }
  const chunks: string[] = [];
  let buf = '';
  for (let i = 0; i < pieces.length; i++) {
    const piece = pieces[i];
    const next = `${buf}${piece}`;
    if (next.length > maxLen && buf.trim()) {
      chunks.push(buf.trim());
      buf = piece;
    } else {
      buf = next;
    }
  }
  if (buf.trim()) {
    chunks.push(buf.trim());
  }
  return chunks;
}

export function difficultyColor(difficulty: string): string {
  if (difficulty === '基础') {
    return '#0F7A5A';
  }
  if (difficulty === '进阶') {
    return '#0369A1';
  }
  if (difficulty === '场景') {
    return '#B45309';
  }
  if (difficulty === '深挖') {
    return '#6D28D9';
  }
  return '#E24A16';
}

export function levelLabel(level: number): string {
  if (level === 1) {
    return '面试官提问';
  }
  if (level === 2) {
    return '补充追问';
  }
  return '再追问';
}

export function levelChip(level: number): string {
  if (level === 1) {
    return '父题';
  }
  if (level === 2) {
    return '补充追问';
  }
  return '再追问';
}
