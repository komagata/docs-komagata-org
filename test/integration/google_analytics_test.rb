# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/integration_helper'
require_relative '../support/admin_helper'

class GoogleAnalyticsTest < LokkaTestCase
  include InSiteContext

  def setup
    super
    Site.first.update!(theme: 'one-column-neue')
    @post = create(:post)
  end

  def test_ga4_initializes_gtag_once_for_anonymous_production_requests
    Option.tracker = 'G-TEST123'

    with_rack_env('production') { get "/#{@post.id}" }

    assert_equal 200, last_response.status
    body = last_response.body
    assert_equal 1, body.scan('<script async src="https://www.googletagmanager.com/gtag/js?id=G-TEST123"></script>').size
    assert_includes body, 'window.dataLayer = window.dataLayer || [];'
    assert_includes body, 'function gtag(){dataLayer.push(arguments);}'
    assert_includes body, "gtag('js', new Date());"
    assert_equal 1, body.scan("gtag('config', 'G-TEST123');").size
    refute_includes body, "gtag('event', 'page_view'"
    refute_includes body, 'analytics.js'
    refute_includes body, "ga('send', 'pageview')"
  end

  def test_legacy_ua_retains_analytics_js_and_one_pageview
    Option.tracker = 'UA-12345-1'

    with_rack_env('production') { get "/#{@post.id}" }

    assert_equal 200, last_response.status
    assert_equal 1, last_response.body.scan('https://www.google-analytics.com/analytics.js').size
    assert_includes last_response.body, "ga('create', 'UA-12345-1', 'auto');"
    assert_equal 1, last_response.body.scan("ga('send', 'pageview');").size
    refute_includes last_response.body, 'googletagmanager.com'
  end

  def test_blank_and_malformed_trackers_emit_no_analytics_or_injected_script
    [nil, '', ' ', 'G-', 'G-test123', 'G-TEST_123', 'UA-12345', 'UA-abc-1',
     "G-TEST123\n", "UA-12345-1\n", 'prefixG-TEST123', 'G-TEST123/suffix',
     "G-TEST123');alert('injected');", 'G-TEST123"><script>alert("injected")</script>',
     'https://example.com/injected.js'].each do |tracker|
      Option.tracker = tracker

      with_rack_env('production') { get "/#{@post.id}" }

      assert_equal 200, last_response.status
      assert_no_analytics
      refute_includes last_response.body, 'injected'
    end
  end

  def test_nonproduction_requests_emit_no_analytics
    ['G-TEST123', 'UA-12345-1'].each do |tracker|
      Option.tracker = tracker
      ['test', 'development', nil].each do |environment|
        with_rack_env(environment) { get "/#{@post.id}" }

        assert_equal 200, last_response.status
        assert_no_analytics
      end
    end
  end

  def test_logged_in_production_requests_emit_no_analytics
    user = create(:user)
    post '/admin/login', name: user.name, password: 'test'
    assert_equal 302, last_response.status

    ['G-TEST123', 'UA-12345-1'].each do |tracker|
      Option.tracker = tracker
      with_rack_env('production') { get "/#{@post.id}" }

      assert_equal 200, last_response.status
      assert_no_analytics
    end
  end

  private

  def with_rack_env(environment)
    previous = ENV['RACK_ENV']
    ENV['RACK_ENV'] = environment
    yield
  ensure
    ENV['RACK_ENV'] = previous
  end

  def assert_no_analytics
    refute_includes last_response.body, 'googletagmanager.com'
    refute_includes last_response.body, 'google-analytics.com'
    refute_includes last_response.body, 'gtag('
    refute_includes last_response.body, "ga('"
  end
end

class GoogleAnalyticsSettingsTest < LokkaTestCase
  include AdminLoginContext

  def test_settings_page_renders_controls_and_escapes_option_values
    Option.tracker = 'G-TEST123'
    Option.tracker_dn = 'example.com" onfocus="alert(1)'

    get '/admin/plugins/google_analytics'

    assert last_response.ok?
    document = Nokogiri::HTML(last_response.body)
    form = document.at_css('form[method="post"]')
    refute_nil form
    assert form['action'].end_with?('/admin/plugins/google_analytics')
    assert_equal 'put', form.at_css('input[name="_method"]')['value']
    assert_equal 'G-TEST123', form.at_css('input[name="tracker"]')['value']
    assert_equal 'submit', form.at_css('input[type="submit"]')['type']
    domain = form.at_css('input[name="tracker_dn"]')
    assert_equal 'example.com" onfocus="alert(1)', domain['value']
    assert_empty document.css('script[onfocus], input[onfocus]')
  end

  def test_settings_page_saves_and_renders_ga4_id
    put '/admin/plugins/google_analytics', tracker: 'G-TEST123', tracker_dn: 'example.com'

    assert last_response.redirect?
    get '/admin/plugins/google_analytics'

    document = Nokogiri::HTML(last_response.body)
    assert_equal 'G-TEST123', document.at_css('input[name="tracker"]')['value']
  end

end
