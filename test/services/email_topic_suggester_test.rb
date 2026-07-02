require "test_helper"

# Einfacher Fake-Embedder: liefert deterministische Vektoren je Schlüsselwort.
# So kann der Classifier getestet werden, ohne Ollama zu brauchen.
class FakeEmbedder
  def initialize(mapping = {})
    @mapping = mapping
  end

  def embed(text)
    match = @mapping.find { |needle, _| text.to_s.downcase.include?(needle.to_s.downcase) }
    match ? match[1].dup : Array.new(8, 0.01)
  end

  def available?
    true
  end
end

class Classifiers::EmailTopicSuggesterTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    @patent = Topic.create!(name: "Patent Ring", slug: "patent-r-#{SecureRandom.hex(3)}",
                            creator: @hans, description: "Patentierung Ring Controller")
    @mpg    = Topic.create!(name: "MPG Solar",   slug: "mpg-s-#{SecureRandom.hex(3)}",
                            creator: @hans, description: "Solar-Anlage Betrieb")

    # Zwei wohl-getrennte Cluster im Embedding-Raum:
    # Patent-Mails sollen dem Patent-Topic ähnlich sein,
    # Solar-Mails dem MPG-Topic.
    @embedder = FakeEmbedder.new(
      "Patent Ring"   => [1, 0, 0, 0, 0, 0, 0, 0].map(&:to_f),
      "patent"        => [0.9, 0.1, 0, 0, 0, 0, 0, 0].map(&:to_f),
      "MPG Solar"     => [0, 1, 0, 0, 0, 0, 0, 0].map(&:to_f),
      "solar"         => [0.1, 0.9, 0, 0, 0, 0, 0, 0].map(&:to_f),
      "irrelevant"    => [0, 0, 1, 0, 0, 0, 0, 0].map(&:to_f)
    )
  end

  def build_email(subject:, body: "")
    Email.create!(subject: subject, body: body, sent_at: Time.current, direction: :inbound,
                  external_id: "xid-#{SecureRandom.hex(4)}")
  end

  test "auto-assigns when top score exceeds threshold with margin" do
    mail = build_email(subject: "patent application")
    suggester = Classifiers::EmailTopicSuggester.new(embedder: @embedder, topics: [@patent, @mpg])
    result = suggester.apply(mail)

    assert_equal :auto_assign, result[:decision]
    assert_equal @patent, result[:top][:topic]
    assert_includes mail.reload.topics, @patent
    assert_not_nil mail.suggested_topic_decided_at
  end

  test "suggests (no auto-apply) for mid-confidence hit" do
    # Vektor mit Patent-Ähnlichkeit ~0.60 (zwischen Suggest- und Auto-
    # Schwellwert), MPG deutlich darunter.
    mixed = FakeEmbedder.new(
      "Patent Ring" => [1, 0, 0, 0, 0, 0, 0, 0].map(&:to_f),
      "MPG Solar"   => [0, 1, 0, 0, 0, 0, 0, 0].map(&:to_f),
      "fall"        => [0.55, 0.1, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3].map(&:to_f)
    )
    mail = build_email(subject: "fall")
    suggester = Classifiers::EmailTopicSuggester.new(embedder: mixed, topics: [@patent, @mpg])
    result = suggester.apply(mail)

    assert_equal :suggest, result[:decision]
    assert_equal @patent.id, mail.reload.suggested_topic_id
    assert_nil mail.suggested_topic_decided_at
    assert_empty mail.topics
  end

  test "skip when score below threshold" do
    mail = build_email(subject: "irrelevant stuff")
    suggester = Classifiers::EmailTopicSuggester.new(embedder: @embedder, topics: [@patent, @mpg])
    result = suggester.apply(mail)

    assert_equal :skip, result[:decision]
    assert_empty mail.topics
    assert_nil mail.reload.suggested_topic_id
  end

  test "gracefully handles unavailable embedder" do
    dead = Class.new { def embed(_t); nil; end; def available?; false; end }.new
    mail = build_email(subject: "whatever")
    suggester = Classifiers::EmailTopicSuggester.new(embedder: dead, topics: [@patent])
    result = suggester.apply(mail)

    assert_equal :skip, result[:decision]
    assert_nil mail.reload.suggested_topic_id
  end
end
