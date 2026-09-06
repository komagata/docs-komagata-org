# frozen_string_literal: true

require_relative '../test_helper'

class ThemePaginationTest < LokkaTestCase
  def setup
    super
    create(:site, theme: 'docs-komagata-org', per_page: 1)
  end

  def test_middle_page_has_five_numbers_and_navigation_links
    create_list(:post, 10)

    get '/', page: 5
    pager = pagination

    assert_equal %w[<< < 3 4 5 6 7 > >>], pager.css('li').map {|li| li.text.strip }
    assert_equal '5', pager.at_css('[aria-current="page"]').text
    assert_equal %w[1 4 3 4 6 7 6 10], pager.css('a').map {|a| Rack::Utils.parse_query(a['href'].split('?').last)['page'] }
  end

  def test_first_page_disables_backward_navigation
    create_list(:post, 6)

    get '/'

    assert_equal %w[<< < 1 2 3 4 5 > >>], pagination.css('li').map {|li| li.text.strip }
    assert_equal ['<<', '<'], pagination.css('[aria-disabled="true"]').map(&:text)
  end

  def test_last_page_disables_forward_navigation
    create_list(:post, 6)

    get '/', page: 6

    assert_equal %w[<< < 2 3 4 5 6 > >>], pagination.css('li').map {|li| li.text.strip }
    assert_equal ['>', '>>'], pagination.css('[aria-disabled="true"]').map(&:text)
  end

  def test_two_pages_only_show_available_numbers
    create_list(:post, 2)

    get '/'

    assert_equal %w[<< < 1 2 > >>], pagination.css('li').map {|li| li.text.strip }
  end

  def test_single_page_and_empty_results_have_no_pager
    get '/'
    assert_nil Nokogiri::HTML(last_response.body).at_css('.pager')

    create(:post)
    get '/'
    assert_nil Nokogiri::HTML(last_response.body).at_css('.pager')
  end

  def test_search_links_preserve_the_query
    3.times {|index| create(:post, title: "Ruby & Rails #{index}") }

    get '/search/', query: 'Ruby & Rails', page: 2

    pagination.css('a').each do |link|
      query = Rack::Utils.parse_query(link['href'].split('?').last)
      assert_equal 'Ruby & Rails', query['query']
      refute_equal '2', query['page']
    end
  end

  private

  def pagination
    assert last_response.ok?, last_response.status.to_s
    pager = Nokogiri::HTML(last_response.body).at_css('nav.pager')
    refute_nil pager
    pager
  end
end
