# frozen_string_literal: true

require 'uri'

module Lokka
  # Deliberately narrow: a URL plus observed market-advertising signals.
  module CommentSpam
    MARKET_TERMS = /\b(?:torzon|darknet\s+(?:market(?:place)?s?|drug\s+(?:links|store)|drugs)|
                      dark\s+web\s+markets?|dark\s*markets?)\b/ix
    URL = %r{https?://[^\s<>"']+}i
    ADVERTISING_HOSTS = %w[
      darknetmarketworld.com darknetaccess.com darkmarketsonion.com darkweb-storelist.com
      darknet-marketslinks.com darknet-marketspro.com darknetmarketnexus.info darknetmarketnexus.org
      darknetmarketnexus.net darknetmarketnexus.us darknetmarketnexus.com nexus-darknet-market-link.com
      bestdarknetmarkets.com
      darknet-market.org marketsdarknet.com market-darknet.org darknetmarketnews.com
    ].freeze

    def self.spam?(name: nil, homepage: nil, body: nil)
      text = [name, homepage, body].compact.join("\n")
      urls = text.scan(URL)
      return false if urls.empty?

      text.match?(MARKET_TERMS) || urls.any? {|url| advertising_domain?(url) }
    end

    def self.advertising_domain?(url)
      host = URI.parse(url).host.to_s.downcase
      ADVERTISING_HOSTS.any? {|domain| host == domain || host.end_with?(".#{domain}") }
    rescue URI::InvalidURIError
      false
    end
  end
end
