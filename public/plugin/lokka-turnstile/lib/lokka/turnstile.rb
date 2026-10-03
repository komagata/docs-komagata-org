# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'

module Lokka
  module Turnstile
    VERIFY_URI = URI('https://challenges.cloudflare.com/turnstile/v0/siteverify')

    def self.registered(app)
      app.before do
        next unless turnstile_required?
        next if turnstile_valid?

        halt 422, t('turnstile.verification_failed')
      end

      app.get '/admin/plugins/turnstile' do
        login_required
        haml :'plugin/lokka-turnstile/views/index', layout: :'admin/layout'
      end

      app.put '/admin/plugins/turnstile' do
        login_required
        Option.turnstile_site_key = params[:turnstile_site_key]
        Option.turnstile_secret_key = params[:turnstile_secret_key]
        flash[:notice] = t('turnstile.updated')
        redirect to('/admin/plugins/turnstile')
      end
    end
  end

  module Helpers
    def turnstile_enabled?
      turnstile_site_key.present? && turnstile_secret_key.present?
    end

    def turnstile_required?
      params['comment'].present? &&
        !request.path.start_with?('/admin/comments') &&
        !current_user.is_a?(User) &&
        turnstile_enabled?
    end

    def turnstile_valid?
      token = params['cf-turnstile-response'].to_s
      return false if token.strip.empty?

      client = Net::HTTP.new(Turnstile::VERIFY_URI.host, Turnstile::VERIFY_URI.port)
      client.use_ssl = true
      client.open_timeout = 3
      client.read_timeout = 5
      client.write_timeout = 5
      verification = Net::HTTP::Post.new(Turnstile::VERIFY_URI)
      verification.set_form_data(secret: turnstile_secret_key, response: token, remoteip: request.ip)
      response = client.request(verification)
      return false unless response.code == '200'

      result = JSON.parse(response.body)
      result.is_a?(Hash) && result['success'] == true && result['hostname'] == request.host
    rescue JSON::ParserError, OpenSSL::SSL::SSLError, SocketError, SystemCallError, Timeout::Error, EOFError
      false
    end

    def turnstile_site_key
      ENV['TURNSTILE_SITE_KEY'].presence || Option.turnstile_site_key
    end

    def turnstile_secret_key
      ENV['TURNSTILE_SECRET_KEY'].presence || Option.turnstile_secret_key
    end
  end
end
