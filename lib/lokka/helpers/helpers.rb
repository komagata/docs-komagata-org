# frozen_string_literal: true

module Lokka
  module Helpers
    include Rack::Utils

    alias h escape_html

    %w[index search category tag yearly monthly daily post page entry entries].each do |name|
      define_method("#{name}?") do
        @theme_types.include?(name.to_sym)
      end
    end

    def base_url
      default_port = request.scheme == 'http' ? 80 : 443
      port = request.port == default_port ? '' : ":#{request.port}"
      "#{request.scheme}://#{request.host}#{port}"
    end

    # h + n2br
    def hbr(str)
      h(str).gsub(/\r\n|\r|\n/, "<br />\n").html_safe
    end

    def login_required
      return true if current_user.class != GuestUser
      session[:return_to] = request.fullpath
      redirect to('/admin/login')
      false
    end

    def current_user
      logged_in? ? User.get(session[:user]) : GuestUser.new
    end

    def logged_in?
      session[:user].present?
    end

    def bread_crumb
      bread_crumb = @bread_crumbs[0..-2].inject('<ol>') do |html, bread|
        html += %(<li><a href="#{bread[:link]}">#{bread[:name]}</a></li>)
      end
      bread_crumb += "<li>#{@bread_crumbs[-1][:name]}</li></ol>"
      bread_crumb.html_safe
    end

    def category_tree(categories = Category.roots)
      html = '<ul>'
      categories.each do |category|
        html += '<li>'
        html += "<a href=\"#{category.link}\">#{category.title}</a>"
        html += category_tree(category.children) if category.children.count > 0
        html += '</li>'
      end
      html += '</ul>'
      html.html_safe
    end

    def comment_form
      haml :"lokka/comments/form", layout: false
    end

    def months
      ms = {}
      Post.published.each do |post|
        m = post.created_at.strftime('%Y-%m')
        if ms[m].nil?
          ms[m] = 1
        else
          ms[m] += 1
        end
      end

      months = []
      ms.each do |m, count|
        year, month = m.split('-')
        months << OpenStruct.new(year: year, month: month, count: count)
      end
      months.sort {|x, y| y.year + y.month <=> x.year + x.month }
    end

    def header
      s = yield_content :header
      mark_safe(s) unless s.blank?
    end

    def footer
      s = yield_content :footer
      mark_safe(s) unless s.blank?
    end

    # example: /foo/bar?buz=aaa
    def request_path
      path = '/' + request.url.split('/')[3..-1].join('/')
      path += '/' if path != '/' && request.url =~ %r{/$}
      path
    end

    def locale
      I18n.locale
    end

    def redirect_after_edit(entry)
      name = entry.class.name.downcase.pluralize
      if entry.draft
        redirect to("/admin/#{name}?draft=true")
      else
        redirect to("/admin/#{name}/#{entry.id}/edit")
      end
    end

    def render_preview(entry)
      @entry = entry
      @entry.user = current_user
      @entry.title << ' - Preview'
      @entry.updated_at = Time.current
      @comment = @entry.comments.new
      setup_and_render_entry
    end

    def setup_and_render_entry
      @theme_types << :entry

      type = @entry.class.name.downcase.to_sym
      @theme_types << type
      instance_variable_set("@#{type}", @entry)

      @title = @entry.title

      @bread_crumbs = [{ name: t('home'), link: '/' }]
      if @entry.category
        @entry.category.ancestors.each do |cat|
          @bread_crumbs << { name: cat.title, link: cat.link }
        end
        @bread_crumbs << { name: @entry.category.title, link: @entry.category.link }
      end
      @bread_crumbs << { name: @entry.title, link: @entry.link }

      render_detect_with_options [type, :entry]
    end

    def get_admin_entries(entry_class)
      @name = entry_class.name.downcase
      @entries = params[:draft] == 'true' ? entry_class.unpublished.all : entry_class.all
      @entries = @entries.page(params[:page], per_page: settings.admin_per_page)
      haml :"admin/entries/index", layout: :"admin/layout"
    end

    def get_admin_entry_new(entry_class)
      @name = entry_class.name.downcase
      @entry = entry_class.new(markup: Site.first.default_markup, created_at: Time.current, updated_at: Time.current)
      @categories = Category.all.map {|c| [c.id, c.title] }.unshift([nil, t('not_select')])
      @field_names = FieldName.all(order: :name.asc)
      haml :"admin/entries/new", layout: :"admin/layout"
    end

    def get_admin_entry_edit(entry_class, id)
      @name = entry_class.name.downcase
      (@entry = entry_class.get(id)) || raise(Sinatra::NotFound)
      @categories = Category.all.map {|c| [c.id, c.title] }.unshift([nil, t('not_select')])
      @field_names = FieldName.all(order: :name.asc)
      haml :"admin/entries/edit", layout: :"admin/layout"
    end

    def post_admin_entry(entry_class)
      @name = entry_class.name.downcase
      @entry = entry_class.new(params[@name])
      if params['preview']
        render_preview @entry
      else
        @entry.user = current_user
        if @entry.save
          flash[:notice] = t("#{@name}_was_successfully_created")
          redirect_after_edit(@entry)
        else
          @field_names = FieldName.all(order: :name.asc)
          @categories = Category.all.map {|c| [c.id, c.title] }.unshift([nil, t('not_select')])
          haml :"admin/entries/new", layout: :"admin/layout"
        end
      end
    end

    def put_admin_entry(entry_class, id)
      @name = entry_class.name.downcase
      (@entry = entry_class.get(id)) || raise(Sinatra::NotFound)
      if params['preview']
        render_preview entry_class.new(params[@name])
      elsif @entry.update(params[@name])
        flash[:notice] = t("#{@name}_was_successfully_updated")
        redirect_after_edit(@entry)
      else
        @categories = Category.all.map {|c| [c.id, c.title] }.unshift([nil, t('not_select')])
        @field_names = FieldName.all(order: :name.asc)
        haml :"admin/entries/edit", layout: :"admin/layout"
      end
    end

    def delete_admin_entry(entry_class, id)
      name = entry_class.name.downcase
      (entry = entry_class.get(id)) || raise(Sinatra::NotFound)
      entry.destroy
      flash[:notice] = t("#{name}_was_successfully_deleted")
      if entry.draft
        redirect to("/admin/#{name.pluralize}?draft=true")
      else
        redirect to("/admin/#{name.pluralize}")
      end
    end

    ##
    # Gravatar profile image from email
    #
    # @param [String] Email address
    # @param [Integer] Image size (width and height)
    # @return [String] Image url
    #
    def gravatar_image_url(email = nil, size = nil)
      url = 'http://www.gravatar.com/avatar/'
      url += if email
               Digest::MD5.hexdigest(email)
             else
               '0' * 32
             end
      size ? "#{url}?size=#{size}" : url
    end

    class TranslateProxy
      def initialize(logger)
        @logger = logger
      end

      def method_missing(name, *)
        name = name.to_s
        @logger.warn %|"t.#{name}" translate style is obsolete. use "t("#{name}")".| # FIXME
        I18n.translate(name)
      end
    end

    def translate_compatibly(*args)
      if args.empty?
        TranslateProxy.new(logger)
      else
        I18n.translate(*args)
      end
    end
    alias t translate_compatibly

    def apply_continue_reading(posts)
      posts.each do |post|
        class << post
          alias_method :body, :short_body
        end
      end
      posts
    end

    def custom_permalink?
      RequestStore[:custom_permalink] ||= Option.permalink_enabled == 'true'
    end

    def permalink_format
      RequestStore[:permalink_format] ||= Option.permalink_format
    end

    def custom_permalink_format
      permalink_format.scan(/(%.+?%[^%]?|.)/).flatten
    end

    def custom_permalink_parse(path)
      chars = path.chars.to_a
      custom_permalink_format.each_with_object({}) do |pattern, result|
        if pattern.start_with?('%')
          next_char = pattern[-1..-1]
          next_char = nil if next_char == '%'
          name = pattern.match(/^%(.+)%.?$/)[1].to_sym
          c = nil
          until (c = chars.shift) == next_char || c.nil?
            result[name] ||= ''
            result[name] = result[name].dup << c
          end
        elsif chars.shift != pattern
          break nil
        end
      end
    end

    def custom_permalink_path(param)
      path = permalink_format.dup
      param.each do |tag, value|
        path.gsub!(/%#{Regexp.escape(tag.to_s)}%/, value)
      end
      path
    end

    def custom_permalink_fix(path)
      result = custom_permalink_parse(path)

      url_changed = false
      %i[year month monthnum day hour minute second].each do |key|
        i = (key == :year ? 4 : 2)
        if result[key] && result[key].size < i
          result[key] = result[key].rjust(i, '0')
          url_changed = true
        end
      end

      custom_permalink_path(result) if url_changed
    rescue StandardError => _e
      nil
    end

    def custom_permalink_entry(path)
      parsed = custom_permalink_parse(path)
      conditions, flags = detect_conditions_and_flags(parsed)
      if flags[:time]
        time_order = %i[year month day hour minute second]
        args, _last = time_order.inject([[], nil]) do |(result, _last), key|
          break [result, key] unless flags[key]
          [result << flags[key], nil]
        end
        args = [0, 1, 1, 0, 0, 0].each_with_index.map {|default, i| args[i] || default }
        conditions[:created_at.gte] = Time.local(*args)
        day_end = { hour: 23, minute: 59, second: 59 }
        day_end.each_pair do |key, value|
          args[time_order.index(key)] = value.to_i
        end
        conditions[:created_at.lt] = Time.local(*args)
      end
      Entry.first(conditions)
    rescue StandardError => _e
      nil
    end

    def detect_conditions_and_flags(parsed)
      parsed.inject([{}, {}]) do |(conditions, flags), (tag, value)|
        case tag
        when :year
          flags[:year] = value.to_i
        when :monthnum, :month
          flags[:month] = value.to_i
        when :day
          flags[:day] = value.to_i
        when :hour
          flags[:hour] = value.to_i
        when :minute
          flags[:minute] = value.to_i
        when :second
          flags[:second] = value.to_i
        when :post_id, :id
          conditions[:id] = value.to_i
        when :postname, :slug
          conditions[:slug] = value
        when :category
          conditions[:category_id] = Category(value).id
        end
        flags[:time] = %i[year month day hour minute second].any? {|key| flags.keys.include?(key) }
        [conditions, flags]
      end
    end

    class << self
      include Lokka::Helpers
    end

    def mobile?
      request.user_agent =~ /iPhone|Android/
    end

    def slugs
      tmp = @theme_types
      tmp << @entry.slug    if @entry && @entry.slug
      tmp << @category.slug if @category && @category.slug
      tmp
    end

    def body_attrs
      { class: slugs.join(' ') }
    end

    def handle_file_upload(params)
      if params[:file].blank?
        return {
          message: 'No file',
          status: 400
        }
      end

      credentials = Aws::Credentials.new(Option.aws_access_key_id, Option.aws_secret_access_key)
      unless credentials.set?
        return {
          status: 400,
          message: 'AWS Credentials are not set'
        }
      end

      s3 = Aws::S3::Resource.new(region: Option.s3_region, credentials: credentials)
      bucket = s3.bucket(Option.s3_bucket_name)
      domain_name = Option.s3_domain_name.presence || bucket.url

      tempfile = params[:file][:tempfile]
      digest = Digest::MD5.file(tempfile.path).to_s
      extname = File.extname(tempfile.path)
      filename = digest + extname
      content_type = MimeMagic.by_magic(tempfile).type
      if bucket.object(filename).upload_file(tempfile.path, content_type: content_type)
        {
          message: 'File upload success',
          url: "#{request.scheme}://#{domain_name}/#{filename}",
          status: 201
        }
      else
        {
          message: 'Failed uploading file',
          status: 400
        }
      end
    rescue StandardError => e
      {
        message: e.message,
        status: 500
      }
    end

    def handle_entry_preview(params)
      markup   = params[:markup]   || @site.default_markup
      raw_body = params[:raw_body] || ''
      body     = Markup.use_engine(markup, raw_body)
      {
        message: 'Preview successfull',
        body: body,
        markup: markup,
        status: 201
      }
    rescue StandardError => e
      {
        message: e.message,
        status: 500
      }
    end
  end
end
