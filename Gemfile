source 'https://rubygems.org'

platform :jruby do
  gem 'jruby-openssl'
end

gemspec

gem 'concurrent-ruby', require: 'concurrent'
gem 'curb'
gem 'http_parser.rb', '~> 0.6.0'
gem 'robots', group: :robots, git: 'https://github.com/temadoomsday/robots'

group :development do
  gem 'rake'
  gem 'rubygems-tasks', '~> 0.2'

  gem 'rspec',    '~> 3.0'
  gem 'sinatra',  '~> 1.0'
  gem 'webmock',  '~> 3.0'

  gem 'kramdown'
  gem 'yard', '~> 0.9'
end
