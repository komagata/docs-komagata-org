# frozen_string_literal: true

module Lokka
  module GoogleAnalytics
    def self.registered(app)
      app.get '/admin/plugins/google_analytics' do
        content = haml(:'plugin/lokka-google_analytics/views/index', layout: false)
        render :'admin/layout', layout: false do
          content.html_safe
        end
      end

      app.put '/admin/plugins/google_analytics' do
        Option.tracker = params['tracker']
        Option.tracker_dn = params['tracker_dn']
        flash[:notice] = 'Updated.'
        redirect to('/admin/plugins/google_analytics')
      end

      app.before do
        tracker = Option.tracker
        if !tracker.blank? && tracker.match?(/\A(?:G-[A-Z0-9]+|UA-[0-9]+-[0-9]+)\z/) &&
           ENV['RACK_ENV'] == 'production' && !logged_in?
          content_for :header do
            if tracker.start_with?('G-')
              <<-SCRIPT.strip_heredoc.html_safe
                <script async src="https://www.googletagmanager.com/gtag/js?id=#{tracker}"></script>
                <script>
                  window.dataLayer = window.dataLayer || [];
                  function gtag(){dataLayer.push(arguments);}
                  gtag('js', new Date());
                  gtag('config', '#{tracker}');
                </script>
              SCRIPT
            else
              <<-SCRIPT.strip_heredoc.html_safe
                <script>
                  (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
                  (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
                  m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
                  })(window,document,'script','https://www.google-analytics.com/analytics.js','ga');

                  ga('create', '#{tracker}', 'auto');
                  ga('send', 'pageview');
                </script>
              SCRIPT
            end
          end
        end
      end
    end
  end
end
