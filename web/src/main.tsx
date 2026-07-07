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
    loadGameData().then(setData, (e) => setError(String(e)));
  }, []);

  if (error) return <div class="boot-screen">Failed to load game data: {error}</div>;
  if (!data) return <div class="boot-screen">Loading Palpagos Islands…</div>;

  return (
    <div class="app-shell">
      <div class="map-pane">
        <MapPane data={data} />
      </div>
      <LibraryPane data={data} />
    </div>
  );
}

render(<App />, document.getElementById("app")!);
