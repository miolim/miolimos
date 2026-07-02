# Request-scoped Actor, damit Model-Callbacks (z.B. AuditLog-Schreibung in
# Task) wissen, wer gerade handelt — ohne den Actor durch jede Methode zu
# reichen.
class Current < ActiveSupport::CurrentAttributes
  attribute :actor
end
