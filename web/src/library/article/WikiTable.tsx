import type { GameData } from "../../data/load";
import { resolveEntityName } from "../../data/load";
import type { ArticleTable, TableCell } from "../../data/types";
import { imageURL } from "../../data/images";
import { navigate } from "../router";

// Wikitable rendering — ports the iOS WikiTableView heuristics: wide or
// text-heavy tables become per-row cards with colored stat bubbles and
// material icon chips; narrow tables stay a real grid.

interface FieldStyle {
  color: string;
  symbol: string;
}

/** Field semantics → (tint, symbol) for the colored value bubbles. */
function fieldStyle(header: string): FieldStyle | null {
  const h = header.toLowerCase();
  if (h.includes("damage") || h.includes("attack") || h.includes("power"))
    return { color: "#ff3b30", symbol: "🔥" };
  if (h.includes("durability") || h.includes("defense")) return { color: "#007aff", symbol: "🛡️" };
  if (h.includes("magazine") || h.includes("ammo")) return { color: "#30b0c7", symbol: "🗃️" };
  if (h.includes("gold") || h.includes("price") || h.includes("sell") || h.includes("buy"))
    return { color: "#ff9500", symbol: "💰" };
  if (h.includes("workload")) return { color: "#32ade6", symbol: "🔨" };
  if (h.includes("tech") || h.includes("schematic")) return { color: "#30b0c7", symbol: "🔧" };
  if (h.includes("weight")) return { color: "#8e8e93", symbol: "⚖️" };
  if (h.includes("effect") || h.includes("passive")) return { color: "#af52de", symbol: "✨" };
  if (h.includes("hp") || h.includes("health") || h.includes("nutrition"))
    return { color: "#34c759", symbol: "💚" };
  if (h.includes("level") || h.includes("points")) return { color: "#5856d6", symbol: "⭐" };
  return null;
}

function rarityColor(value: string): string | null {
  switch (value.toLowerCase()) {
    case "common": return "#8e8e93";
    case "uncommon": return "#34c759";
    case "rare": return "#3b82f6";
    case "epic": return "#a855f7";
    case "legendary": return "#f59e0b";
    default: return null;
  }
}

const isMaterialField = (header: string): boolean => {
  const h = header.toLowerCase();
  return h.includes("material") || h.includes("recipe") || h.includes("ingredient");
};

const isShortValue = (header: string, cell: TableCell): boolean =>
  !isMaterialField(header) && cell.t.length <= 16 && !cell.t.includes("\n");

export function WikiTable({ data, table }: { data: GameData; table: ArticleTable }) {
  const widestRow = Math.max(0, ...table.rows.map((r) => r.length));
  const longestCell = Math.max(0, ...table.rows.flatMap((r) => r.map((c) => c.t.length)));
  const useCards = table.headers.length >= 4 || widestRow >= 4 || longestCell > 80;
  return useCards ? <CardTable data={data} table={table} /> : <GridTable data={data} table={table} />;
}

