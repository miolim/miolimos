Lockbox.master_key =
  ENV["LOCKBOX_MASTER_KEY"] ||
  Rails.application.credentials.dig(:lockbox, :master_key) ||
  # Development/test fallback — do NOT use in production.
  (Rails.env.local? ? "0" * 64 : nil)

if Lockbox.master_key.nil? && !Rails.env.local?
  raise "LOCKBOX_MASTER_KEY missing. Set ENV[\"LOCKBOX_MASTER_KEY\"] or credentials[:lockbox][:master_key]."
end
