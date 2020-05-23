require './init'
require 'rack/ssl'
use Rack::SSL
run Lokka::App
