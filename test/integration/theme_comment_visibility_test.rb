# frozen_string_literal: true

require_relative '../test_helper'

class ThemeCommentVisibilityTest < LokkaTestCase
  def setup
    super
    create(:site, theme: 'docs-komagata-org')
  end

  def test_entry_page_shows_only_approved_comments_in_ascending_order
    entry = create(:post)
    approved_last = create(:comment, entry:, body: 'Approved last')
    create(:comment, entry:, status: Comment::MODERATED, body: 'Moderated private')
    create(:spam_comment, entry:, body: 'Spam private')
    approved_first = create(:comment, entry:, body: 'Approved first')

    get "/#{entry.id}"

    assert last_response.ok?, last_response.status.to_s
    page = Nokogiri::HTML(last_response.body)
    comments = page.css('ul.comments > li.comment')

    comment_ids = comments.map {|comment| comment['id'] }
    assert_equal ["comment-#{approved_first.id}", "comment-#{approved_last.id}"], comment_ids
    assert_equal ['Approved first', 'Approved last'], comments.map {|comment| comment.at_css('.body').text }
    refute_includes last_response.body, 'Moderated private'
    refute_includes last_response.body, 'Spam private'
    assert page.at_css('form#comment_form')
  end
end
