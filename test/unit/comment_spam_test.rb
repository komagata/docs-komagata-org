# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../lib/lokka/comment_spam'

class CommentSpamTest < Minitest::Test
  def test_observed_advertisements_require_a_url_and_narrow_market_signal
    [
      { body: 'Torzon market https://sites.google.com/view/torzon' },
      { body: 'DARK WEB MARKET https://example.org/' },
      { body: 'darknet market', homepage: 'https://example.org/' },
      { body: 'Visit https://darknetaccess.com/torzon' },
      { name: 'Torzon', body: 'https://example.org/' }
    ].each {|attrs| assert Lokka::CommentSpam.spam?(**attrs), attrs.inspect }
  end

  def test_ordinary_comments_and_darknet_discussion_are_preserved
    [
      { body: 'ありがとうございます' },
      { body: 'Good article https://example.com/' },
      { body: 'darknet research https://example.org/paper' },
      { body: 'Torzon darknet market, without a link' },
      { body: 'https://notdarknetaccess.com/' },
      { body: 'https://darknetaccess.com.example.org/' },
      { body: 'https://example.org/darknetaccess.com' }
    ].each {|attrs| refute Lokka::CommentSpam.spam?(**attrs), attrs.inspect }
  end

  def test_confirmed_market_phrase_variants_require_a_url_and_word_boundaries
    [
      'darknet market', 'darknet markets', 'darknet marketplace', 'darknet marketplaces',
      'dark web market', 'dark web markets', 'dark market', 'dark markets', 'darkmarket', 'darkmarkets',
      'darknet drug links', 'darknet drug store', 'darknet drugs'
    ].each do |phrase|
      assert Lokka::CommentSpam.spam?(body: "#{phrase.upcase} https://example.org/"), phrase
      refute Lokka::CommentSpam.spam?(body: phrase), phrase
      refute Lokka::CommentSpam.spam?(body: "not#{phrase} https://example.org/"), phrase
      refute Lokka::CommentSpam.spam?(body: "#{phrase}extra https://example.org/"), phrase
    end
  end

  def test_confirmed_production_advertisements
    [
      'darknet markets onion <a href="https://darknetmarketworld.com">darknet marketplace</a>',
      'darkmarket <a href="https://darkmarketslinks.com">darkmarkets</a>',
      'darknet drug links https://darkweb-storelist.com'
    ].each {|body| assert Lokka::CommentSpam.spam?(body: body), body }
  end

  def test_exact_advertising_hosts_and_their_subdomains
    %w[
      darknetmarketworld.com darknetaccess.com darkmarketsonion.com darkweb-storelist.com
      darknet-marketslinks.com darknet-marketspro.com darknetmarketnexus.info darknetmarketnexus.org
      darknetmarketnexus.net darknetmarketnexus.us darknetmarketnexus.com nexus-darknet-market-link.com
      bestdarknetmarkets.com
      darknet-market.org marketsdarknet.com market-darknet.org darknetmarketnews.com
    ].each do |host|
      assert Lokka::CommentSpam.spam?(body: "Visit https://#{host}/"), host
      assert Lokka::CommentSpam.spam?(homepage: "http://links.#{host.upcase}/"), host
      refute Lokka::CommentSpam.spam?(body: host), host
      refute Lokka::CommentSpam.spam?(body: "https://not#{host}/"), host
      refute Lokka::CommentSpam.spam?(body: "https://#{host}.example.org/"), host
      refute Lokka::CommentSpam.spam?(body: "https://example.org/#{host}"), host
      refute Lokka::CommentSpam.spam?(body: "https://#{host}@example.org/"), host
    end
  end

  def test_additional_confirmed_advertising_hosts_and_reject_lookalikes
    %w[darknet-market.org marketsdarknet.com market-darknet.org darknetmarketnews.com].each do |host|
      assert Lokka::CommentSpam.spam?(body: "Visit https://#{host}/"), host
      refute Lokka::CommentSpam.spam?(body: "https://not#{host}/"), host
      refute Lokka::CommentSpam.spam?(body: "https://#{host}.example.org/"), host
      refute Lokka::CommentSpam.spam?(body: "https://example.org/#{host}"), host
      refute Lokka::CommentSpam.spam?(body: "#{host} https://example.org/"), host
    end

    [
      'dark web link <a href="https://darknet-market.org">tor drug market</a>',
      'bitcoin dark web <a href="https://marketsdarknet.com">dark web marketplaces</a>',
      'onion dark website <a href="https://market-darknet.org">dark web marketplaces</a>',
      'darknet sites <a href="https://darknetmarketnews.com">dark websites</a>'
    ].each {|body| assert Lokka::CommentSpam.spam?(body: body), body }

    refute Lokka::CommentSpam.spam?(body: 'Useful link https://example.org/article')
    refute Lokka::CommentSpam.spam?(body: '参考リンク https://example.jp/article')
  end
end
