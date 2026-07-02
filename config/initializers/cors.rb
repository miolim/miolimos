# CORS-Konfiguration nur für /api/v1/*. Wird vom Browser-Add-on
# (`chrome-extension://<id>`) und anderen externen Clients aufgerufen,
# die mit Authorization: Bearer <api_token> auth-en.
#
# Web-UI selbst läuft same-origin und braucht KEINE CORS-Erlaubnis.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "*"  # API-Auth via Bearer-Token, daher Origin-frei.
    resource "/api/*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      credentials: false,
      max_age: 3600
  end
end
