# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/integration_helper'

class TurnstileTest < LokkaTestCase
  include InSiteContext

  class VerificationClient
    attr_accessor :use_ssl, :open_timeout, :read_timeout, :write_timeout
    attr_reader :last_request

    def initialize(response)
      @response = response
    end

    def request(request)
      @last_request = request
      raise @response if @response.is_a?(Exception)

      @response
    end
  end

  def setup
    super
    Option.turnstile_site_key = 'test-site-key'
    Option.turnstile_secret_key = 'test-secret-key'
    Site.first.update!(theme: 'one-column-neue')
    @post = create(:post)
  end

  def test_comment_form_renders_turnstile_widget
    get "/#{@post.id}"
    assert_includes last_response.body, 'https://challenges.cloudflare.com/turnstile/v0/api.js'
    assert_includes last_response.body, 'data-sitekey="test-site-key"'
  end

  def test_missing_token_fails_before_network
    Net::HTTP.stub(:new, ->(*) { flunk 'Missing token must not contact verification service' }) do
      [nil, '', " \t"].each do |token|
        post_comment(token)
        assert_rejected
      end
    end
  end

  def test_accepts_verified_comment_and_bounds_network_timeouts
    client = verify_with('{"success":true,"hostname":"example.org"}') { post_comment('valid-token') }

    assert_equal 302, last_response.status
    assert_equal Comment::MODERATED, Comment.first.status
    assert_equal true, client.use_ssl
    assert_equal 3, client.open_timeout
    assert_equal 5, client.read_timeout
    assert_equal 5, client.write_timeout
    assert_includes client.last_request.body, 'response=valid-token'
  end

  def test_rejects_failed_malformed_and_mismatched_verification
    ['{"success":false}', 'invalid json', 'null', '[]',
     '{"success":true,"hostname":"other.example"}'].each do |body|
      verify_with(body) { post_comment('token') }
      assert_rejected
    end
  end

  def test_rejects_non_success_http_status_even_with_success_json
    verify_with('{"success":true,"hostname":"example.org"}', code: '503') { post_comment('token') }
    assert_rejected
  end

  def test_network_failures_fail_closed
    [OpenSSL::SSL::SSLError.new, Net::OpenTimeout.new, Net::ReadTimeout.new, EOFError.new].each do |error|
      verify_with(error) { post_comment('token') }
      assert_rejected
    end
  end

  def test_market_spam_is_rejected_even_with_successful_turnstile
    verify_with('{"success":true,"hostname":"example.org"}') do
      post_comment('token', body: 'Torzon darknet market https://sites.google.com/view/torzon')
    end
    assert_equal 422, last_response.status
    assert_equal 0, Comment.count
    assert_includes last_response.body, 'market advertising'
  end

  def test_deleted_user_session_still_requires_turnstile
    user = create(:user)
    post '/admin/login', name: user.name, password: 'test'
    user.destroy!
    post_comment(nil)
    assert_rejected
  end

  def test_valid_user_can_submit_without_turnstile
    user = create(:user)
    post '/admin/login', name: user.name, password: 'test'
    post_comment(nil)
    assert_equal 302, last_response.status
    assert_equal Comment::APPROVED, Comment.first.status
  end

  def test_admin_prefix_is_login_gated_for_anonymous_requests
    @post.update!(slug: 'admin/comments-advertisement')
    post '/admin/comments-advertisement', check: 'check', comment: { name: 'Reader', body: 'Good entry!' }
    assert_equal 302, last_response.status
    assert_includes last_response.location, '/admin/login'
    assert_equal 0, Comment.count
  end

  private

  def verify_with(body, code: '200', &)
    response = body.is_a?(Exception) ? body : Struct.new(:body, :code).new(body, code)
    client = VerificationClient.new(response)
    Net::HTTP.stub(:new, client, &)
    client
  end

  def assert_rejected
    assert_equal 422, last_response.status
    assert_equal 0, Comment.count
    assert_includes last_response.body, I18n.t('turnstile.verification_failed')
  end

  def post_comment(token, attributes = {})
    post "/#{@post.id}", check: 'check', 'cf-turnstile-response': token,
                         comment: { name: 'Lokka user', body: 'Good entry!' }.merge(attributes)
  end
end
