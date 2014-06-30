require 'rake'
require 'rake/clean'
require 'rake/testtask'

CLOBBER.include('pkg')

directory 'pkg'

desc 'Build distributable packages'
task :build => [:pkg] do
  system 'gem build yajl-ffi.gemspec && mv yajl-ffi-*.gem pkg/'
end

Rake::TestTask.new(:test) do |test|
  test.libs << 'test'
  test.pattern = 'spec/**/*_spec.rb'
  test.warning = true
end

task :default => [:clobber, :test, :build]
