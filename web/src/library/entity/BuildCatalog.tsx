import type { GameData } from "../../data/load";
import { imageURL } from "../../data/images";
import { navigate } from "../router";

const STRUCTURE_TYPES = [
  "Production", "Pal", "Storage", "Infrastructure", "Lighting",
  "Foundations", "Defenses", "Furniture", "Other",
];

/**
 * Everything buildable, grouped by structure type, generated from item data
 * (BuildCatalogView port — the wiki's own tables are server-side queries).
 */
export function BuildCatalog({ data }: { data: GameData }) {
  return (
    <div class="build-catalog">
      {STRUCTURE_TYPES.map((type) => {
        const members = data.items
          .filter((i) => i.type === type && (i.techTier != null || i.craftMaterials.length > 0))
          .sort((a, b) => (a.techTier ?? 99) - (b.techTier ?? 99) || a.name.localeCompare(b.name));
        if (members.length === 0) return null;
        return (
          <section key={type}>
            <h3 class="tech-level">{type} · {members.length}</h3>
            <div class="build-grid">
              {members.map((item) => (
                <button key={item.id} class="build-tile" onClick={() => navigate(["entity", item.id])}>
                  <img src={imageURL(item.image, "items")} alt="" loading="lazy" />
                  <span class="build-tile-text">
                    <span class="build-tile-name">{item.name}</span>
                    {item.techTier != null && <span class="build-tile-tier">Tech {item.techTier}</span>}
                  </span>
                </button>
              ))}
            </div>
          </section>
        );
      })}
    </div>
  );
}
