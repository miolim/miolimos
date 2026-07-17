require "test_helper"

# #1055: GcalPush schreibt in einen ECHTEN Google-Kalender — ein Bug
# löscht oder dupliziert Remote-Termine. Hier mit gestubbtem CalendarV3-
# Service (Inhalts-Assertions, nicht nur Call-Zählung): Insert speichert
# die Remote-ID, Update trifft exakt die vorhandene ID, Delete schluckt
# notFound (Remote schon weg) und reicht andere Fehler hoch.
class GcalPushTest < ActiveSupport::TestCase
  class FakeCalendarService
    attr_reader :calls
    attr_accessor :insert_result, :delete_error

    def initialize
      @calls = []
      @insert_result = Struct.new(:id).new("gcal-neu-1")
    end

    def insert_event(calendar_id, body)
      @calls << [:insert, calendar_id, body]
      @insert_result
    end

    def update_event(calendar_id, event_id, body)
      @calls << [:update, calendar_id, event_id, body]
      body
    end

    def delete_event(calendar_id, event_id)
      @calls << [:delete, calendar_id, event_id]
      raise @delete_error if @delete_error
    end
  end

  setup do
    @actor = create_human
    @topic = Topic.create!(name: "Reiseplanung-#{SecureRandom.hex(2)}", creator: @actor)
    @event = Event.create!(title: "Kickoff", creator: @actor, topic: @topic,
                           location: "Büro", description: "Agenda folgt",
                           starts_at: Time.zone.parse("2026-08-01 10:00"))
    @fake = FakeCalendarService.new
    @push = GcalPush.new
  end

  def with_fake
    fake = @fake
    @push.define_singleton_method(:service)     { fake }
    @push.define_singleton_method(:calendar_id) { "primary" }
    yield
  end

  test "upsert ohne Remote-ID: insert mit korrektem Inhalt, Remote-ID wird gespeichert" do
    with_fake { @push.upsert(@event) }

    kind, calendar_id, body = @fake.calls.first
    assert_equal :insert, kind
    assert_equal "primary", calendar_id
    assert_equal "Kickoff", body.summary
    assert_equal "Büro", body.location
    assert_includes body.description, "Agenda folgt"
    assert_includes body.description, "Projekt: #{@topic.name}"
    assert_equal @event.starts_at.iso8601, body.start.date_time
    # ends_at nil → Default eine Stunde
    assert_equal (@event.starts_at + 1.hour).iso8601, body.end.date_time
    assert_equal "gcal-neu-1", @event.reload.gcal_event_id
  end

  test "upsert mit Remote-ID: update auf exakt diese ID, kein insert (keine Duplikate)" do
    @event.update_column(:gcal_event_id, "gcal-77")
    with_fake { @push.upsert(@event) }

    kinds = @fake.calls.map(&:first)
    assert_equal [:update], kinds
    assert_equal "gcal-77", @fake.calls.first[2]
    assert_equal "gcal-77", @event.reload.gcal_event_id, "Remote-ID darf sich beim Update nicht ändern"
  end

  test "remove löscht exakt die übergebene Remote-ID" do
    with_fake { @push.remove("gcal-42") }
    assert_equal [[:delete, "primary", "gcal-42"]], @fake.calls
  end

  test "remove schluckt notFound (Remote-Event schon weg), reicht andere Fehler hoch" do
    @fake.delete_error = Google::Apis::ClientError.new("notFound: Not Found")
    with_fake { assert_nothing_raised { @push.remove("gcal-42") } }

    @fake.delete_error = Google::Apis::ClientError.new("rateLimitExceeded")
    with_fake do
      assert_raises(Google::Apis::ClientError) { @push.remove("gcal-42") }
    end
  end

  test "ohne Calendar-Scope ist der Klassen-Einstieg ein No-Op" do
    assert_not GcalPush.enabled?, "ohne Credential darf enabled? nicht true sein"
    assert_nil GcalPush.upsert(@event)
    assert_nil GcalPush.remove("gcal-42")
  end
end
