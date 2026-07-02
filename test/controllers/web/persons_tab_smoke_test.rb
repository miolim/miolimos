require "test_helper"
class PersonsTabSmokeTest < ActionDispatch::IntegrationTest
  test "persons tab list_card content" do
    hans = create_human(password: "secretsecret")
    %w[Topic KnowledgeItem Task Actor Communication].each { |rt| grant(hans, rt, %w[read create update delete]) }
    post "/login", params: { email: hans.email, password: "secretsecret" }
    topic = Topic.create!(name: "P-Thema", slug: "p-#{SecureRandom.hex(3)}", creator: hans)
    ki = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Max Personentest", item_type: :person,
                               file_path: "x/maxp.md", content_hash: "h", body: "")
    topic.knowledge_items << ki
    get "/topics/#{topic.slug}/list_card", params: { tab: "persons" }
    body = response.body
    puts "status: #{response.status}"
    puts "enthält Person: #{body.include?('Max Personentest')}"
    puts "first element: #{body.strip[0, 80]}"
    puts "data-uuid: #{body[/data-uuid="[^"]+"/]}"
    nav = body[/aria-label="Personen"/] ? "Personen-Tab-Link da" : "Personen-Tab-Link FEHLT"
    puts nav
    assert true
  end
end
