import type { GameData } from "../../data/load";
import type { Article } from "../../data/types";
import { imageURL } from "../../data/images";

/**
 * Article body renderer v1: headings, prose paragraphs and image galleries.
 * M5 adds entity auto-linking, chip-list runs and wiki tables.
 */
export function ArticleSections({
  data: _data, article, hideHeadings = [],
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
        return (
          <section key={i} class="article-section">
            {section.heading &&
              (section.level === 3 ? (
                <h4 class="section-heading sub">{section.heading}</h4>
              ) : (
                <h3 class="section-heading">{section.heading}</h3>
              ))}
            {section.text &&
              section.text.split("\n").filter(Boolean).map((line, j) => (
                <p key={j} class="body-text">{line}</p>
              ))}
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
