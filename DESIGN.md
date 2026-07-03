# Palworld Trainer — App Design

A personal iOS app to learn everything about Palworld through generated quizzes and a browsable
knowledge library. All content lives in the bundled `data/` files; every question is generated at
runtime from templates over that data (no AI, no network).

---

## 1. Navigation — TabBar

```
TabView
├── Game         gamecontroller.fill   — mode picker, Daily Challenge card, Smart Review card
├── Progression  chart.bar.fill        — knowledge completeness bars, launch targeted quizzes
├── Library      books.vertical.fill   — full wiki: browse, search, cross-linked pages
├── Achievements trophy.fill           — earned + locked achievements
└── Profile      person.crop.circle    — avatar, level/rank, stats history, settings
```

Stats live inside Profile (history, bests) and Progression (knowledge); no separate tab.

## 2. Screens

**Game tab**: Daily Challenge card up top (streak flame counter), Smart Review card when reviews
are due, then the mode grid. Every mode leads to category/length/difficulty options (defaulting
from profile) → quiz.

**Quiz screen**: question area (text and/or image), answer area (varies by format), progress /
timer / lives indicator. After answering: correct answer is always revealed, and an **info button**
opens the related Library page as a sheet. In untimed modes the sheet is offered on every
question; in timed modes missed questions collect info links on the results screen instead, so
reading never eats the clock.

**Results screen**: score, XP earned itemized (base + streak + speed + redemption bonuses), XP
routing summary ("Water +5, Celaray +2..."), per-question review with info links, "play again" /
"harder" buttons.

**Library detail page**: structured card at top (stats, elements, recipe...) rendered from typed
JSON, then the article's readable sections, then a full-width image opening a pinch-to-zoom viewer
(original quality — this is why we bundle full-res images).

**Tables**: wiki pages keep a lot of data in tables (weapon rarity tiers, element effectiveness,
spawn lists). The pipeline extracts wikitables into structured `{headers, rows}` on each article
section, and the Library renders them as native tables (bold header, row dividers, horizontal
scroll when wide).

**Cross-linking (essential)**: every piece of structured data that names another entity renders as
a tappable chip that navigates to that entity's page — a pal's element chips → the element's
article; active skills → skill pages; drops & craft materials → item pages; a skill's learnset →
pal pages; saddle tech → the saddle item. Additionally, article prose auto-links: at render time
we scan section text for known entity names (we have all 1,423 titles + name index; longest match
wins, first occurrence per section) and make them tappable. Navigation is a NavigationStack, so
the user can wiki-dive and back out.

## 3. Answer formats (the interaction primitives)

| Format | Interaction | Used for |
|---|---|---|
| Multiple choice (text) | 4 buttons | names, elements, types, facts |
| Multiple choice (image) | 2×2 image grid | "which of these is Foxparks?" |
| Type-in | text field + fuzzy match (case/diacritic-insensitive, ≤1 edit distance) | recall upgrade of MC |
| Numeric guess | number pad; scored by % error (full/partial/zero credit) | damage, prices, tiers, stats |
| True / False | 2 buttons | flipped facts, fast timed modes |
| Higher / Lower | 2 big buttons, current vs next card | stat/price comparisons, streaks |
| Match pairs | 4 left ↔ 4 right taps | pals↔elements, items↔types |
| Ordering | drag 4 cards into order | paldeck numbers, nutrition, tech tiers |

Every template targets one of these formats; difficulty can *promote* a template to a harder
format (MC → type-in, MC → numeric guess).

## 4. Question template catalog

Each template declares: data domain, answer format(s), supported difficulty range, distractor
strategy, **base XP value**, and the **facets** it exercises (see §7). Initial catalog
(~35 templates — each generates hundreds/thousands of variants):

**Pals** (`pals.json`, images)
1. Picture → name (MC / type-in) — facet: `identify`
2. Name → picture (image MC) — `identify`
3. **Who's that Pal?** — silhouette (image tinted black in SwiftUI) → name — `identify`
4. Pal → element(s); element → "which pal is X type?" — `elements`
5. Paldeck lore entry → pal — `lore`
6. Alpha title ↔ pal ("Guardian of the Dark Sun" → Anubis) — `lore`
7. Partner skill name/description ↔ pal — `partnerSkill`
8. Work suitability: which work? what level? which pal has Mining 3? — `work`
9. Drops: what does X drop / which pal drops Y? — `drops`
10. Skill learnset: at what level does X learn Y? (MC / numeric) — `skills`
11. Stat duels: which of these 4 has the highest base attack? — `stats`
12. Paldeck number: type it / order 4 pals by number — `identify`
13. Rideables: which pals are rideable, what tech level unlocks X's saddle — `utility`
14. Subspecies: match base pal ↔ variant, variant's element — `elements`
15. Food amount: order 4 pals by how much they eat — `utility`

