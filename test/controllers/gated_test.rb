require "test_helper"

# Dummy controller that participates in Gated (via ApplicationController)
# and lets the test set the current_actor.
class TaskbinsController < ApplicationController
  cattr_accessor :fake_actor

  def index;   head :ok end
  def show;    head :ok end
  def create;  head :created end
  def update;  head :ok end
  def destroy; head :ok end

  def current_actor
    self.class.fake_actor
  end
end

class GatedTest < ActionDispatch::IntegrationTest
  setup do
    @actor = create_human
    TaskbinsController.fake_actor = @actor

    Rails.application.routes.disable_clear_and_finalize = true
    Rails.application.routes.draw do
      resources :taskbins, only: [:index, :show, :create, :update, :destroy]
    end
  end

  teardown do
    Rails.application.reload_routes!
  end

  test "denies index (read) without capability — 403" do
    get "/taskbins"
    assert_response :forbidden
  end

  test "allows index with read capability" do
    grant(@actor, "Taskbin", %w[read])
    get "/taskbins"
    assert_response :success
  end

  test "show requires read (same as index)" do
    grant(@actor, "Taskbin", %w[read])
    get "/taskbins/42"
    assert_response :success
  end

  test "create requires create capability, not update" do
    grant(@actor, "Taskbin", %w[update])
    post "/taskbins"
    assert_response :forbidden

    grant(@actor, "Taskbin", %w[create update])
    post "/taskbins"
    assert_response :created
  end

  test "update requires update capability" do
    grant(@actor, "Taskbin", %w[read create])
    patch "/taskbins/1"
    assert_response :forbidden

    grant(@actor, "Taskbin", %w[read create update])
    patch "/taskbins/1"
    assert_response :success
  end

  test "destroy requires delete capability" do
    grant(@actor, "Taskbin", %w[read create update])
    delete "/taskbins/1"
    assert_response :forbidden

    grant(@actor, "Taskbin", %w[read create update delete])
    delete "/taskbins/1"
    assert_response :success
  end

  test "explicit deny overrides allow" do
    grant(@actor, "Taskbin", %w[read])
    grant(@actor, "Taskbin", %w[read], effect: :deny)
    get "/taskbins"
    assert_response :forbidden
  end
end
