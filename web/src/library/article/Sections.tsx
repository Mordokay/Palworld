import type { GameData } from "../../data/load";
import { resolveEntityName } from "../../data/load";
import type { Article } from "../../data/types";
import { imageURL } from "../../data/images";
import { elementColor } from "../../theme";
import { navigate } from "../router";
import { LinkedText } from "./LinkedText";
import { WikiTable } from "./WikiTable";

/**
 * Article body renderer: headings, auto-linked prose, entity chip-list runs
 * (2+ consecutive resolvable lines), pal image grids (4+ all-pal runs),
 * wiki tables and image galleries — the SectionBody/articleSections port.
 */
export function ArticleSections({
  data, article, hideHeadings = [],
}: {
  data: GameData;
  article: Article;
  hideHeadings?: string[];
}) {
  const hidden = new Set(hideHeadings.map((h) => h.toLowerCase()));
  return (
    <div class="article-sections">
      {article.sections.map((section, i) => {
        if (hidden.has(section.heading.toLowerCase())) return null;
        const empty =
          !section.heading && !section.text.trim() &&
          !section.tables?.length && !section.images?.length;
        if (empty) return null;
        return (
          <section key={i} class="article-section">
            {section.heading &&
              (section.level === 3 ? (
                <h4 class="section-heading sub">{section.heading}</h4>
              ) : (
                <h3 class="section-heading">{section.heading}</h3>
              ))}
            {section.text && <SectionBody data={data} text={section.text} selfID={article.id} />}
            {section.tables?.map((table, j) => <WikiTable key={j} data={data} table={table} />)}
            {section.images && section.images.length > 0 && (
              <div class="section-gallery">
                {section.images.map((image) => (
                  <figure key={image.file}>
                    <img src={imageURL(image.file, "articles")} alt={image.caption} loading="lazy" />
                    {image.caption && <figcaption>{image.caption}</figcaption>}
                  </figure>
                ))}
              </div>
            )}
          </section>
        );
      })}
    </div>
  );
}

type Block =
  | { kind: "prose"; text: string }
  | { kind: "chips"; entries: { label: string; id: string }[] }
  | { kind: "palGrid"; entries: { label: string; id: string }[] };

/**
 * Runs of 2+ consecutive lines that each resolve to an entity name (the
 * wiki's link lists) become icon chips; 4+ all-pal runs become an image grid;
 * everything else stays auto-linked prose. Ports iOS SectionBody.blocks.
 */
function toBlocks(data: GameData, text: string): Block[] {
  const result: Block[] = [];
  let prose: string[] = [];
  let run: { label: string; id: string }[] = [];

  const flushProse = () => {
    const joined = prose.join("\n");
    if (joined.trim()) result.push({ kind: "prose", text: joined });
    prose = [];
  };
  const flushRun = () => {
    if (run.length === 0) return;
    flushProse();
    if (run.length >= 4 && run.every((e) => data.palByID.has(e.id))) {
      result.push({ kind: "palGrid", entries: run });
    } else {
      result.push({ kind: "chips", entries: run });
    }
    run = [];
  };

  for (const line of text.split("\n")) {
    // strip list bullets and indent (•, ◦, em-space)
    const candidate = line.replace(/^[•◦  \t]+|[•◦  \t]+$/g, "");
    const id = candidate && candidate.length <= 60 ? resolveEntityName(data, candidate) : null;
    if (id) {
      run.push({ label: candidate, id });
    } else {
      flushRun();
      prose.push(line);
    }
  }
  flushRun();
  flushProse();
  return result;
}

export function SectionBody({
  data, text, selfID,
}: {
  data: GameData; text: string; selfID: string;
}) {
  return (
    <>
      {toBlocks(data, text).map((block, i) => {
        switch (block.kind) {
          case "prose":
            return <LinkedText key={i} data={data} text={block.text} selfID={selfID} />;
          case "chips":
            return (
              <div key={i} class="entity-chips">
                {block.entries.map((entry) => {
                  const icon =
                    data.palByID.get(entry.id)?.image ?? data.itemByID.get(entry.id)?.image;
                  const kind = data.palByID.has(entry.id) ? "pals" : "items";
                  return (
                    <button
                      key={entry.label}
                      class="entity-chip"
                      onClick={() => navigate(["entity", entry.id])}
                    >
                      {icon && <img src={imageURL(icon, kind)} alt="" loading="lazy" />}
                      {entry.label}
                    </button>
                  );
                })}
              </div>
            );
          case "palGrid":
            return (
              <div key={i} class="pal-mini-grid">
                {block.entries.map((entry) => {
                  const pal = data.palByID.get(entry.id)!;
                  return (
                    <button
                      key={entry.id}
                      class="paldex-cell mini"
                      style={{ background: elementColor(pal.elements[0] ?? "", 0.1) }}
                      onClick={() => navigate(["entity", entry.id])}
                    >
                      <img src={imageURL(pal.image, "pals")} alt="" loading="lazy" />
                      <span class="paldex-name">{entry.label}</span>
                    </button>
                  );
                })}
              </div>
            );
        }
      })}
    </>
  );
}
