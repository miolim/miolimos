# STI child of Communication — email is the first (and currently only)
# concrete communication channel. The parent Communication holds all the
# shared fields; Email exists so future channel types (chat, SMS, …) can
# be added without touching existing code.
class Email < Communication
  # Tiefer Link zur E-Mail im Gmail-Webinterface.
  # Format: https://mail.google.com/mail/?authuser=<email>#all/<thread_id>
  # Fallback auf Message-ID wenn kein Thread gespeichert ist.
  def gmail_url
    thread = raw_data&.dig("thread_id") || raw_data&.dig("threadId")
    id     = thread.presence || external_id
    return nil if id.blank?

    account = oauth_credential&.email_address
    base    = account.present? ? "https://mail.google.com/mail/?authuser=#{CGI.escape(account)}" : "https://mail.google.com/mail/u/0/"
    "#{base}#all/#{id}"
  end
end
