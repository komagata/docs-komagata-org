# frozen_string_literal: true

module Lokka
  class Database
    MODELS = %w[site option user entry category comment snippet tag tagging field_name field].freeze

    def connect
      DataMapper.finalize
      config = if Lokka.dsn.present?
                 Lokka.dsn
               else
                 Lokka.dsh
               end
      DataMapper.setup(:default, config)
      self
    end

    def load_fixture(path, model_name = nil)
      model = model_name || File.basename(path).sub('.csv', '').classify.constantize
      headers, *body = CSV.read(path)
      body.each {|row| model.create!(Hash[*headers.zip(row).reject {|i| i[1].blank? }.flatten]) }
    end

    def migrate
      MODELS.each do |model|
        model.camelize.constantize.auto_upgrade!
      end
      self
    end

    def migrate!
      MODELS.each do |model|
        model.camelize.constantize.auto_migrate!
      end
      self
    end

    def seed
      seed_file = File.join(Lokka.root, 'db', 'seeds.rb')
      load(seed_file) if File.exist?(seed_file)
    end
  end
end
