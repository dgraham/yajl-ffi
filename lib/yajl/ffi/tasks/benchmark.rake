desc 'Compare parser performance'
task :benchmark do
  require 'benchmark'
  require 'json'
  require 'json/stream'
  require 'yajl'
  require 'yajl/ffi'
  require 'tempfile'

  # Copy the JSON test document into a temporary file several thousand times
  # to give us a decent sized text with which to benchmark the parsers.
  #
  # Returns a File.
  def generate
    json = File.read('spec/fixtures/repository.json')
    Tempfile.new('json-bench').tap do |file|
      file.puts '['
      1500.times do
        file.puts json
        file.puts ','
      end
      file.puts json
      file.puts ']'
      file.close
    end
  end

  # Run the benchmark test against several JSON parsers.
  #
  # Returns nothing.
  def benchmark
    file = generate
    Benchmark.bmbm do |x|
      x.report('json') do
        json = File.read(file.path)
        JSON.parse(json)
      end

      x.report('yajl-ruby') do
        json = File.open(file.path)
        Yajl::Parser.new.parse(json)
      end

      x.report('yajl-ffi') do
        json = File.open(file.path)
        Yajl::FFI::Parser.parse(json)
      end

      x.report('json-stream') do
        json = File.open(file.path)
        JSON::Stream::Parser.parse(json)
      end
    end
  ensure
    file.unlink if file
  end

  # Run it.
  benchmark
end
