import type { GameData } from "../data/load";
import { useRoute } from "./router";
import { PaldexGrid } from "./lists/PaldexGrid";

/**
 * Right pane: routed library content. M1 ships the Paldex grid; browse home,
 * the other list views, search and entity pages arrive in M4/M5.
 */
export function LibraryPane({ data }: { data: GameData }) {
  const route = useRoute();
  const [head, arg] = route.path;

  let content;
  if (head === "entity" && arg) {
    content = <p class="placeholder">Entity page for “{arg}” — coming in M4.</p>;
  } else {
    content = <PaldexGrid data={data} />;
  }

  return (
    <div class="library-pane">
      <header class="library-header">
        <h1>Library</h1>
      </header>
      <div class="library-content">{content}</div>
    </div>
  );
}
