import { useMemo, useState } from "preact/hooks";
import type { GameData } from "../../data/load";
import { imageURL } from "../../data/images";
import { allWorkKeys, elementColor, workColor, workIconFile, workLabel } from "../../theme";
import { navigate } from "../router";

/**
 * 3-column paldex grid with a name search and a multi-select work-suitability
 * filter. Tapping the colored work bubbles keeps only pals that have ALL the
 * selected works and sorts by the SUM of their levels — e.g. select Mining +
 * Kindling to find the best pal at both. Tap a pal to see where it spawns.
 */
export function PaldexGrid({ data }: { data: GameData }) {
  const [query, setQuery] = useState("");
  const [workFilters, setWorkFilters] = useState<Set<string>>(new Set());
  const [descending, setDescending] = useState(true);

  const selectedKeys = allWorkKeys.filter((k) => workFilters.has(k));

  const toggle = (key: string) => {
    setWorkFilters((prev) => {
      const next = new Set(prev);
      if (!next.delete(key)) next.add(key);
      return next;
    });
  };

  const pals = useMemo(() => {
    const q = query.trim().toLowerCase();
    const byNumber = (a: (typeof data.pals)[number], b: typeof a) => {
      const na = a.number || "999";
      const nb = b.number || "999";
      return na === nb ? a.name.localeCompare(b.name) : Number(na) - Number(nb) || na.localeCompare(nb);
    };
    const total = (p: (typeof data.pals)[number]) =>
      selectedKeys.reduce((sum, k) => sum + (p.workSuitability[k] ?? 0), 0);

    let list = data.pals.filter((p) => !q || p.name.toLowerCase().includes(q));
    if (selectedKeys.length > 0) {
      list = list.filter((p) => selectedKeys.every((k) => (p.workSuitability[k] ?? 0) > 0));
      list = list.sort((a, b) => {
        const diff = total(b) - total(a);
        return (descending ? diff : -diff) || byNumber(a, b);
      });
    } else {
      list = [...list].sort(byNumber);
    }
    return list;
  }, [data, query, workFilters, descending]);

  return (
    <div class="paldex">
      <div class="paldex-controls">
        <input
          class="search-field wide"
          type="search"
          placeholder="Pal name"
          value={query}
          onInput={(e) => setQuery((e.target as HTMLInputElement).value)}
        />
        <div class="work-bubbles">
          {allWorkKeys.map((key) => {
            const active = workFilters.has(key);
            return (
              <button
                key={key}
                class={`work-bubble ${active ? "active" : ""}`}
                style={
                  active
                    ? { background: workColor(key, 0.28), borderColor: workColor(key), color: workColor(key) }
                    : undefined
                }
                onClick={() => toggle(key)}
              >
                <img src={imageURL(workIconFile(key), "ui")} alt="" />
                {workLabel(key)}
              </button>
            );
          })}
        </div>
        {selectedKeys.length > 0 && (
          <div class="paldex-sort-row">
            <button class="order-toggle" onClick={() => setDescending((d) => !d)}>
              {descending ? "▼ Highest combined" : "▲ Lowest combined"}
            </button>
            <button class="clear-works" onClick={() => setWorkFilters(new Set())}>
              Clear
            </button>
          </div>
        )}
      </div>

      {selectedKeys.length > 0 && (
        <p class="paldex-result-note">
          {pals.length} pal{pals.length === 1 ? "" : "s"} with{" "}
          {selectedKeys.map(workLabel).join(" + ")} — tap one to see its spawn map.
        </p>
      )}

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
            {selectedKeys.length > 0 ? (
              <span class="paldex-work-lines">
                {selectedKeys.map((key) => (
                  <span key={key} class="paldex-work-line">
                    <img src={imageURL(workIconFile(key), "ui")} alt="" />
                    <span class="wstars" style={{ color: workColor(key) }}>
                      {"★".repeat(pal.workSuitability[key] ?? 0)}
                    </span>
                  </span>
                ))}
              </span>
            ) : (
              <span class="paldex-number">{pal.number ? `#${pal.number}` : "—"}</span>
            )}
          </button>
        ))}
      </div>
    </div>
  );
}
