ENV["RAILS_ENV"] ||= "test"

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails" do
    enable_coverage :branch
    add_group "Services", "app/services"
    add_group "Concerns", "app/controllers/concerns"
    add_group "API",      "app/controllers/api"
    add_filter "/test/"
    add_filter "/config/"
    add_filter "/db/migrate/"
    # The parallel test workers each write a result; SimpleCov merges them.
    command_name "rails-test-#{ENV['TEST_ENV_NUMBER'] || 'main'}"
  end
end

require_relative "../config/environment"
require "rails/test_help"
require "fileutils"
require "tmpdir"

# ─── #1387: Tests schreiben NIEMALS in das echte Datenverzeichnis ──────────
#
# `FileProxy::BASE_PATH` ist per Default `~/miolimos` — in JEDER Umgebung,
# auch im Test. Es gab zwar `with_isolated_miolimos_base`, aber das war
# freiwillig: Jeder Test, der eine KI über FileProxy anlegte, ohne sich darin
# einzupacken, schrieb eine echte Markdown-Datei in den Wissensbestand — und
# committete sie, weil FileProxy das Repo mitführt.
#
# Was daraus wurde: ein voller Suite-Lauf hinterließ rund 500 Dateien in
# `~/miolimos/knowledge/`. Aufgefallen ist es erst, als am 10.07.2026 ein
# Reindex den angesammelten Bestand einlas — 14.220 Wissenselemente in acht
# Minuten, davon 14.120 Dubletten mit Titeln wie „Notiz" oder „Tag-Test".
#
# Deshalb ist die Sandbox jetzt der DEFAULT und nicht die Ausnahme: Der Pfad
# wird einmal beim Laden umgebogen, bevor der erste Test läuft. Wer echte
# Isolation je Test braucht, nimmt weiterhin `with_isolated_miolimos_base`.
module MiolimosTestSandbox
  ROOT = Pathname.new(Dir.mktmpdir("miolimos-test-root-"))

  def self.install!(dir = ROOT)
    dir.mkpath
    unless dir.join(".git").exist?
      Dir.chdir(dir) do
        system("git", "init", "-q", "-b", "main")
        system("git", "-c", "user.name=test", "-c", "user.email=test@test.local",
               "commit", "--allow-empty", "-q", "-m", "root")
      end
    end
    FileProxy.send(:remove_const, :BASE_PATH) if FileProxy.const_defined?(:BASE_PATH)
    FileProxy.const_set(:BASE_PATH, dir)
  end
end

MiolimosTestSandbox.install!
at_exit { FileUtils.remove_entry(MiolimosTestSandbox::ROOT, true) }

