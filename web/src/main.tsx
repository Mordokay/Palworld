import { render } from "preact";
import { useEffect, useState } from "preact/hooks";
import { loadGameData, type GameData } from "./data/load";
import { LibraryPane } from "./library/LibraryPane";
import { MapPane } from "./map/MapPane";
import "./styles.css";

function App() {
  const [data, setData] = useState<GameData | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadGameData().then((loaded) => {
      if (import.meta.env.DEV) {
        (window as unknown as Record<string, unknown>).__data = loaded;
      }
      setData(loaded);
    }, (e) => setError(String(e)));
  }, []);

  // narrow screens can't fit the dual pane — fall back to a Map|Library
  // switcher; both panes stay mounted so Leaflet keeps its state
  const [mobileTab, setMobileTab] = useState<"map" | "library">("map");

  if (error) return <div class="boot-screen">Failed to load game data: {error}</div>;
  if (!data) return <div class="boot-screen">Loading Palpagos Islands…</div>;

  return (
    <div class={`app-shell show-${mobileTab}`}>
      <nav class="mobile-tabs">
        <button class={mobileTab === "map" ? "active" : ""} onClick={() => setMobileTab("map")}>
          🗺️ Map
        </button>
        <button class={mobileTab === "library" ? "active" : ""} onClick={() => setMobileTab("library")}>
          📚 Library
        </button>
      </nav>
      <div class="map-pane">
        <MapPane data={data} />
      </div>
      <LibraryPane data={data} />
    </div>
  );
}

render(<App />, document.getElementById("app")!);