function CardTable({ data, table }: { data: GameData; table: ArticleTable }) {
  const iconColumn = table.headers.findIndex((h) => ["icon", "image"].includes(h.toLowerCase()));
  const legendFields = table.headers
    .map((header, col) => ({ header, col, style: fieldStyle(header) }))
    .filter(({ style, col }) =>
      style &&
      table.rows.some((row) => {
        const cell = row[col];
        return cell && cell.t !== "" && cell.t.length <= 16 && !cell.t.includes("\n");
      }),
    );

  return (
    <div class="wiki-cards-wrap">
      <div class="wiki-cards">
        {table.rows.map((row, i) => (
          <RowCard key={i} data={data} table={table} row={row} iconColumn={iconColumn} />
        ))}
      </div>
      {legendFields.length > 0 && (
        <div class="wiki-legend">
          {legendFields.map(({ header, style }) => (
            <span key={header}>
              <span style={{ color: style!.color }}>{style!.symbol}</span> {header}
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

function RowCard({
  data, table, row, iconColumn,
}: {
  data: GameData; table: ArticleTable; row: TableCell[]; iconColumn: number;
}) {
  const iconFile = iconColumn >= 0 ? row[iconColumn]?.img : undefined;
  const titleIndex = row.findIndex((cell, i) => i !== iconColumn && cell.t !== "");
  const title = titleIndex >= 0 ? row[titleIndex] : undefined;
  const details = row
    .map((cell, i) => ({ header: table.headers[i] ?? "", cell, i }))
    .filter(({ cell, i }) => i !== iconColumn && i !== titleIndex && (cell.t !== "" || cell.img));

  const titleColor = title ? rarityColor(title.t) : null;
  const titleIcon =
    iconFile ??
    title?.img ??
    (title?.l ? (data.palByID.get(title.l)?.image ?? data.itemByID.get(title.l)?.image) : undefined);
  const linked = title?.l && data.articleByID.has(title.l);

  return (
    <div
      class={`wiki-card ${linked ? "linked" : ""}`}
      style={{ borderColor: (titleColor ?? "#8e8e93") + "40", background: (titleColor ?? "#8e8e93") + "14" }}
      onClick={() => linked && navigate(["entity", title!.l!])}
    >
      <div class="wiki-card-title">
        {titleIcon && <img src={imageURL(titleIcon, "items")} alt="" loading="lazy" />}
        <span style={titleColor ? { color: titleColor } : linked ? { color: "var(--accent)" } : undefined}>
          {title?.t ?? ""}
        </span>
      </div>
      <div class="wiki-bubbles">
        {details.map(({ header, cell }) => {
          const style = fieldStyle(header);
          if (!style || !isShortValue(header, cell) || cell.t === "") return null;
          return (
            <span
              key={header}
              class="stat-bubble"
              title={header}
              style={{ background: style.color + "2b", color: style.color }}
            >
              {style.symbol} {cell.t}
            </span>
          );
        })}
      </div>
      {details.map(({ header, cell }) => {
        if (isMaterialField(header) || cell.l || cell.img) {
          return (
            <div key={header} class="wiki-detail">
              {header && <div class="wiki-detail-label">{header}</div>}
              <MaterialChips data={data} value={cell.t} />
            </div>
          );
        }
        if (isShortValue(header, cell) && fieldStyle(header)) return null;
        if (cell.t === "") return null;
        return (
          <div key={header} class="wiki-detail">
            {header && <div class="wiki-detail-label">{header}</div>}
            <div class="wiki-detail-text">{cell.t}</div>
          </div>
        );
      })}
    </div>
  );
}

function MaterialChips({ data, value }: { data: GameData; value: string }) {
  return (
    <div class="entity-chips">
      {value.split("\n").filter((line) => line.trim()).map((line, i) => {
        const id = resolveEntityName(data, line);
        const icon = id ? (data.itemByID.get(id)?.image ?? data.palByID.get(id)?.image) : undefined;
        const linked = id && data.articleByID.has(id);
        return (
          <button
            key={i}
            class={`entity-chip small ${linked ? "" : "unlinked"}`}
            onClick={(e) => { e.stopPropagation(); if (linked) navigate(["entity", id]); }}
          >
            {icon && <img src={imageURL(icon, "items")} alt="" loading="lazy" />}
            {line.trim()}
          </button>
        );
      })}
    </div>
  );
}

function GridTable({ data, table }: { data: GameData; table: ArticleTable }) {
  return (
    <div class="wiki-grid-wrap">
      <table class="wiki-grid">
        {table.headers.length > 0 && (
          <thead>
            <tr>
              {table.headers.map((header) => <th key={header}>{header}</th>)}
            </tr>
          </thead>
        )}
        <tbody>
          {table.rows.map((row, i) => (
            <tr key={i}>
              {row.map((cell, j) => <GridCell key={j} data={data} cell={cell} />)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function GridCell({ data, cell }: { data: GameData; cell: TableCell }) {
  const icon =
    cell.img ??
    (cell.l ? (data.itemByID.get(cell.l)?.image ?? data.palByID.get(cell.l)?.image) : undefined);
  const linked = cell.l && data.articleByID.has(cell.l);
  return (
    <td>
      <span
        class={`wiki-cell ${linked ? "linked" : ""}`}
        onClick={() => linked && navigate(["entity", cell.l!])}
      >
        {icon && <img src={imageURL(icon, "items")} alt="" loading="lazy" />}
        {cell.t}
      </span>
    </td>
  );
}
