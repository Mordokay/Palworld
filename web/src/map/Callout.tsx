import type { GameData } from "../data/load";
import { imageURL, mapIconURL } from "../data/images";
import { navigate } from "../library/router";
import { isVisited, toggleVisited, useMapStore } from "./visited";
import type { MarkerHit } from "./layers";
import { visitedKeyFor } from "./layers";

/** Category icon with fallbacks for layers whose markers are pal artwork. */
export function CategoryIcon({ icon, side }: { icon: string; side: number }) {
  if (icon === "alpha" || icon === "predator") {
    return (
      <span class="category-icon-fallback" style={{ fontSize: side * 0.7, width: side, height: side }}>
        {icon === "alpha" ? "👑" : "⚠️"}
      </span>
    );
  }
  return <img src={mapIconURL(icon)} width={side} height={side} alt="" />;
}

/**
 * Popup body for a tapped marker — ports the iOS calloutCard: title,
 * category, library link for pal markers, jump-to and visited toggle.
 */
export function Callout({
  data, hit, onJump,
}: {
  data: GameData;
  hit: MarkerHit;
  onJump: () => void;
}) {
  useMapStore(); // re-render when the visited set changes
  const key = visitedKeyFor(hit.category.id, hit.marker);
  const seen = isVisited(key);
  const pal = hit.marker.pal ? data.palByLowerName.get(hit.marker.pal) : undefined;

  return (
    <div class="callout">
      <CategoryIcon icon={hit.category.icon} side={34} />
      <div class="callout-text">
        <div class="callout-title">{hit.marker.name || hit.category.name}</div>
        <div class="callout-subtitle">{hit.category.name}</div>
      </div>
      {pal && (
        <button
          class="callout-button"
          title="Open in Library"
          onClick={() => navigate(["entity", pal.id])}
        >
          <img src={imageURL(pal.image, "pals")} width={28} height={28} alt="" />
          <span>📖</span>
        </button>
      )}
      <button class="callout-button" title="Center on this point" onClick={onJump}>
        🎯
      </button>
      <button
        class={`callout-button ${seen ? "callout-visited" : ""}`}
        title={seen ? "Visited — click to unmark" : "Mark as visited"}
        onClick={() => toggleVisited(key)}
      >
        {seen ? "✅" : "☑️"}
      </button>
    </div>
  );
}
