import type { Article } from "../../data/types";
import { navigate } from "../router";

/** Plain title rows — locations, guides, update history (SimpleArticleList). */
export function ArticleList({ articles }: { articles: Article[] }) {
  return (
    <div class="article-list">
      {articles.map((article) => (
        <button key={article.id} class="article-row" onClick={() => navigate(["entity", article.id])}>
          <span class="item-name">{article.title}</span>
          <span class="browse-chevron">›</span>
        </button>
      ))}
    </div>
  );
}
