import { useMemo } from "preact/hooks";
import type { GameData } from "../../data/load";
import { resolveEntityName } from "../../data/load";
import { imageURL } from "../../data/images";
import { navigate } from "../router";

/**
 * The Technology page: per-level groups of tech tiles (image + points +
 * name), Ancient Technology highlighted purple (TechnologyTreeView port).
 */
export function TechTree({ data }: { data: GameData }) {
  const levels = useMemo(() => {
    const byLevel = new Map<number, typeof data.technology>();
    for (const tech of data.technology) {
      let bucket = byLevel.get(tech.level);
      if (!bucket) byLevel.set(tech.level, (bucket = []));
      bucket.push(tech);
    }
    return [...byLevel.entries()]
      .sort(([a], [b]) => a - b)
      .map(([level, techs]) => ({
        level,
        techs: techs.sort((a, b) => Number(a.ancient) - Number(b.ancient)),
      }));
  }, [data]);

  return (
    <div class="tech-tree">
      {levels.map((group) => (
        <section key={group.level}>
          <h3 class="tech-level">Level {group.level}</h3>
          <div class="tech-grid">
            {group.techs.map((tech) => {
              const accent = tech.ancient ? "#af52de" : "#30b0c7";
              const id = resolveEntityName(data, tech.name);
              return (
                <button
                  key={tech.name}
                  class="tech-tile"
                  disabled={!id}
                  style={{ background: accent + "1a", borderColor: accent + "59" }}
                  onClick={() => id && navigate(["entity", id])}
                >
                  <span class="tech-kind" style={{ color: accent }}>
                    {tech.ancient ? "Ancient" : tech.structure ? "Structure" : "Item"}
                  </span>
                  <span class="tech-image">
                    <img src={imageURL(tech.image, "items")} alt="" loading="lazy" />
                    <span class="tech-points" style={{ background: accent }}>{tech.points}</span>
                  </span>
                  <span class="tech-name">{tech.name}</span>
                </button>
              );
            })}
          </div>
        </section>
      ))}
    </div>
  );
}
