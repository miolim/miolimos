require "test_helper"

# #1076: Die Testumgebung darf nicht davon abhaengen, welche Instanz gerade
# ausgerollt wird. Vorher las ExternalLinks MIOLIMOS_HOST aus der Umgebung der
# aufrufenden Shell — ein Deploy-Skript, das den Instanz-Host exportiert (oder
# ein Selbst-Hoster mit eigener Domain), bekam damit eine rote Suite, ohne dass
# an der Anwendung etwas falsch war.
class KnowledgeMarkdownExternalLinksHostTest < ActiveSupport::TestCase
  test "der eigene Host ist im Test fest verdrahtet, nicht aus der Umgebung" do
    assert_equal [ "https://os.miolim.de", "http://os.miolim.de" ],
                 KnowledgeMarkdown::ExternalLinks::OWN_HOST_PREFIXES,
                 "config/environments/test.rb muss MIOLIMOS_HOST festlegen — sonst haengt die Suite an der aufrufenden Shell"
  end

  test "ein Link auf den eigenen Host gilt nicht als extern" do
    html = KnowledgeMarkdown::ExternalLinks.annotate(%(<a href="https://os.miolim.de/tasks/1">intern</a>))
    refute_includes html, 'target="_blank"'
  end

  test "ein Link auf einen fremden Host gilt als extern" do
    html = KnowledgeMarkdown::ExternalLinks.annotate(%(<a href="https://beispiel.de/x">fremd</a>))
    assert_includes html, 'target="_blank"'
  end
end
