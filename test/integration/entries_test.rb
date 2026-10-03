# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/integration_helper'

class EntriesTest < LokkaTestCase
  include InSiteContext

  def setup
    super
    @post = create(:post)
  end

  def test_anonymous_cannot_choose_status_or_protected_attributes
    other = create(:post)
    post_comment(status: '1', id: '99999', entry_id: other.id, created_at: '1999-01-01', updated_at: '1999-01-01')

    assert_equal 302, last_response.status
    comment = Comment.unscoped.order(:id).last
    assert_equal Comment::MODERATED, comment.status
    assert_equal @post.id, comment.entry_id
    refute_equal 99_999, comment.id
    refute_equal 1999, comment.created_at.year
    refute_equal 1999, comment.updated_at.year
    assert_empty other.comments
  end

  def test_existing_comment_cannot_be_modified_by_submitting_its_id
    existing = create(:comment, entry: @post)
    post_comment(id: existing.id, body: 'replacement', status: '2')

    assert_equal 302, last_response.status
    assert_equal 'Test Comment', existing.reload.body
    assert_equal Comment::APPROVED, existing.status
    assert_equal 2, Comment.count
  end

  def test_legitimate_japanese_and_english_links_are_moderated
    ['参考になりました https://example.com/', 'Useful article! https://example.org/'].each do |body|
      post_comment(body: body, email: 'reader@example.org', homepage: 'https://example.org/')
      assert_equal 302, last_response.status
      assert_equal Comment::MODERATED, Comment.unscoped.order(:id).last.status
      assert_equal body, Comment.unscoped.order(:id).last.body
      assert_equal 'reader@example.org', Comment.unscoped.order(:id).last.email
    end
  end

  def test_valid_logged_in_user_is_approved_even_if_status_is_supplied
    user = create(:user)
    post '/admin/login', name: user.name, password: 'test'
    post_comment(status: '2')

    assert_equal 302, last_response.status
    assert_equal Comment::APPROVED, Comment.unscoped.order(:id).last.status
  end

  def test_deleted_user_session_is_moderated
    user = create(:user)
    post '/admin/login', name: user.name, password: 'test'
    user.destroy!
    post_comment

    assert_equal 302, last_response.status
    assert_equal Comment::MODERATED, Comment.unscoped.order(:id).last.status
  end

  def test_market_advertising_is_rejected_without_turnstile
    post_comment(body: 'Visit Torzon darknet market https://sites.google.com/view/market')

    assert_equal 422, last_response.status
    assert_equal 0, Comment.count
    assert_includes last_response.body, 'market advertising'
  end

  def test_authenticated_api_preserves_explicit_status
    user = create(:user)
    token = user.generate_api_token!
    post '/api/v1/comments', JSON.generate(comment: { entry_id: @post.id, name: 'API reader',
                                                      body: 'Good entry!', status: Comment::SPAM }),
         'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}"

    assert_equal 201, last_response.status
    assert_equal Comment::SPAM, Comment.first.status
  end

  def test_unauthenticated_api_cannot_create_comment
    payload = JSON.generate(comment: { entry_id: @post.id, name: 'Reader',
                                       body: 'Good entry!', status: Comment::APPROVED })
    post '/api/v1/comments', payload, 'CONTENT_TYPE' => 'application/json'

    assert_equal 401, last_response.status
    assert_equal 0, Comment.count
  end

  private

  def post_comment(attributes = {})
    post "/#{@post.id}", check: 'check', comment: { name: 'Reader', body: 'Good entry!' }.merge(attributes)
  end
end
