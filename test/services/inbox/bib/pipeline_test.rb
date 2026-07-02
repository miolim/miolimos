require "test_helper"

class Inbox::Bib::PipelineTest < ActiveSupport::TestCase
  def with_strategies(arr)
    orig = Inbox::Bib::Pipeline.method(:strategies)
    Inbox::Bib::Pipeline.define_singleton_method(:strategies) { arr }
    yield
  ensure
    Inbox::Bib::Pipeline.define_singleton_method(:strategies, orig)
  end

  test "erste erfolgreiche Strategie wird zurückgegeben, provenance gesetzt" do
    s1 = Class.new { def self.call(**_); nil; end }
    s2 = Class.new { def self.call(**_); { title: "T", csl_type: "book" }; end }
    s3 = Class.new { def self.call(**_); raise "must not be called"; end }

    with_strategies([s1, s2, s3]) do
      out = Inbox::Bib::Pipeline.call(item: nil, path: "/x", text: "y")
      assert_equal "T",    out[:title]
      assert_equal "book", out[:csl_type]
      assert out.key?(:provenance)
    end
  end

  test "Strategien dürfen werfen — Pipeline geht zur nächsten" do
    bad  = Class.new { def self.call(**_); raise "boom"; end }
    good = Class.new { def self.call(**_); { title: "T" }; end }

    with_strategies([bad, good]) do
      out = Inbox::Bib::Pipeline.call(item: nil, path: "/x", text: "y")
      assert_equal "T", out[:title]
    end
  end

  test "alle Strategien leer → nil" do
    nothing = Class.new { def self.call(**_); nil; end }
    with_strategies([nothing, nothing]) do
      assert_nil Inbox::Bib::Pipeline.call(item: nil, path: "/x", text: "y")
    end
  end

  test "leerer Title gilt als kein Treffer" do
    blank = Class.new { def self.call(**_); { title: "  " }; end }
    real  = Class.new { def self.call(**_); { title: "Real" }; end }
    with_strategies([blank, real]) do
      out = Inbox::Bib::Pipeline.call(item: nil, path: "/x", text: "y")
      assert_equal "Real", out[:title]
    end
  end
end
