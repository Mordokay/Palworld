import { useMemo } from "preact/hooks";
import type { GameData } from "../../data/load";
import { elementColor } from "../../theme";
import { navigate } from "../router";

/** Skills grouped by element, power-sorted within (SkillListView port). */
export function SkillList({ data }: { data: GameData }) {
  const groups = useMemo(() => {
    const byElement = new Map<string, typeof data.skills>();
    for (const skill of data.skills) {
      const element = skill.element || "Other";
      let bucket = byElement.get(element);
      if (!bucket) byElement.set(element, (bucket = []));
      bucket.push(skill);
    }
    return [...byElement.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([element, skills]) => ({
        element,
        skills: skills.sort((a, b) => (a.power ?? 0) - (b.power ?? 0)),
      }));
  }, [data]);

  return (
    <div class="skill-list">
      {groups.map((group) => (
        <section key={group.element}>
          <h3 class="skill-group-header" style={{ color: elementColor(group.element) }}>
            {group.element}
          </h3>
          {group.skills.map((skill) => (
            <button key={skill.id} class="item-row" onClick={() => navigate(["entity", skill.id])}>
              <span class="skill-dot" style={{ background: elementColor(skill.element) }} />
              <span class="item-name">{skill.name}</span>
              {skill.power != null && <span class="skill-power">{skill.power}</span>}
            </button>
          ))}
        </section>
      ))}
    </div>
  );
}
