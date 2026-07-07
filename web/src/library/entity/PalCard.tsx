import type { GameData } from "../../data/load";
import type { Pal } from "../../data/types";
import { imageURL } from "../../data/images";
import { allElements, damageMultiplier, elementColor, elementIconFile, workIconFile, workLabel } from "../../theme";
import { navigate, setQueryParams } from "../router";
import { CardSection, ElementChip, EntityChips } from "./shared";

/** Pal detail card — ports EntityPageView.palCard section by section. */
export function PalCard({ data, pal }: { data: GameData; pal: Pal }) {
  const stats = pal.stats;
  const hasStats = stats && (stats.hp != null || stats.attack != null || stats.defense != null);
  const work = Object.entries(pal.workSuitability).sort(([, a], [, b]) => b - a);

  return (
    <div class="pal-card">
      <div class="card-hero">
        <img class="hero-image" src={imageURL(pal.image, "pals")} alt={pal.name} />
        {pal.number && <div class="hero-number">#{pal.number}</div>}
        <div class="chips-row">
          {pal.elements.map((element) => <ElementChip key={element} element={element} />)}
        </div>
        {pal.alphaTitle && <div class="hero-alpha-title">{pal.alphaTitle}</div>}
      </div>

      {hasStats && stats && (
        <CardSection title="Stats">
          <div class="stats-grid">
            <StatColumn label="HP" color="#34c759" base={stats.hp} range={stats.hpLv50Range} />
            <StatColumn label="Attack" color="#ff3b30" base={stats.attack} range={stats.attackLv50Range} />
            <StatColumn label="Defense" color="#007aff" base={stats.defense} range={stats.defenseLv50Range} />
          </div>
        </CardSection>
      )}

      {pal.partnerSkill.name && (
        <CardSection title="Partner Skill">
          <div class="partner-skill-name">{pal.partnerSkill.name}</div>
          <p class="body-text">{pal.partnerSkill.description}</p>
        </CardSection>
      )}

      {pal.foodAmount != null && (
        <CardSection title="Food">
          <div class="food-meter">
            {Array.from({ length: 10 }, (_, i) => (
              <img
                key={i}
                src={imageURL("Food_on_icon.png", "ui")}
                class={i < (pal.foodAmount ?? 0) ? "" : "food-off"}
                alt=""
              />
            ))}
          </div>
        </CardSection>
      )}

      {work.length > 0 && (
        <CardSection title="Work Suitability">
          <div class="work-grid">
            {work.map(([key, stars]) => (
              <div key={key} class="work-row">
                <img src={imageURL(workIconFile(key), "ui")} alt="" />
                <span class="work-label">{workLabel(key)}</span>
                <span class="work-stars">{"★".repeat(stars)}</span>
              </div>
            ))}
          </div>
        </CardSection>
      )}

      {pal.drops.length > 0 && (
        <CardSection title="Drops">
          <EntityChips data={data} refs={pal.drops} />
        </CardSection>
      )}
      {pal.alphaDrops.length > 0 && (
        <CardSection title="Alpha Drops">
          <EntityChips data={data} refs={pal.alphaDrops} />
        </CardSection>
      )}
      {pal.farmingProduce.length > 0 && (
        <CardSection title="Farming Produce">
          <EntityChips data={data} refs={pal.farmingProduce} />
        </CardSection>
      )}

      {(pal.habitatDay || pal.habitatNight) && <HabitatSection pal={pal} />}

      {pal.elements.length > 0 && (
        <CardSection title="Elemental Effectiveness">
          <div class="effectiveness-strip">
            {allElements.map((attacker) => {
              const x = damageMultiplier(pal.elements, attacker);
              return (
                <div key={attacker} class="effect-cell">
                  <img src={imageURL(elementIconFile(attacker), "ui")} alt={attacker} />
                  <span
                    class="effect-value"
                    style={{
                      color: x > 1 ? "#ff3b30" : x < 1 ? "#34c759" : "var(--text-secondary)",
                      fontWeight: x !== 1 ? 700 : 400,
                    }}
                  >
                    {x}×
                  </span>
                </div>
              );
            })}
          </div>
        </CardSection>
      )}

      {pal.activeSkills.length > 0 && (
        <CardSection title="Active Skills">
          <div class="active-skills">
            {pal.activeSkills.map((learned) => {
              const id = data.idByName.get(learned.name.toLowerCase());
              const skill = id ? data.skillByID.get(id) : undefined;
              return (
                <button
                  key={learned.name}
                  class="skill-row"
                  disabled={!id}
                  onClick={() => id && navigate(["entity", id])}
                >
                  <span
                    class="skill-level"
                    style={{ background: elementColor(skill?.element ?? "", 0.25), color: elementColor(skill?.element ?? "") }}
                  >
                    Lv {learned.level ?? "?"}
                  </span>
                  <span class="skill-row-name">{learned.name}</span>
                  {skill?.power != null && <span class="skill-power">{skill.power}</span>}
                  {skill?.cooldown != null && <span class="skill-ct">CT {skill.cooldown}s</span>}
                </button>
              );
            })}
          </div>
        </CardSection>
      )}

      {pal.saddleTech && (
        <CardSection title="Mount">
          <p class="body-text">
            {pal.saddleTech}
            {pal.saddleTechLevel != null && (
              <span class="tag-chip" style={{ marginLeft: 8 }}>Tech {pal.saddleTechLevel}</span>
            )}
          </p>
        </CardSection>
      )}
    </div>
  );
}

function StatColumn({
  label, color, base, range,
}: {
  label: string; color: string; base: number | null; range: (number | null)[];
}) {
  const [low, high] = range;
  return (
    <div class="stat-column">
      <div class="stat-label" style={{ color }}>{label}</div>
      <div class="stat-base">{base ?? "—"}</div>
      {low != null && high != null && <div class="stat-range">{low}–{high} @50</div>}
    </div>
  );
}

function HabitatSection({ pal }: { pal: Pal }) {
  return (
    <CardSection title="Habitat">
      <div class="habitat-images">
        {pal.habitatDay && (
          <figure>
            <img src={imageURL(pal.habitatDay, "maps")} alt={`${pal.name} day habitat`} loading="lazy" />
            <figcaption>Day</figcaption>
          </figure>
        )}
        {pal.habitatNight && (
          <figure>
            <img src={imageURL(pal.habitatNight, "maps")} alt={`${pal.name} night habitat`} loading="lazy" />
            <figcaption>Night</figcaption>
          </figure>
        )}
      </div>
      <button
        class="show-on-map"
        onClick={() => setQueryParams({ spawn: pal.name.toLowerCase(), side: null })}
      >
        📍 Show spawn points on the Map
      </button>
    </CardSection>
  );
}