# Sicherung gegen ein stilles Zurückfallen: Zeigt der Pfad nicht in die
# Sandbox, brechen wir ab, statt in den Wissensbestand zu schreiben.
unless FileProxy::BASE_PATH.to_s.include?("miolimos-test-root-")
  abort "FileProxy::BASE_PATH zeigt auf #{FileProxy::BASE_PATH} statt in die Test-Sandbox — Abbruch."
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors) unless ENV["DISABLE_PARALLEL_TESTS"]

    # #1387: je Worker eine eigene Sandbox. Die Worker forken aus dem Parent,
    # teilten sich sonst EIN Verzeichnis samt Git-Repo — und gleichzeitige
    # Commits aus mehreren Prozessen in dasselbe Repo gehen schief.
    parallelize_setup do |worker|
      MiolimosTestSandbox.install!(MiolimosTestSandbox::ROOT.join("w#{worker}"))
    end

    # SimpleCov + parallelize: Worker forken aus dem Parent, in dem
    # SimpleCov.start schon gelaufen ist. Ohne diesen Hook schreibt nur
    # der Parent-Prozess seine Coverage — der zeigt 0.8 % an, weil er
    # selber kaum Code ausführt. `at_fork` re-initialisiert SimpleCov
    # je Worker, `command_name` macht die Resultsets eindeutig, dann
    # mergt SimpleCov beim Reporten alle.
    if ENV["COVERAGE"]
      parallelize_setup do |worker|
        SimpleCov.command_name "rails-test-#{worker}"
        SimpleCov.at_fork.call(Process.pid)
      end
      parallelize_teardown do |_worker|
        SimpleCov.result
      end
    end

    # We do NOT use Rails fixtures — Phase 1/2 tests build their own data inline
    # to keep state explicit per test.
    self.use_transactional_tests = true

    # #1055: Der Login-Rate-Limit-Store (SessionsController) ist ein
    # Prozess-MemoryStore — ohne Clearing zählen die login-POSTs ALLER
    # Tests eines Workers zusammen und ab dem elften wird jeder
    # Test-Login gebremst (549 rote Tests beim ersten Versuch).
    setup { SessionsController::RATE_LIMIT_STORE.clear }

    # ─── Factories ───────────────────────────────────────────────────────────
    # Lightweight, explicit builders — no gem dependency.

    # #602 S1: Default-Rolle admin — entspricht dem Bestand vor Multi-User
    # (jeder eingeloggte Nutzer sah alles); Member-Verhalten testen die
    # Isolations-Tests mit explizitem role: :member.
    def create_human(email: "hans-#{SecureRandom.hex(4)}@test.local", name: "Hans", role: :admin, password: nil)
      HumanActor.create!(name: name, email: email, active: true, role: role, password: password)
    end

    def create_agent(name: "Agent-#{SecureRandom.hex(4)}", description: "test agent")
      AgentActor.create!(name: name, description: description, active: true)
    end

    def create_team(name: "Team-#{SecureRandom.hex(4)}")
      Team.create!(name: name)
    end

    def create_topic(creator:, name: "Topic-#{SecureRandom.hex(4)}", slug: nil, template: false, team: nil)
      slug ||= name.parameterize
      Topic.create!(name: name, slug: slug, creator: creator, template: template, team: team, status: :active)
    end

    def create_task(creator:, title: "Task-#{SecureRandom.hex(4)}", **attrs)
      Task.create!(title: title, creator: creator, **attrs)
    end

    def grant(actor_or_team, resource_type, actions, effect: :allow)
      scope_attr = actor_or_team.is_a?(Actor) ? { actor: actor_or_team } : { team: actor_or_team }
      cap = Capability.where(scope_attr.merge(resource_type: resource_type, effect: effect)).first_or_initialize
      cap.actions = Array(actions).map(&:to_s)
      cap.save!
      cap
    end

    # ─── Llm::ChatClient stub ────────────────────────────────────────────────
    # Minitest hat `Object#stub` rausgenommen — und wir patchen ChatClient.complete
    # in 6+ Tests. Hier zentralisiert. `response` ist entweder
    #   - ein Wert (String/`""`/`nil`/Exception-Klasse): wird bei jedem Call zurueck
    #     gegeben (Exception-Klassen werden geraist),
    #   - oder ein Callable, dem die kwargs durchgereicht werden.
    #
    #   stub_chat_client("OK") { ... }
    #   stub_chat_client(->(prompt:, **) { prompt.upcase }) { ... }
    #   stub_chat_client(->(**) { raise Llm::ChatClient::UnavailableError, "x" }) { ... }
    def stub_chat_client(response, &block)
      responder = response.respond_to?(:call) ? response : ->(**_) { response }
      original  = Llm::ChatClient.method(:complete)
      Llm::ChatClient.define_singleton_method(:complete) { |**kw| responder.call(**kw) }
      yield
    ensure
      Llm::ChatClient.singleton_class.send(:remove_method, :complete) rescue nil
      Llm::ChatClient.define_singleton_method(:complete, original) if original
    end

    # ─── Isolated FileProxy base path ────────────────────────────────────────
    # Each test that touches the filesystem gets its own ~/miolimos sandbox.

    def with_isolated_miolimos_base(&block)
      Dir.mktmpdir("miolimos-test-") do |tmp|
        previous = FileProxy.const_get(:BASE_PATH)
        FileProxy.send(:remove_const, :BASE_PATH)
        FileProxy.const_set(:BASE_PATH, Pathname.new(tmp))

        # Git-init the sandbox so commits work
        Dir.chdir(tmp) do
          system("git", "init", "-q", "-b", "main")
          system("git", "-c", "user.name=test", "-c", "user.email=test@test.local",
                 "commit", "--allow-empty", "-q", "-m", "root")
        end

        begin
          yield Pathname.new(tmp)
        ensure
          FileProxy.send(:remove_const, :BASE_PATH)
          FileProxy.const_set(:BASE_PATH, previous)
        end
      end
    end
  end
end
