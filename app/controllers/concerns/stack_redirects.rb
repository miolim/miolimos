# #627 v2 / #633: Create-Flows, die im aktuellen Blade-Stack bleiben
# sollen. Das Formular gibt stay_in_stack=1 mit; der Redirect geht
# zurück auf die Referer-Stack-Seite mit dem neuen Objekt als
# angehängtem Blade (pushState hält den Stack im ?stack=-Query-Param).
# Ohne brauchbaren Referer-Stack: nil → Aufrufer nimmt seinen Standard.
module StackRedirects
  extend ActiveSupport::Concern

  private

  # token: Blade-Token des neuen Objekts, z. B. "inboxitem:42".
  def stay_in_stack_redirect_to(token)
    return nil if params[:stay_in_stack].blank?
    uri = URI.parse(request.referer.to_s) rescue nil
    return nil unless uri&.path.present? && uri.host == request.host
    stack = Rack::Utils.parse_nested_query(uri.query.to_s)["stack"].to_s
                .split(",").map(&:strip).reject(&:blank?)
    return nil if stack.empty?
    stack = (stack - [token]) + [token]
    "#{uri.path}?stack=#{ERB::Util.url_encode(stack.join(','))}"
  end
end
