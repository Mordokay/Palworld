// Ported verbatim from the iOS app's Theme.swift — element colors, the
// damage-taken table and icon-name helpers must stay in lockstep.

export const allElements = [
  "Neutral", "Fire", "Water", "Grass", "Electric",
  "Ice", "Ground", "Dark", "Dragon",
] as const;

/** Work-suitability keys in the in-game order (match pals.json keys). */
export const allWorkKeys = [
  "kindling", "watering", "planting", "generatingElectricity",
  "handiwork", "gathering", "lumbering", "mining",
  "medicineProduction", "cooling", "transporting", "farming",
] as const;

const workRGB: Record<string, [number, number, number]> = {
  kindling: [0.94, 0.35, 0.2],
  watering: [0.23, 0.55, 0.96],
  planting: [0.3, 0.75, 0.35],
  generatingElectricity: [0.97, 0.78, 0.1],
  handiwork: [0.92, 0.56, 0.18],
  gathering: [0.16, 0.72, 0.55],
  lumbering: [0.62, 0.42, 0.26],
  mining: [0.54, 0.56, 0.62],
  medicineProduction: [0.9, 0.36, 0.62],
  cooling: [0.36, 0.78, 0.92],
  transporting: [0.58, 0.4, 0.9],
  farming: [0.62, 0.78, 0.3],
};

/** A distinct accent color per work suitability, for the filter bubbles. */
export function workColor(key: string, alpha = 1): string {
  const rgb = workRGB[key] ?? [0.56, 0.56, 0.58];
  const [r, g, b] = rgb.map((c) => Math.round(c * 255));
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

const elementRGB: Record<string, [number, number, number]> = {
  neutral: [0.66, 0.64, 0.62],
  fire: [0.94, 0.27, 0.27],
  water: [0.23, 0.51, 0.96],
  grass: [0.13, 0.77, 0.37],
  electric: [0.98, 0.8, 0.08],
  ice: [0.49, 0.83, 0.99],
  ground: [0.85, 0.47, 0.02],
  dark: [0.49, 0.23, 0.93],
  dragon: [0.39, 0.4, 0.95],
};

export function elementColor(element: string, alpha = 1): string {
  const rgb = elementRGB[element.toLowerCase()] ?? [0.56, 0.56, 0.58];
  const [r, g, b] = rgb.map((c) => Math.round(c * 255));
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

/** Bundled game icon for an element (data/images/ui/). */
export function elementIconFile(element: string): string {
  return `${capitalize(element)} icon.png`;
}

/** Bundled game icon for a work-suitability key from pals.json. */
export function workIconFile(workKey: string): string {
  return `${workLabel(workKey)} Icon.png`;
}

export function workLabel(workKey: string): string {
  return workKey
    .replace(/([A-Z])/g, " $1")
    .trim()
    .replace(/(^|\s)\S/g, (m) => m.toUpperCase());
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1).toLowerCase();
}

/**
 * Damage-taken multipliers: [defending element][attacking element] = x.
 * Absent pairs are 1x. Dual-element pals multiply their elements' values.
 */
export const damageTaken: Record<string, Record<string, number>> = {
  neutral: { dark: 1.5 },
  fire: { water: 1.5, grass: 0.5, ice: 0.5 },
  water: { electric: 1.5, fire: 0.5 },
  grass: { fire: 1.5, ground: 0.5 },
  electric: { ground: 1.5, water: 0.5 },
  ice: { fire: 1.5, dragon: 0.5 },
  ground: { grass: 1.5, electric: 0.5 },
  dark: { dragon: 1.5, neutral: 0.5 },
  dragon: { ice: 1.5, dark: 0.5 },
};

/** How much damage a pal with `elements` takes from an attack of `attacker`. */
export function damageMultiplier(elements: string[], attacker: string): number {
  return elements.reduce(
    (result, element) =>
      result * (damageTaken[element.toLowerCase()]?.[attacker.toLowerCase()] ?? 1),
    1,
  );
}

/** Stat pill colors matching the iOS Theme.Stat palette. */
export const statColors = {
  hp: "#34c759",
  attack: "#ff3b30",
  defense: "#007aff",
  work: "#30b0c7",
  food: "#a2845e",
  gold: "#ff9500",
  xp: "#af52de",
} as const;
