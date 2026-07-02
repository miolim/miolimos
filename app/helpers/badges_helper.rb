# #203 Phase E.6: Status- und Prioritaets-Pills/Badges/Dots.
module BadgesHelper
  # Inbox-Status als kleines, farbiges Pill — einheitlich in Detail-
  # Header und Listen-Zeilen.
  INBOX_STATUS_PILL = {
    "pending"               => { label: "Eingang",     cls: "bg-slate-100 text-slate-700" },
    "processing"            => { label: "Läuft",       cls: "bg-blue-100 text-blue-800" },
    "awaiting_confirmation" => { label: "Bestätigen",  cls: "bg-amber-100 text-amber-800" },
    "processed"             => { label: "Verarbeitet", cls: "bg-emerald-100 text-emerald-800" },
    "failed"                => { label: "Fehler",      cls: "bg-rose-100 text-rose-800" },
    "archived"              => { label: "Archiv",      cls: "bg-slate-100 text-slate-500" }
  }.freeze

  def status_pill(status)
    meta = INBOX_STATUS_PILL[status.to_s] || { label: status, cls: "bg-slate-100 text-slate-600" }
    content_tag(:span, meta[:label],
                class: "shrink-0 text-[11px] px-2 py-0.5 rounded-full #{meta[:cls]}")
  end

  def status_badge(value, labels:)
    tone = case value.to_s
           when "done", "completed", "archived" then "bg-emerald-100 text-emerald-800"
           when "paused"                         then "bg-amber-100 text-amber-800"
           else                                       "bg-slate-100 text-slate-700"
           end
    content_tag :span, labels[value.to_s] || value.to_s, class: "inline-block px-2 py-0.5 rounded text-xs #{tone}"
  end

  def priority_badge(value, labels:)
    tone = case value.to_s
           when "urgent" then "bg-rose-100 text-rose-800"
           when "high"   then "bg-orange-100 text-orange-800"
           when "normal" then "bg-slate-100 text-slate-700"
           when "low"    then "bg-slate-50 text-slate-500"
           else "bg-slate-100 text-slate-700"
           end
    content_tag :span, labels[value.to_s] || value.to_s, class: "inline-block px-2 py-0.5 rounded text-xs #{tone}"
  end

  # Kompakte Mobile-Variante des Prio-Badges: nur ein farbiger Punkt.
  def priority_dot(value)
    color = case value.to_s
            when "urgent" then "bg-rose-500"
            when "high"   then "bg-orange-500"
            when "low"    then "bg-slate-300"
            else               "bg-slate-400"   # normal + default
            end
    content_tag :span, "", class: "inline-block w-2.5 h-2.5 rounded-full #{color}",
                title: t("tasks.priority.#{value}", default: value.to_s)
  end
end
