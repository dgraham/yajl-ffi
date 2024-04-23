# Yajl::FFI

Yajl::FFI is a [JSON](http://json.org) parser, based on
[FFI](https://github.com/ffi/ffi) bindings into the native
[YAJL](https://github.com/lloyd/yajl) library, that generates
events for each state change. This allows streaming both the JSON document into
memory and the parsed object graph out of memory to some other process.

This is similar to an XML SAX parser that generates events during parsing. There
is no requirement for the document, or the object graph, to be fully buffered in
memory. Yajl::FFI is best suited for huge JSON documents that won't fit in memory.

## Usage

The simplest way to parse is to read the full JSON document into memory
and then parse it into a full object graph. This is fine for small documents
because we have room for both the text and parsed object in memory.

```ruby
require 'yajl/ffi'
json = File.read('/tmp/test.json')
obj = Yajl::FFI::Parser.parse(json)
```

While it's possible to do this with Yajl::FFI, we should really use the
standard library's [json](https://github.com/flori/json) gem for documents
like this. It's faster because it doesn't need to generate events and notify
observers each time the parser changes state. It parses and builds the Ruby
object entirely in native code and hands it back to us, fully formed.

For larger documents, we can use an IO object to stream it into the parser.
We still need room for the parsed object, but the document itself is never
fully read into memory.

```ruby
require 'yajl/ffi'
stream = File.open('/tmp/test.json')
obj = Yajl::FFI::Parser.parse(stream)
```

However, when streaming small documents from disk, or over the network, the
[yajl-ruby](https://github.com/brianmario/yajl-ruby) gem will give us the best
performance.

Huge documents arriving over the network in small chunks to an
[EventMachine](https://github.com/eventmachine/eventmachine)
`receive_data` loop is where Yajl::FFI is uniquely suited. Inside an
`EventMachine::Connection` subclass we might have:

```ruby
def post_init
  @parser = Yajl::FFI::Parser.new
  @parser.start_document { puts "start document" }
  @parser.end_document   { puts "end document" }
  @parser.start_object   { puts "start object" }
  @parser.end_object     { puts "end object" }
  @parser.start_array    { puts "start array" }
  @parser.end_array      { puts "end array" }
  @parser.key            { |k| puts "key: #{k}" }
  @parser.value          { |v| puts "value: #{v}" }
end

def receive_data(data)
  begin
    @parser << data
  rescue Yajl::FFI::ParserError => e
    close_connection
  end
end
```

The parser accepts chunks of the JSON document and parses up to the end of the
available buffer. Passing in more data resumes the parse from the prior state.
When an interesting state change happens, the parser notifies all registered
callback procs of the event.

The event callback is where we can do interesting data filtering and passing
to other processes. The above example simply prints state changes, but the
callbacks might look for an array named `rows` and process sets of these row
objects in small batches. Millions of rows, streaming over the network, can be
processed in constant memory space this way.

## Dependencies

* [libyajl2](https://github.com/lloyd/yajl)

## Library loading

FFI uses the the `dlopen` system call to dynamically load the libyajl library
into memory at runtime. It searches the usual directories for the library file,
like `/usr/lib` and `/usr/local/lib`, and raises an error if it's not found.
If libyajl is installed in an unusual directory, we can tell `dlopen` where to
look by setting the `LD_LIBRARY_PATH` environment variable.

```sh
# test normal library load
$ ruby -r 'yajl/ffi' -e 'puts Yajl::FFI::VERSION'

# if it fails, specify the search path
$ LD_LIBRARY_PATH=/somewhere/yajl/lib \
  ruby -r 'yajl/ffi' -e 'puts Yajl::FFI::VERSION'
```

## Installation

The libyajl library needs to be installed before this gem can bind to it.

### OS X

Use [Homebrew](http://brew.sh) or compile from source below.

```
$ brew install yajl
```

### Fedora

Fedora 20 provides libyajl2 in a package. Older versions might need to compile
the latest yajl version from source.

```
$ sudo yum install yajl
```

### Ubuntu

Ubuntu 14.04 provides a libyajl2 package. Older versions might also need to
compile yajl from source.

```
$ sudo apt-get install libyajl2
```

### Source

By default, this compiles and installs to `/usr/local`. Use
`./configure -p /tmp/somewhere` to install to a different directory.
Setting `LD_LIBRARY_PATH` will be required in that case.

```
$ git clone https://github.com/lloyd/yajl
$ cd yajl
$ ./configure
$ make && make install
```

## Performance

This gem provides a benchmark script to test the relative performance of
several parsers. Here's a sample run.

```
$ bin/rake benchmark
                  user     system      total        real
json          0.037963   0.002951   0.040914 (  0.041196)
yajl-ruby     0.043128   0.001845   0.044973 (  0.045292)
yajl-ffi      0.181198   0.004324   0.185522 (  0.186301)
json-stream   2.169778   0.010984   2.180762 (  2.196817)
```

Yajl::FFI is about 4x slower than the pure native parsers. JSON::Stream is a
pure Ruby parser, and it performs accordingly. But it's useful in cases where
you're unable to use native bindings or when the limiting factor is the
network, rather than processor speed.

So if you need to parse many small JSON documents, the json and yajl-ruby gems
are the best options. If you need to stream, and incrementally parse, pieces of a
large document in constant memory space, yajl-ffi and json-stream are good
choices.

## Alternatives

* [json](https://github.com/flori/json)
* [yajl-ruby](https://github.com/brianmario/yajl-ruby)
* [json-stream](https://github.com/dgraham/json-stream)
* [application/json-seq](http://www.rfc-editor.org/rfc/rfc7464.txt)

## Development

```
$ bin/setup
$ bin/rake test
```

## License

Yajl::FFI is released under the MIT license. Check the LICENSE file for details.
