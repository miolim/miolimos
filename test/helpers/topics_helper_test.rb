require "test_helper"

class TopicsHelperTest < ActionView::TestCase
  test "topic_dot rendert farbigen Kreis mit Custom-Color" do
    t = Topic.new(color: "#ff0000")
    html = topic_dot(t)
    assert_includes html, "background: #ff0000"
  end

  test "topic_dot fällt auf Default-Color zurück, wenn keine Color" do
    t = Topic.new(color: nil)
    html = topic_dot(t)
    assert_includes html, "background: #94a3b8"
  end

  test "topic_marker mit next_step:true rendert SVG-Dreieck" do
    t = Topic.new(color: "#abcdef")
    html = topic_marker(t, next_step: true)
    assert_includes html, "<svg"
    assert_includes html, "polygon"
    assert_includes html, "#abcdef"
  end

  test "topic_marker ohne next_step rendert Kreis-Span" do
    t = Topic.new(color: "#abcdef")
    html = topic_marker(t, next_step: false)
    assert_includes html, "rounded-full"
    refute_includes html, "<svg"
  end

  test "topic_has_next_step? findet Topics mit angepinntem next_step" do
    hans  = create_human
    grant(hans, "Task", %w[create])
    topic = create_topic(creator: hans)
    task  = Task.create!(title: "T", creator: hans)
    TaskTopic.create!(task: task, topic: topic, next_step: true)
    assert topic_has_next_step?(topic)

    other = create_topic(creator: hans)
    refute topic_has_next_step?(other)
  end
end
