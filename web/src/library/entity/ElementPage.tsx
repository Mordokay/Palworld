import type { GameData } from "../../data/load";
import type { Pal } from "../../data/types";
import { imageURL } from "../../data/images";
import { allElements, damageMultiplier, elementColor, elementIconFile } from "../../theme";
import { navigate } from "../router";
import { LinkedText } from "../article/LinkedText";
import { ElementChip } from "./shared";

/**
 * Custom page for the nine elements: icon header, strengths/weaknesses,
 * article prose, the element's skills, and pal grids (ElementPageView port).
 */
export function ElementPage({ data, element }: { data: GameData; element: string }) {
  const color = elementColor(element);
  const strongAgainst = allElements.filter((e) => damageMultiplier([e], element) > 1);
  const weakAgainst = allElements.filter((e) => damageMultiplier([e], element) < 1);

  const members = data.pals
    .filter((p) => p.elements.some((e) => e.toLowerCase() === element.toLowerCase()))
    .sort((a, b) => (a.number || "999").localeCompare(b.number || "999"));
  const subspecies = members.filter((p) => p.categories.some((c) => c.endsWith("Subspecies")));
  const regular = members.filter((p) => !subspecies.includes(p));

  const skills = data.skills
    .filter((s) => s.element.toLowerCase() === element.toLowerCase())
    .sort((a, b) => (a.power ?? 0) - (b.power ?? 0));

  const article = data.articleByID.get(element.toLowerCase());
  const isPalList = (heading: string) => {
    const h = heading.toLowerCase();
    return h.includes("pals") || h.includes("subspecies") || h.includes("skills");
  };

  return (
    <div class="element-page">
      <div class="card-hero">
        <img class="element-hero-icon" src={imageURL(elementIconFile(element), "ui")} alt="" />
        <h2 class="element-hero-name" style={{ color }}>{cap(element)}</h2>
      </div>

      <div class="matchup-columns">
        <MatchupColumn title="Strong against" elements={strongAgainst} tint="#34c759" arrow="▲" />
        <MatchupColumn title="Weak against" elements={weakAgainst} tint="#ff3b30" arrow="▼" />
      </div>

      {article?.sections.map((section, i) =>
        !isPalList(section.heading) && section.text ? (
          <section key={i} class="article-section">
            {section.heading && <h3 class="section-heading">{section.heading}</h3>}
            <LinkedText data={data} text={section.text} selfID={article.id} />
          </section>
        ) : null,
      )}

      {skills.length > 0 && (
        <section class="article-section">
          <h3 class="section-heading">{cap(element)} Skills</h3>
          <div class="entity-chips">
            {skills.map((skill) => (
              <button key={skill.id} class="entity-chip" onClick={() => navigate(["entity", skill.id])}>
                {skill.name}{skill.power != null ? ` · ${skill.power}` : ""}
              </button>
            ))}
          </div>
        </section>
      )}

      <PalGridSection title={`${cap(element)} Pals`} pals={regular} tint={elementColor(element, 0.1)} />
      <PalGridSection title="Subspecies" pals={subspecies} tint={elementColor(element, 0.1)} />
    </div>
  );
}

const cap = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1);

function MatchupColumn({
  title, elements, tint, arrow,
}: {
  title: string; elements: string[]; tint: string; arrow: string;
}) {
  return (
    <div class="matchup-column">
      <div class="matchup-title" style={{ color: tint }}>{arrow} {title}</div>
      {elements.length === 0 && <span class="matchup-none">None</span>}
      {elements.map((e) => <ElementChip key={e} element={e} small />)}
    </div>
  );
}

function PalGridSection({ title, pals, tint }: { title: string; pals: Pal[]; tint: string }) {
  if (pals.length === 0) return null;
  return (
    <section class="article-section">
      <h3 class="section-heading">{title}</h3>
      <div class="pal-mini-grid">
        {pals.map((pal) => (
          <button
            key={pal.id}
            class="paldex-cell mini"
            style={{ background: tint }}
            onClick={() => navigate(["entity", pal.id])}
          >
            <img src={imageURL(pal.image, "pals")} alt="" loading="lazy" />
            <span class="paldex-name">{pal.name}</span>
          </button>
        ))}
      </div>
    </section>
  );
}
