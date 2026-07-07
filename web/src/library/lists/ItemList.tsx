import { useMemo } from "preact/hooks";
import type { Item, ImageKind } from "../../data/types";
import { imageURL } from "../../data/images";
import { navigate } from "../router";

/**
 * Items/weapons grouped by type in collapsed disclosure sections with count
 * badges — 729 items is a wall of rows otherwise (ItemListView port).
 */
export function ItemList({ items, kind }: { items: Item[]; kind: ImageKind }) {
  const groups = useMemo(() => {
    const byType = new Map<string, Item[]>();
    for (const item of items) {
      const type = item.type || "Other";
      let bucket = byType.get(type);
      if (!bucket) byType.set(type, (bucket = []));
      bucket.push(item);
    }
    return [...byType.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([type, members]) => ({
        type,
        items: members.sort((a, b) => a.name.localeCompare(b.name)),
      }));
  }, [items]);

  return (
    <div class="item-list">
      {groups.map((group) => (
        <details key={group.type} class="item-group">
          <summary>
            <span class="item-group-title">{group.type}</span>
            <span class="item-group-count">{group.items.length}</span>
          </summary>
          {group.items.map((item) => (
            <button key={item.id} class="item-row" onClick={() => navigate(["entity", item.id])}>
              <img src={imageURL(item.image, kind)} width={32} height={32} alt="" loading="lazy" />
              <span class="item-name">{item.name}</span>
              {item.rarity && item.rarity !== "Common" && (
                <span class={`item-rarity rarity-${item.rarity.toLowerCase()}`}>{item.rarity}</span>
              )}
            </button>
          ))}
        </details>
      ))}
    </div>
  );
}