**Items & Weapons** (`items.json`, `weapons.json`)
16. Icon → item name (MC / type-in)
17. Recipe → item ("40 Refined Ingot + 10 Polymer + 30 Carbon Fiber crafts what?")
18. Item → required material
19. Tech tier (numeric guess)
20. Gold prices (numeric guess / Higher-Lower)
21. Weapon damage / magazine size
22. Food nutrition/sanity comparisons and ordering
23. Rarity
24. Weight ordering
25. Sphere capture power comparisons

**Skills** (`skills.json`)
26. Skill ↔ element
27. Skill power / cooldown (numeric, Higher/Lower)
28. Description → skill name
29. Which pal learns X / exclusive skills
30. Skill fruit ↔ skill

**World & Mechanics** (`locations.json`, `articles.json`, hand-curated constants)
31. Element effectiveness chart (hardcoded from the Elements article — fixed game rule)
32. Tower bosses ↔ towers ↔ faction leaders
33. Which category does X belong to (Legendary? Raid boss? Alpha?)
34. True/False fact flips across all domains
35. Faction ↔ description matching

Templates are data-driven: when 1.0 adds pals/items they appear in questions after a data
refresh — no code changes.

## 5. Game modes

| Mode | Rules | Notes |
|---|---|---|
| **Quick Quiz** | 10 questions, chosen category or "Everything" | the default |
| **Time Attack** | 30s / 1m / 5m / 10m, max correct answers | wrong = −3s; leans on fast formats (MC, T/F, H/L) |
| **Survival** | endless, 3 lives, difficulty ramps every 10 correct | score = questions survived |
| **Streak (Higher/Lower)** | endless comparison chain, one mistake ends it | "more base HP: Jetragon or Anubis?" |
| **Daily Challenge** | 10 questions, date-seeded RNG (same quiz all day); one scored attempt/day | feeds daily-streak counter + streak achievements |
| **Spin the Wheel** | wheel of question categories/templates spins, lands somewhere, 5 questions on that topic, spin again | zero-decision play; wheel weights slightly favor the user's weakest categories (secretly smart) |
| **Teacher** | pick a topic → **Study phase**: curated Library pages for that topic, read at leisure → "I'm ready" → 20/40/60/80/100 questions restricted to that topic | the learn-then-test loop; results show which studied facts were missed, with links back to the pages |
| **Who's that Pal?** | silhouette-only picture round, 20 pals | fan-favorite gimmick, own mode |
| **Smart Review** | re-asks previously missed questions, spaced (due 1, 3, 7 days after miss; correct answer graduates it) | turns mistakes into internalized knowledge |
| **Placement Test** | 12 questions sweeping easy→hard across domains | sets initial difficulty; retakable from Profile |

## 6. Difficulty engine

Three player-facing levels (Easy / Medium / Hard) interpreted per template; the real lever is
**distractor similarity**:

- **Easy**: random distractors from the domain; recognition formats (MC); numeric tolerance ±30%;
  common content only.
- **Medium**: distractors share a trait with the answer (same element, same item type, nearby
  paldeck numbers); tolerance ±15%; subspecies and mid-tier content enter.
- **Hard**: maximally confusable distractors (same element *and* similar stats; sibling
  subspecies; numeric distractors within ±20% of truth); recall formats replace MC; tolerance ±5%;
  obscure content (drop rates, breed power, alpha titles).

Initial difficulty: self-report at first launch ("New / Played some / Veteran") or the Placement
Test. Overridable per-quiz; rank (§7) nudges the default.

## 7. Progression — the knowledge map

Progression is a first-class tab: a browsable map of what the user knows, with progress bars, and
**every gap is tappable → launches a quiz targeted at exactly that gap**.

**Facets.** Knowing a pal isn't one fact. Each pal tracks per-facet mastery:
`identify, elements, partnerSkill, work, drops, stats, skills, lore, utility` (items/skills/world
entities have smaller facet sets, e.g. items: `identify, recipe, economy, properties`). A facet is
mastered after N correct answers on it (N = 2/3/4 by content obscurity), with misses subtracting
one. **A pal is complete when all its facets are mastered** — you must dominate every aspect,
exactly as you described.

