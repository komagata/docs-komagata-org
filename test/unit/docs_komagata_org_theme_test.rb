# frozen_string_literal: true

require_relative '../test_helper'

class DocsKomagataOrgThemeTest < LokkaTestCase
  def test_article_content_does_not_expand_the_mobile_viewport
    stylesheet = File.read(File.expand_path(
                             '../../public/theme/docs-komagata-org/style.css',
                             __dir__
                           ))

    assert_match(/\.article\s*\{[^}]*min-width:\s*0;/m, stylesheet)
    assert_match(/\.article \.body\s*\{[^}]*overflow-wrap:\s*anywhere;/m, stylesheet)
  end
end
