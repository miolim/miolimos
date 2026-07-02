class PromptTemplate < ApplicationRecord
  belongs_to :creator, class_name: "Actor"

  # #705 (b) (Hans): Ausgabeformat des LLM-Outputs. html → das erzeugte KI
  # wird render_mode=html (sandboxed iframe im Blade). output_html?/output_markdown?
  enum :output_format, { markdown: "markdown", html: "html" }, prefix: :output

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :prompt_text, presence: true
end