**Rollups.** Category completeness = mean of member entity completeness:
- Water Pals 43% ── element categories roll up pals of that element
- Materials 12%, Weapons 30% ── item-type categories
- Skills, World... every quiz category has a bar
The Progression screen shows these bars (element-colored, §10), expandable to per-entity rows
(Celaray 6/9 facets), each with a "Quiz this" button that seeds the engine with that
entity/category filter.

**XP routing.** Every question knows its subjects and category. One question about Celaray's
drops awards: +1 pal XP (Celaray), +1 facet progress (Celaray/drops), +1 element XP (Water), and
its base XP to the global level. A 30-question mix with 5 water-pal questions yields Water +5 —
your example, exactly.

**Global level.** XP requirement grows ×1.5 per level: 100, 150, 225, 338... (`100 × 1.5^(n−1)`,
rounded). Ranks by level: Beginner (1–4) → Novice (5–9) → Intermediate (10–19) → Advanced (20–34)
→ Expert (35–49) → **Pal Professor** (50+). Rank nudges default difficulty; never locks gameplay.

**XP per question** = template base value × difficulty multiplier (1 / 1.5 / 2) × format bonus
(type-in and numeric ×1.25) + streak bonus (+2 per consecutive correct, cap +10) + speed bonus in
timed modes. **Redemption bonus**: correctly answering a question you previously missed pays 2×
base XP and is celebrated in the results screen — failure literally becomes the most valuable
thing to revisit (Smart Review and the wheel's weak-category bias both feed on this).

**Avatar unlocks**: 5 correct answers about a pal "catches" it as a profile avatar choice.

**Quiz History & Replay.** Every finished session is saved and replayable, forever, because
generation is deterministic. The History screen (in Profile) lists past quizzes as rows: mode,
category, date, and a **completion ring** — a circular progress bar segmented green/red per
question showing which of that quiz's questions have *ever* been answered correctly. Replaying is
free and unlimited; **replays award XP only for questions that were previously wrong** (the
redemption bonus applies), so grinding a completed quiz yields nothing, but hunting down your last
two reds turns a 8/10 into a 100% ring. Completing a ring is a satisfying unit of progress and
feeds facet mastery like any other answer.

*Implementation note*: replay is **signature-based, not seed-based**. A session persists its seed
*and* each question's signature (templateID + subjectID); replay regenerates questions from the
signatures (the seed still drives distractor/shuffle determinism). This survives data refreshes —
a pure seed replay would silently produce different questions once 1.0 adds new pals to the pool.
Templates therefore support targeted generation: `generate(for: subjectID)` in addition to random
draw (the Progression tab's "Quiz this" needs the same capability).

## 8. Achievements (initial placeholder set)

| Achievement | Condition | Symbol |
|---|---|---|
| First Steps | finish your first quiz | figure.walk |
| On Fire | 10-question correct streak in one session | flame.fill |
| Creature of Habit | 7-day Daily Challenge streak | calendar |
| Making Amends | clear 25 Smart Review questions | arrow.uturn.up.circle.fill |
| Hydrologist | 100% Water-pal progression | drop.fill |

Engine: an `Achievement` protocol evaluated on session end + a generic "element mastery" family so
Hydrologist scales to all elements later. Locked achievements show silhouetted icons + hint text.

## 9. Profile & persistence (SwiftData, local only)

```
PlayerProfile   — name, avatarPalID, selfReportedExperience, xp, level, dailyStreak,
                  preferredDifficulty, unlockedAvatarPalIDs
QuizSession     — date, mode, category, difficulty, score, xpEarned, duration,
                  seed, dataVersion, questionSignatures (replayable history)
QuestionResult  — session ref, templateID, subjectIDs, facet, wasCorrect (latest),
                  everCorrect (completion ring), timeToAnswer
FacetProgress   — entityID, facet, correctCount, missCount, masteredAt?
CategoryXP      — categoryID → xp             (progression bars read this + FacetProgress)
BestScore       — mode+category+difficulty → best value, date
AchievementState— achievementID, unlockedAt?, progressCounter
ReviewItem      — questionSignature, missedAt, dueAt, graduated
```

## 10. Visual design system — colorful, like the game

**Element colors** (used for chips, progression bars, quiz category theming, subtle question-card
tinting when the subject's element is known):

| Element | Color (light/dark tuned) | Element | Color |
|---|---|---|---|
| Neutral | warm gray #A8A29E | Electric | yellow #FACC15 |
| Fire | red-orange #EF4444 | Ice | ice blue #7DD3FC |
| Water | blue #3B82F6 | Ground | earth brown #D97706 |
| Grass | green #22C55E | Dark | violet-black #7C3AED |
| Dragon | indigo #6366F1 | | |

**Stat colors + SF Symbols** (used everywhere a stat appears — library cards, stat duels, results):

| Stat | Color | Symbol |
|---|---|---|
| HP | green | heart.fill |
| Attack | red | flame.fill (inside a red context, reads as "power", distinct from Fire chips which pair color+label) |
| Defense | blue | shield.fill |
| Work suitability | teal | hammer.fill |
| Food | brown | fork.knife |
| Gold / economy | amber | dollarsign.circle.fill |
| XP / level | purple | star.fill |

**Haptics**: `.success`/`.error` feedback on every answered question. Timed modes tick
(`Haptics.countdownTick()`, a short light impact) once per second through the final 10 seconds.
Level-ups and achievements get `.success` plus confetti.

Other iconography: dice.fill (Spin the Wheel), graduationcap.fill (Teacher), timer (Time Attack),
heart.slash (Survival), arrow.up.arrow.down (Higher/Lower), calendar.badge.clock (Daily),
questionmark.circle.fill (Who's that Pal?), brain.head.profile (Smart Review), book.fill (info
button).

**Typography**: SF Rounded as the app-wide font design (`.fontDesign(.rounded)`) — playful without
shipping a custom font. Hierarchy is deliberate and bold: question prompts `.title2.bold()`,
answers `.body.weight(.semibold)`, big numbers (scores, timers, XP) `.largeTitle.bold()` with
`.monospacedDigit()`, category headers `.headline` in the category's color, captions/lore in
`.callout` italic. Element/stat chips: capsule background at 20% opacity of the element color with
full-color text+icon — readable in light and dark mode.

**Components**: cards with `RoundedRectangle(cornerRadius: 16)` + subtle element-tinted borders
(1pt at 30% opacity); big rounded answer buttons that flash green/red on answer; progress bars are
capsules filled with the category color; confetti on level-up and achievement unlocks.

## 11. Architecture

- `GameData` — loaded once at launch; indexed lookups (by id, element, category) for distractor pools.
- `QuestionTemplate` protocol — `id`, `domain`, `facet`, `baseXP`, `supportedFormats`,
  `generate(data:difficulty:rng:) -> Question?`
- `Question` — enum by answer format; carries prompt (text/image), payloads, `subjectIDs`,
  `articleID` (info button), `signature` (stable hash for Smart Review/redemption matching).
- `QuizEngine` — (mode, filters, difficulty, seeded RNG) → samples templates by weights,
  dedupes subjects in-session, scores, emits XP routing events.
- `ProgressionStore` — consumes routing events, updates FacetProgress/CategoryXP, computes rollups.
- `Theme` — element/stat color + symbol lookups in one place.
- Views are dumb: one SwiftUI view per answer format, one per mode chrome.

Seeded RNG everywhere → Daily Challenge reproducibility and testability.

## 12. Data refresh ("Update All")

`pipeline/refresh.sh` re-runs the whole pipeline (pages → parse → images). Run after game updates
(1.0 lands ~2026-07-10); new pals/items flow into quizzes and progression automatically (bars
recompute against the larger entity set). See `pipeline/README.md`.

## 13. Build order

1. **M1 — Foundations** ✅: bundle `data/`, Codable models, `GameData` loader, simulator-verified
2. **M2 — First playable** ✅: TabBar shell + Theme; Quick Quiz with templates 1–6, MC formats
   (2×2 image grid with labels + per-option tints), answer haptics, results screen, info sheet
3. **M3 — Library** ✅: browse + search + detail pages + cross-link chips + prose auto-linking +
   wikitable rendering + zoomable images
4. **M4 — Persistence & progression** ✅: SwiftData models, XP routing (global + element
   categories + per-pal facets, redemption 2×), Progression tab with targeted quizzes,
   levels/ranks, profile with avatar unlocks, quiz history with replay + completion rings
5. **M5 — Modes** ✅: Time Attack, Survival, Daily, Spin the Wheel, Who's that Pal?, placement test,
   Weakest Pals (targets the N lowest-completeness pals in a category; mixing ≥10 subjects keeps
   answers from being telegraphed — the reason single-pal/single-element quiz triggers were removed)
6. **M6 — Depth**: Teacher mode, Smart Review + redemption, remaining templates,
   difficulty-aware distractors everywhere, achievements, avatar unlocks, confetti & polish
