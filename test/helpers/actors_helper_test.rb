require "test_helper"

class ActorsHelperTest < ActionView::TestCase
  test "actor_initials liefert max zwei Großbuchstaben" do
    h = HumanActor.new(name: "Hans Müller")
    assert_equal "HM", actor_initials(h)
  end

  test "actor_initials liefert ? für leeren Namen" do
    h = HumanActor.new(name: "")
    assert_equal "?", actor_initials(h)
  end

  test "actor_avatar_classes ist deterministisch pro ID" do
    h1 = HumanActor.new
    h1.id = 0
    h2 = HumanActor.new
    h2.id = 0
    assert_equal actor_avatar_classes(h1), actor_avatar_classes(h2)
  end
end
