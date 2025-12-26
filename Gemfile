source 'https://rubygems.org'

gemspec

group :development do
  gem "rack-test"
  gem "pdf-inspector"
end

group :optional do
  gem "pdfkit"
end

group :test do
  gem 'rake'
  gem 'rspec'
  gem 'pry'
  gem 'simplecov', require: false
end

group :development, :test do
  gem 'bundler-audit', require: false
end

gem 'rack-contrib'
