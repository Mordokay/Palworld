import { useMemo } from "preact/hooks";
import type { GameData } from "../../data/load";
import { imageURL } from "../../data/images";
import { elementColor } from "../../theme";
import { navigate } from "../router";

/** 3-column paldex grid, sorted by number then name (LibraryView port). */
export function PaldexGrid({ data, filter = "" }: { data: GameData; filter?: string }) {
  const pals = useMemo(() => {
    const q = filter.trim().toLowerCase();
    return [...data.pals]
      .filter((p) => !q || p.name.toLowerCase().includes(q))
      .sort((a, b) => {
        const na = a.number || "999";
        const nb = b.number || "999";
        return na === nb
          ? a.name.localeCompare(b.name)
          : Number(na) - Number(nb) || na.localeCompare(nb);
      });
  }, [data, filter]);

  return (
    <div class="paldex-grid">
      {pals.map((pal) => (
        <button
          key={pal.id}
          class="paldex-cell"
          style={{ background: elementColor(pal.elements[0] ?? "", 0.1) }}
          onClick={() => navigate(["entity", pal.id])}
        >
          <img src={imageURL(pal.image, "pals")} alt={pal.name} loading="lazy" />
          <span class="paldex-name">{pal.name}</span>
          <span class="paldex-number">{pal.number ? `#${pal.number}` : "—"}</span>
        </button>
      ))}
    </div>
  );
}
