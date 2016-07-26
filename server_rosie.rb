require 'sinatra'
require 'pry'
require 'awesome_print'
require_relative '../global_utils/global_utils'
class BakedPotato < Sinatra::Base
  set env: :development
  set port: 4545
  set :bind, '0.0.0.0'
  @box_client = Utils::Box::Client.instance
  @sf_client  = Utils::SalesForce::Client.instance
  get '/' do
    File.read('funtimes.csv')
  end

  run! if app_file == $0
end
