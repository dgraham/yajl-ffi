require './lib/yajl/ffi/version'

Gem::Specification.new do |s|
  s.name        = 'yajl-ffi'
  s.version     = Yajl::FFI::VERSION
  s.summary     = %q[A streaming JSON parser that generates SAX-like events.]
  s.description = %q[Ruby FFI bindings to the native YAJL streaming JSON parser.]

  s.authors      = ['David Graham']
  s.email        = %w[david.malcom.graham@gmail.com]
  s.homepage     = 'https://github.com/dgraham/yajl-ffi'
  s.license      = 'MIT'

  s.files        = Dir['[A-Z]*', 'yajl-ffi.gemspec', '{lib}/**/*'] - ['Gemfile.lock']
  s.require_path = 'lib'

  s.add_dependency 'ffi', '~> 1.16'
  s.add_development_dependency 'bundler', '~> 2.2'
  s.add_development_dependency 'minitest', '~> 5.22'
  s.add_development_dependency 'rake', '~> 13.2'

  s.required_ruby_version = '>= 2.6.0'
end
