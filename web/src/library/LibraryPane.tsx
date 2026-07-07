import { useEffect, useRef, useState } from "preact/hooks";
import type { GameData } from "../data/load";
import { imageURL } from "../data/images";
import { navigate, useRoute } from "./router";
import { searchArticles } from "./search";
import { guidesArticles, librarySections, updateArticles } from "./sections";
import { BrowseHome } from "./lists/BrowseHome";
import { PaldexGrid } from "./lists/PaldexGrid";
import { ItemList } from "./lists/ItemList";
import { SkillList } from "./lists/SkillList";
import { ArticleList } from "./lists/ArticleList";
import { EntityPage } from "./entity/EntityPage";

/** Right pane: routed Library content with global search. */
export function LibraryPane({ data }: { data: GameData }) {
  const route = useRoute();
  const [query, setQuery] = useState("");
  const contentRef = useRef<HTMLDivElement>(null);
  const [head, arg] = route.path;

  // a new page starts at its top, like a pushed navigation view
  const routeKey = route.path.join("/");
  useEffect(() => {
    contentRef.current?.scrollTo(0, 0);
    setQuery("");
  }, [routeKey]);

  const title =
    head === "entity" && arg
      ? (data.articleByID.get(arg)?.title ?? arg)
      : head === "section" && arg
        ? (librarySections.find((s) => s.id === arg)?.title ?? "Library")
        : head === "element" && arg
          ? arg.charAt(0).toUpperCase() + arg.slice(1)
          : "Library";

  return (
    <div class="library-pane">
      <header class="library-header">
        {route.path.length > 0 && (
          <button class="back-button" onClick={() => history.back()}>‹</button>
        )}
        <h1>{title}</h1>
        <input
          class="search-field"
          type="search"
          placeholder="Pals, items, skills, guides…"
          value={query}
          onInput={(e) => setQuery((e.target as HTMLInputElement).value)}
        />
      </header>
      <div class="library-content" ref={contentRef}>
        {query.trim() ? (
          <SearchResults data={data} query={query.trim()} onPick={() => setQuery("")} />
        ) : (
          <RouteContent data={data} head={head} arg={arg} />
        )}
      </div>
    </div>
  );
}

function RouteContent({ data, head, arg }: { data: GameData; head?: string; arg?: string }) {
  if (head === "entity" && arg) return <EntityPage data={data} id={arg} />;
  if (head === "element" && arg) return <EntityPage data={data} id={arg} />;
  if (head === "section" && arg) {
    switch (arg) {
      case "pals": return <PaldexGrid data={data} />;
      case "items": return <ItemList items={data.items} kind="items" />;
      case "weapons": return <ItemList items={data.weapons} kind="weapons" />;
      case "skills": return <SkillList data={data} />;
      case "locations": return <ArticleList articles={data.locations.map((l) => data.articleByID.get(l.id)).filter((a) => a != null)} />;
      case "guides": return <ArticleList articles={guidesArticles(data)} />;
      case "updates": return <ArticleList articles={updateArticles(data)} />;
    }
  }
  return <BrowseHome data={data} />;
}

function SearchResults({
  data, query, onPick,
}: {
  data: GameData; query: string; onPick: () => void;
}) {
  const hits = searchArticles(data, query);
  return (
    <div class="search-results">
      {hits.map((article) => {
        const pal = data.palByID.get(article.id);
        const item = pal ? undefined : data.itemByID.get(article.id);
        const thumb = pal
          ? imageURL(pal.image, "pals")
          : item
            ? imageURL(item.image, data.weapons.some((w) => w.id === item.id) ? "weapons" : "items")
            : null;
        return (
          <button
            key={article.id}
            class="item-row"
            onClick={() => { onPick(); navigate(["entity", article.id]); }}
          >
            {thumb ? (
              <img src={thumb} width={36} height={36} alt="" loading="lazy" />
            ) : (
              <span class="search-doc-icon">📄</span>
            )}
            <span class="search-hit-text">
              <span class="item-name">{article.title}</span>
              <span class="search-hit-kind">{article.kind.charAt(0).toUpperCase() + article.kind.slice(1)}</span>
            </span>
          </button>
        );
      })}
      {hits.length === 0 && <p class="placeholder">No results for “{query}”.</p>}
    </div>
  );
}
