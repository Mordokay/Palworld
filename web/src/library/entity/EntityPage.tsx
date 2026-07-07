import type { GameData } from "../../data/load";
import { imageURL } from "../../data/images";
import { ArticleSections } from "../article/Sections";
import { PalCard } from "./PalCard";
import { CardSection, ElementChip, EntityChips, TagChip } from "./shared";

// Article headings hidden on entity pages because the card already renders
// that data (EntityPageView port).
const PAL_HIDDEN = ["paldeck entry", "stats", "utility", "active skills", "elemental effectiveness", "breeding"];
const SKILL_HIDDEN = ["learnset", "pals"];

/** Dispatch an entity/article id to its card + article body. */
export function EntityPage({ data, id }: { data: GameData; id: string }) {
  const article = data.articleByID.get(id);
  const pal = data.palByID.get(id);
  const item = pal ? undefined : data.itemByID.get(id);
  const skill = pal || item ? undefined : data.skillByID.get(id);
  const location = pal || item || skill ? undefined : data.locations.find((l) => l.id === id);

  return (
    <div class="entity-page">
      <h2 class="entity-title">{article?.title ?? pal?.name ?? id}</h2>
      {pal && <PalCard data={data} pal={pal} />}
      {item && <ItemCard data={data} id={id} />}
      {skill && <SkillCard data={data} id={id} />}
      {location && <LocationCard data={data} id={id} />}
      {article && (
        <ArticleSections
          data={data}
          article={article}
          hideHeadings={pal ? PAL_HIDDEN : skill ? SKILL_HIDDEN : []}
        />
      )}
      {!article && !pal && !item && !skill && !location && (
        <p class="placeholder">Nothing in the Library for “{id}”.</p>
      )}
    </div>
  );
}

function ItemCard({ data, id }: { data: GameData; id: string }) {
  const item = data.itemByID.get(id)!;
  const kind = data.weapons.some((w) => w.id === id) ? "weapons" : "items";
  return (
    <div class="pal-card">
      <div class="card-hero">
        <img class="hero-image item" src={imageURL(item.image, kind)} alt={item.name} />
        <div class="chips-row">
          <TagChip text={item.type} />
          {item.rarity && <TagChip text={item.rarity} />}
        </div>
        {item.description && <p class="body-text centered">{item.description}</p>}
      </div>
      <div class="stat-pills">
        {item.damage != null && <span class="stat-pill" style={{ color: "#ff3b30" }}>⚔ {item.damage}</span>}
        {item.techTier != null && <span class="stat-pill" style={{ color: "#30b0c7" }}>Tech {item.techTier}</span>}
        {item.goldBuy != null && <span class="stat-pill" style={{ color: "#ff9500" }}>💰 {item.goldBuy}</span>}
        {item.nutrition != null && <span class="stat-pill" style={{ color: "#34c759" }}>🍖 {item.nutrition}</span>}
      </div>
      {item.craftMaterials.length > 0 && (
        <CardSection title="Recipe">
          <EntityChips data={data} refs={item.craftMaterials} />
        </CardSection>
      )}
    </div>
  );
}

function SkillCard({ data, id }: { data: GameData; id: string }) {
  const skill = data.skillByID.get(id)!;
  const typeLabel =
    skill.skillType === "ex_active" ? "Exclusive Active"
    : skill.skillType === "active" ? "Active" : "Passive";
  return (
    <div class="pal-card">
      <div class="card-hero">
        <div class="chips-row">
          {skill.element && <ElementChip element={skill.element} />}
          <TagChip text={typeLabel} />
        </div>
        <div class="stat-pills">
          {skill.power != null && <span class="stat-pill" style={{ color: "#ff3b30" }}>Power {skill.power}</span>}
          {skill.cooldown != null && <span class="stat-pill" style={{ color: "#30b0c7" }}>CT {skill.cooldown}s</span>}
        </div>
        {skill.description && <p class="body-text centered">{skill.description}</p>}
      </div>
      {skill.exclusiveTo.length > 0 && (
        <CardSection title="Exclusive to">
          <EntityChips data={data} refs={skill.exclusiveTo} />
        </CardSection>
      )}
    </div>
  );
}

function LocationCard({ data, id }: { data: GameData; id: string }) {
  const location = data.locations.find((l) => l.id === id)!;
  return (
    <div class="pal-card">
      <div class="card-hero">
        {location.image && (
          <img class="hero-image wide" src={imageURL(location.image, "locations")} alt={location.name} />
        )}
        <div class="chips-row">
          <TagChip text={location.type} />
          <TagChip text={location.region} />
          {location.level && <TagChip text={`Lv ${location.level}`} />}
        </div>
      </div>
      {location.inhabitants.length > 0 && (
        <CardSection title="Inhabitants">
          <EntityChips data={data} refs={location.inhabitants} />
        </CardSection>
      )}
    </div>
  );
}
