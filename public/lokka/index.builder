# frozen_string_literal: true

require 'uri'

port = request.port == 80 ? '' : ":#{request.port}"
base_url = "#{request.scheme}://#{request.host}#{port}"

first_image_url = lambda do |html|
  img = Nokogiri::HTML.fragment(html.to_s).at_css('img[src]')
  next unless img

  URI.join("#{base_url}/", img['src'].gsub('&amp;', '&')).to_s
rescue URI::InvalidURIError
  nil
end

xmlns_media = 'http://search.yahoo.com/mrss/'

xml.instruct! :xml, version: '1.0'
xml.feed(xmlns: 'http://www.w3.org/2005/Atom', 'xmlns:media': xmlns_media) do
  xml.id      "#{base_url}/"
  xml.title   @site.title
  xml.updated @posts.first.updated_at.to_s
  xml.link    type: 'text/html', rel: 'alternate', href: "#{base_url}/"
  xml.link    type: 'application/atom+xml', ref: 'self', href: "#{base_url}/index.atom"

  @posts.each do |post|
    xml.entry do
      xml.id        "tag:#{base_url.gsub('http://', '')},#{post.created_at}"
      xml.title     post.title, type: 'html'
      xml.published post.created_at.to_s
      xml.updated   post.updated_at.to_s
      xml.link      type: 'html', rel: 'alternate', href: base_url + post.link
      if (image_url = first_image_url.call(post.body))
        xml.link type: 'image', rel: 'enclosure', href: image_url
        xml.media :content, url: image_url, medium: 'image'
      end
      xml.content   post.body, type: 'html'
      xml.author do
        xml.name post.user.nil? ? '' : post.user.name
      end
    end
  end
end
