#!/usr/bin/env ruby

# Create API user for testing docs.komagata.org API

require 'bundler/setup'
require File.join(Dir.pwd, 'init.rb')

# Create testapi user if not exists
unless User.find_by(name: 'testapi')
  user = User.create!(
    name: 'testapi',
    email: 'api@komagata.org',
    password: 'testpass123',
    password_confirmation: 'testpass123',
    permission_level: 1  # admin
  )
  token = user.generate_api_token!
  puts "User created: #{user.name}"
  puts "API token: #{token}"
else
  puts "User 'testapi' already exists"
end

# Show existing users
puts "\nExisting users:"
User.all.each do |u|
  puts "- #{u.name} (#{u.email}) #{u.api_token ? '[has_token]' : '[no_token]'}"
end