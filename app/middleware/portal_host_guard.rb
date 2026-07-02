# #536: Auf dem Portal-Host (portal.miolim.de) existiert ausschließlich das
# Portal. Als Rack-Middleware (nicht Controller-Hook), damit WIRKLICH alles
# erfasst ist — auch Controller, die nicht von ApplicationController erben
# (interner Login, API, Files). /up bleibt für den Health-Check frei.
class PortalHostGuard
  ALLOWED_PREFIXES = [ "/portal", "/up" ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    host = env["HTTP_HOST"].to_s.split(":").first
    if host == portal_host
      path = env["PATH_INFO"].to_s
      unless ALLOWED_PREFIXES.any? { |p| path == p || path.start_with?("#{p}/") }
        return [ 404, { "Content-Type" => "text/plain" }, [ "Not Found" ] ]
      end
    end
    @app.call(env)
  end

  def portal_host
    ENV.fetch("PORTAL_HOST", "portal.miolim.de")
  end
end
