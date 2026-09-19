require "test_helper"
require "webrick"

# #1675: Der eine, abgesicherte Abruf fremder Web-Adressen.
class SafeHttpTest < ActiveSupport::TestCase
  def mit_server
    server = WEBrick::HTTPServer.new(Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
    server.mount_proc("/seite")  { |_q, r| r["Content-Type"] = "text/html"; r.body = "<title>Hallo</title>" }
    server.mount_proc("/kurz")   { |_q, r| r.status = 301; r["Location"] = "/seite" }   # RELATIV (#1462)
    server.mount_proc("/gross")  { |_q, r| r.body = "x" * 200_000 }
    server.mount_proc("/nach-innen") { |_q, r| r.status = 302; r["Location"] = "http://169.254.169.254/latest/meta-data/" }
    server.mount_proc("/mailto") { |_q, r| r.status = 302; r["Location"] = "mailto:jemand@example.org" }
    thread = Thread.new { server.start }
    yield "http://127.0.0.1:#{server.config[:Port]}"
  ensure
    server&.shutdown
    thread&.join(2)
  end

  test "interne Adressen werden nicht abgerufen" do
    ["http://127.0.0.1:5432/", "http://localhost/", "http://10.0.0.5/", "http://192.168.1.1/router",
     "http://169.254.169.254/latest/meta-data/", "http://[::1]/", "http://0.0.0.0/",
     "http://[::ffff:127.0.0.1]/"].each do |url|
      fehler = assert_raises(SafeHttp::Blocked, "#{url} wurde abgerufen") { SafeHttp.get(url) }
      assert_match(/interne Adresse/, fehler.message)
    end
  end

  test "oeffentliche Adressen gelten nicht als gesperrt" do
    refute SafeHttp.gesperrt?("93.184.216.34")
    refute SafeHttp.gesperrt?("2606:2800:220:1:248:1893:25c8:1946")
    assert SafeHttp.gesperrt?("172.20.0.1")
    assert SafeHttp.gesperrt?("kein-ip")
  end

  test "kein Web-Aufruf: file, ftp und Unsinn werden abgewiesen" do
    ["file:///etc/passwd", "ftp://example.org/x", "javascript:alert(1)", "nur text"].each do |url|
      assert_raises(SafeHttp::Error, url) { SafeHttp.get(url) }
    end
  end

  # Geprüft wird vor JEDER Anfrage — also auch vor jedem Weiterleitungsziel
  # (SafeHttp.anfrage ruft pruefe_ziel! je Sprung). Der Testserver leitet auf den
  # Metadaten-Dienst um; ohne geöffnete Sperre scheitert schon der erste Sprung,
  # und das Ziel selbst ist für sich gesperrt.
  test "jede Anfrage prueft ihr Ziel — auch das einer Weiterleitung" do
    mit_server do |basis|
      assert_raises(SafeHttp::Blocked) { SafeHttp.get("#{basis}/nach-innen") }
    end
    assert_raises(SafeHttp::Blocked) { SafeHttp.send(:pruefe_ziel!, "169.254.169.254") }
  end

  test "relative Weiterleitung wird aufgeloest, fremdes Schema abgewiesen" do
    mit_server do |basis|
      SafeHttp.intern_erlaubt do
        antwort = SafeHttp.get("#{basis}/kurz")
        assert_includes antwort.body, "Hallo"
        assert_equal "/seite", antwort.uri.path
        assert_match(/text\/html/, antwort.content_type)

        fehler = assert_raises(SafeHttp::Error) { SafeHttp.get("#{basis}/mailto") }
        assert_match(/mailto/, fehler.message)
      end
    end
  end

  test "die Groessengrenze bricht ab, statt alles in den Speicher zu laden" do
    mit_server do |basis|
      SafeHttp.intern_erlaubt do
        assert_raises(SafeHttp::Error) { SafeHttp.get("#{basis}/gross", max_bytes: 50_000) }
        assert_equal 200_000, SafeHttp.get("#{basis}/gross").body.bytesize
      end
    end
  end

  test "die Sperre ist nach dem Block wieder zu" do
    SafeHttp.intern_erlaubt { nil }
    assert_raises(SafeHttp::Blocked) { SafeHttp.get("http://127.0.0.1:1/") }
  end
end
