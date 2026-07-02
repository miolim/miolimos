import { Controller } from "@hotwired/stimulus"

// Scannt den .markdown-body nach `<h2>Session YYYY-MM-DD</h2>` und baut
// eine kleine TOC oben in der Card — wenn es ≥ 2 Sessions gibt. Andy
// Matuschak-Stil: Body bleibt einzige Wahrheit, Frontmatter pflegt
// keine Sessions-Liste mit.
//
// Markup:
//   <div data-controller="sessions-toc" data-sessions-toc-target="container">
//     <article class="markdown-body">
//       …Body mit ## Session YYYY-MM-DD-Headings…
//     </article>
//   </div>
export default class extends Controller {
  static targets = ["container"]

  connect() {
    const article = this.element.querySelector(".markdown-body")
    if (!article) return

    const headings = Array.from(article.querySelectorAll("h2"))
      .filter(h => /^Session\s+\d{4}-\d{2}-\d{2}/.test(h.textContent.trim()))
    if (headings.length < 2) return

    headings.forEach(h => {
      const m = h.textContent.trim().match(/^Session\s+(\d{4}-\d{2}-\d{2})/)
      if (m && !h.id) h.id = `session-${m[1]}`
    })

    const links = headings.map(h => {
      const m = h.textContent.trim().match(/^Session\s+(\d{4}-\d{2}-\d{2})/)
      const date = m[1]
      return `<a href="#${h.id}" class="text-xs text-emerald-700 hover:underline">${date}</a>`
    }).join(" · ")

    const toc = document.createElement("div")
    toc.className = "text-xs text-slate-500 border border-slate-200 rounded px-3 py-2 mb-3 bg-slate-50"
    toc.innerHTML = `<span class="font-medium mr-2">Sessions:</span>${links}`

    article.parentElement.insertBefore(toc, article)
  }
}
