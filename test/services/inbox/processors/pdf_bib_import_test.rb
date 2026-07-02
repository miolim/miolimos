require "test_helper"

class Inbox::Processors::PdfBibImportTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Source",        %w[read create update delete])
    @klass = Inbox::Processors::PdfBibImport
  end

  def stub_extract(text)
    orig = @klass.method(:extract_first_pages)
    @klass.define_singleton_method(:extract_first_pages) { |_p| text }
    yield
  ensure
    @klass.define_singleton_method(:extract_first_pages, orig)
  end

  def stub_pipeline(result)
    orig = Inbox::Bib::Pipeline.method(:call)
    Inbox::Bib::Pipeline.define_singleton_method(:call) { |**_| result }
    yield
  ensure
    Inbox::Bib::Pipeline.define_singleton_method(:call, orig)
  end

  test "applies? matcht nur pdf_upload" do
    assert @klass.applies?(InboxItem.new(source_kind: "pdf_upload"))
    refute @klass.applies?(InboxItem.new(source_kind: "upload"))
    refute @klass.applies?(InboxItem.new(source_kind: "markdown"))
  end

  test "process! legt Source + transcript-KI mit DOI-Identifier und Authoren an" do
    with_isolated_miolimos_base do
      Dir.mktmpdir do |dir|
        pdf_path = File.join(dir, "stub.pdf")
        File.write(pdf_path, "%PDF-1.4 stub")
        item = InboxItem.create!(
          creator: @hans, source_kind: "pdf_upload",
          external_path: pdf_path, title: "stub", status: "pending"
        )

        result = {
          provenance: "doi_crossref",
          csl_type: "article-journal",
          title: "Climate Change is Real",
          container_title: "Nature",
          publisher: "Springer",
          issued_date: Date.new(2024, 3, 15),
          issued_string: "2024-3-15",
          volume: "10", issue: "2", pages: "1-20",
          authors: [
            { given: "John", family: "Doe" },
            { given: "Jane", family: "Roe" }
          ],
          identifier: { scheme: "DOI", value: "10.1234/abcd.efgh" }
        }

        stub_extract("dummy text") do
          stub_pipeline(result) do
            Current.set(actor: @hans) do
              @klass.new.process!(item, actor: @hans)
            end
          end
        end

        item.reload
        created = item.result["created"].first
        assert_equal "knowledge_item", created["kind"]

        ki = KnowledgeItem.find_by(uuid: created["uuid"])
        assert_equal "transcript", ki.item_type
        src = ki.bib_source
        assert_not_nil src
        assert_equal "Climate Change is Real", src.title
        assert_equal "article-journal", src.csl_type
        assert_equal "10.1234/abcd.efgh", src.identifier_value("DOI")
        assert_equal 2, src.source_creators.count
        names = src.source_creators.includes(:knowledge_item).order(:position).map { |sc| sc.knowledge_item.title }
        assert_equal ["John Doe", "Jane Roe"], names
      end
    end
  end

  test "leere Pipeline-Antwort → Fehler" do
    Dir.mktmpdir do |dir|
      pdf_path = File.join(dir, "stub.pdf")
      File.write(pdf_path, "%PDF-1.4 stub")
      item = InboxItem.create!(
        creator: @hans, source_kind: "pdf_upload",
        external_path: pdf_path, title: "stub", status: "pending"
      )
      stub_extract("nothing useful here") do
        stub_pipeline(nil) do
          err = assert_raises(RuntimeError) { @klass.new.process!(item, actor: @hans) }
          assert_match(/Keine bibliografischen Daten/, err.message)
        end
      end
    end
  end

  test "existierende Source mit gleicher DOI wird wiederverwendet, Titel bleibt unangetastet" do
    with_isolated_miolimos_base do
      Dir.mktmpdir do |dir|
        pdf_path = File.join(dir, "stub.pdf")
        File.write(pdf_path, "%PDF-1.4 stub")
        existing = Source.create!(
          slug: "doe-2024-climate", csl_type: "article-journal",
          title: "Original Title (händisch gepflegt)", creator: @hans
        )
        existing.source_identifiers.create!(scheme: "DOI", value: "10.1234/x")

        item = InboxItem.create!(
          creator: @hans, source_kind: "pdf_upload",
          external_path: pdf_path, title: "stub", status: "pending"
        )
        result = {
          csl_type: "article-journal", title: "Pipeline-Title",
          authors: [], identifier: { scheme: "DOI", value: "10.1234/X" }
        }
        stub_extract("x") do
          stub_pipeline(result) do
            Current.set(actor: @hans) do
              @klass.new.process!(item, actor: @hans)
            end
          end
        end
        existing.reload
        # Phase C: bestehende Source wird NICHT überschrieben
        assert_equal "Original Title (händisch gepflegt)", existing.title
        assert_equal 1, Source.where(slug: existing.slug).count

        item.reload
        assert_equal true, item.result.dig("source", "reused")
        assert_equal existing.slug, item.result.dig("source", "slug")
      end
    end
  end

  test "neue Source-Anlage notiert reused=false in result" do
    with_isolated_miolimos_base do
      Dir.mktmpdir do |dir|
        pdf_path = File.join(dir, "stub.pdf")
        File.write(pdf_path, "%PDF-1.4 stub")
        item = InboxItem.create!(
          creator: @hans, source_kind: "pdf_upload",
          external_path: pdf_path, title: "stub", status: "pending"
        )
        result = {
          csl_type: "article-journal", title: "Fresh Title",
          authors: [{ family: "Smith" }],
          identifier: { scheme: "DOI", value: "10.1234/fresh" }
        }
        stub_extract("x") do
          stub_pipeline(result) do
            Current.set(actor: @hans) do
              @klass.new.process!(item, actor: @hans)
            end
          end
        end
        item.reload
        assert_equal false, item.result.dig("source", "reused")
      end
    end
  end
end
