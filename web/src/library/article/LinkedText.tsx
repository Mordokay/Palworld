import type { GameData } from "../../data/load";
import { navigate } from "../router";

// Prose auto-linking — ports the iOS LinkedText: known entity names become
// links at their FIRST word-boundary occurrence, longest names first so
// "Lamball Mutton" wins over "Lamball"; names under 4 chars never link.

interface Segment {
  text: string;
  id?: string;
}

let cachedIndex: { data: GameData; index: [string, string][] } | null = null;

function linkIndex(data: GameData): [string, string][] {
  if (cachedIndex?.data === data) return cachedIndex.index;
  const index = [...data.idByName.entries()].sort((a, b) => b[0].length - a[0].length);
  cachedIndex = { data, index };
  return index;
}

const isLetter = (ch: string | undefined): boolean =>
  !!ch && ch.toLowerCase() !== ch.toUpperCase();

/** First occurrence of `name` in `lower` with non-letter boundaries. */
function boundaryIndex(name: string, lower: string): number {
  let start = 0;
  for (;;) {
    const i = lower.indexOf(name, start);
    if (i === -1) return -1;
    const beforeOK = i === 0 || !isLetter(lower[i - 1]);
    const afterOK = i + name.length >= lower.length || !isLetter(lower[i + name.length]);
    if (beforeOK && afterOK) return i;
    start = i + name.length;
  }
}

export function linkSegments(data: GameData, text: string, selfID: string): Segment[] {
  const lower = text.toLowerCase();
  const ranges: { start: number; end: number; id: string }[] = [];
  for (const [name, id] of linkIndex(data)) {
    if (id === selfID || name.length < 4) continue;
    const start = boundaryIndex(name, lower);
    if (start === -1) continue;
    const end = start + name.length;
    if (ranges.some((r) => start < r.end && end > r.start)) continue;
    ranges.push({ start, end, id });
  }
  ranges.sort((a, b) => a.start - b.start);

  const segments: Segment[] = [];
  let pos = 0;
  for (const range of ranges) {
    if (range.start > pos) segments.push({ text: text.slice(pos, range.start) });
    segments.push({ text: text.slice(range.start, range.end), id: range.id });
    pos = range.end;
  }
  if (pos < text.length) segments.push({ text: text.slice(pos) });
  return segments;
}

export function LinkedText({
  data, text, selfID,
}: {
  data: GameData; text: string; selfID: string;
}) {
  return (
    <p class="body-text prose">
      {linkSegments(data, text, selfID).map((segment, i) =>
        segment.id ? (
          <a
            key={i}
            class="entity-link"
            href={`#/entity/${segment.id}`}
            onClick={(e) => { e.preventDefault(); navigate(["entity", segment.id!]); }}
          >
            {segment.text}
          </a>
        ) : (
          segment.text
        ),
      )}
    </p>
  );
}
