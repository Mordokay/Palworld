import type { ComponentChildren } from "preact";
import type { GameData } from "../../data/load";
import { resolveEntityName, strippedName } from "../../data/load";
import { imageURL } from "../../data/images";
import { elementColor, elementIconFile } from "../../theme";
import { navigate } from "../router";

/** Capsule chip for an element type — game icon + 20% tinted background. */
export function ElementChip({ element, small }: { element: string; small?: boolean }) {
  return (
    <button
      class={`element-chip ${small ? "small" : ""}`}
      style={{ background: elementColor(element, 0.2), color: elementColor(element) }}
      onClick={() => navigate(["element", element.toLowerCase()])}
    >
      <img src={imageURL(elementIconFile(element), "ui")} alt="" />
      {element}
    </button>
  );
}

/**
 * Chip list for decorated entity references like "3-5 Bone (100%)": icon of
 * the resolved entity + display label, linked when the target is known.
 */
export function EntityChips({ data, refs }: { data: GameData; refs: string[] }) {
  return (
    <div class="entity-chips">
      {refs.map((raw) => {
        const id = resolveEntityName(data, raw);
        const image = id
          ? (data.palByID.get(id)?.image ?? data.itemByID.get(id)?.image)
          : undefined;
        const kind = id && data.palByID.has(id) ? "pals" : "items";
        return (
          <button
            key={raw}
            class={`entity-chip ${id ? "" : "unlinked"}`}
            onClick={() => id && navigate(["entity", id])}
          >
            {image && <img src={imageURL(image, kind)} alt="" loading="lazy" />}
            {strippedName(raw)}
          </button>
        );
      })}
    </div>
  );
}

export function CardSection({ title, children }: { title: string; children: ComponentChildren }) {
  return (
    <section class="card-section">
      <h3>{title}</h3>
      {children}
    </section>
  );
}

export function TagChip({ text }: { text: string }) {
  return text ? <span class="tag-chip">{text}</span> : null;
}
