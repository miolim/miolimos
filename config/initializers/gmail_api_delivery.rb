# #536 P0: ActionMailer-Delivery-Method „gmail_api" — alle App-Mails laufen
# über GmailSender (Gmail-API mit Hans' OAuth-Credential) statt SMTP.
# Aktiviert in config/environments/production.rb; Test/Dev bleiben auf :test.
class GmailApiDelivery
  def initialize(_settings = {}); end

  def deliver!(mail)
    GmailSender.deliver!(mail)
  end
end

ActiveSupport.on_load(:action_mailer) do
  ActionMailer::Base.add_delivery_method(:gmail_api, GmailApiDelivery)
end
