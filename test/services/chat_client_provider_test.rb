require "test_helper"

# #1546: Der lokale Ollama-Zweig ist aus dem Chat-Client entfernt. Ohne
# Anthropic-Schluessel gibt es keinen stillen Rueckfall mehr auf ein
# lokales Modell — der Client sagt, dass er nicht arbeiten kann.
class ChatClientProviderTest < ActiveSupport::TestCase
  # Gleiche Technik wie `stub_chat_client` im test_helper: Singleton-Methode
  # ersetzen und danach zurueckgeben (Minitest hat Object#stub entfernt).
  def without_anthropic_key
    original = Llm::ChatClient.method(:anthropic_api_key)
    Llm::ChatClient.define_singleton_method(:anthropic_api_key) { nil }
    yield
  ensure
    Llm::ChatClient.singleton_class.send(:remove_method, :anthropic_api_key) rescue nil
    Llm::ChatClient.define_singleton_method(:anthropic_api_key, original) if original
  end

  test "detect_provider liefert ohne Anthropic-Schluessel keinen Anbieter" do
    without_anthropic_key do
      assert_nil Llm::ChatClient.detect_provider
    end
  end

  test "complete verweigert ohne Schluessel, statt lokal auszuweichen" do
    without_anthropic_key do
      error = assert_raises(Llm::ChatClient::UnavailableError) do
        Llm::ChatClient.complete(prompt: "Hallo")
      end
      assert_match(/ANTHROPIC_API_KEY/, error.message)
      assert_no_match(/Ollama/i, error.message)
    end
  end

  test "ein ollama-praefigiertes Modell wird abgewiesen, nicht stillschweigend umgeleitet" do
    error = assert_raises(Llm::ChatClient::UnavailableError) do
      Llm::ChatClient.complete(prompt: "Hallo", model: "ollama:llama3.1:8b")
    end
    assert_match(/Unbekannter LLM-Anbieter/, error.message)
  end

  test "der Ollama-Client und der Embedder existieren nicht mehr" do
    assert_not Llm::ChatClient.const_defined?(:Ollama, false)
    assert_not Object.const_defined?("Classifiers::OllamaEmbedder")
  end
end
