require "test_helper"

# #745: the app version is a single source of truth (the VERSION file) exposed
# as Miolimos::VERSION. Guard the contract the changelog/release process and
# the Settings footer rely on.
class VersionTest < ActiveSupport::TestCase
  test "Miolimos::VERSION is a SemVer string matching the VERSION file" do
    assert_match(/\A\d+\.\d+\.\d+\z/, Miolimos::VERSION)

    file = File.read(Rails.root.join("VERSION")).strip
    assert_equal file, Miolimos::VERSION
  end

  test "app_version helper returns the constant" do
    helper = Object.new.extend(ApplicationHelper)
    assert_equal Miolimos::VERSION, helper.app_version
  end
end
