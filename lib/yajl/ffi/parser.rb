module Yajl
  module FFI
    # Raised on any invalid JSON text.
    ParserError = Class.new(RuntimeError)

    # A streaming JSON parser that generates SAX-like events for state changes.
    #
    # Examples
    #
    #   parser = Yajl::FFI::Parser.new
    #   parser.key {|key| puts key }
    #   parser.value {|value| puts value }
    #   parser << '{"answer":'
    #   parser << ' 42}'
    class Parser
      BUF_SIZE = 4096
      CONTINUE_PARSE = 1
      FLOAT = /[\.eE]/

      # Parses a full JSON document from a String or an IO stream and returns
      # the parsed object graph. For parsing small JSON documents with small
      # memory requirements, use the json gem's faster JSON.parse method instead.
      #
      # json - The String or IO containing JSON data.
      #
      # Examples
      #
      #   Yajl::FFI::Parser.parse('{"hello": "world"}')
      #   # => {"hello": "world"}
      #
      # Raises a Yajl::FFI::ParserError if the JSON data is malformed.
      #
      # Returns a Hash.
      def self.parse(json)
        stream = json.is_a?(String) ? StringIO.new(json) : json
        parser = Parser.new
        builder = Builder.new(parser)
        while (buffer = stream.read(BUF_SIZE)) != nil
          parser << buffer
        end
        parser.finish
        builder.result
      ensure
        stream.close
      end

      # Create a new parser with an optional initialization block where
      # we can register event callbacks.
      #
      # Examples
      #
      #   parser = Yajl::FFI::Parser.new do
      #     start_document { puts "start document" }
      #     end_document   { puts "end document" }
      #     start_object   { puts "start object" }
      #     end_object     { puts "end object" }
      #     start_array    { puts "start array" }
      #     end_array      { puts "end array" }
      #     key            {|k| puts "key: #{k}" }
      #     value          {|v| puts "value: #{v}" }
      #   end
      def initialize(&block)
        @listeners = {
          start_document: [],
          end_document: [],
          start_object: [],
          end_object: [],
          start_array: [],
          end_array: [],
          key: [],
          value: []
        }

        # Track parse stack.
        @depth = 0
        @started = false

        # Allocate native memory.
        @callbacks = callbacks
        @handle = Yajl::FFI.alloc(@callbacks.to_ptr, nil, nil)
        @handle = ::FFI::AutoPointer.new(@handle, method(:release))

        # Register any observers in the block.
        instance_eval(&block) if block_given?
      end

      def start_document(&block)
        @listeners[:start_document] << block
      end

      def end_document(&block)
        @listeners[:end_document] << block
      end

      def start_object(&block)
        @listeners[:start_object] << block
      end

      def end_object(&block)
        @listeners[:end_object] << block
      end

      def start_array(&block)
        @listeners[:start_array] << block
      end

      def end_array(&block)
        @listeners[:end_array] << block
      end

      def key(&block)
        @listeners[:key] << block
      end

      def value(&block)
        @listeners[:value] << block
      end

      # Pass data into the parser to advance the state machine and
      # generate callback events. This is well suited for an EventMachine
      # receive_data loop.
      #
      # data - The String of partial JSON data to parse.
      #
      # Raises a Yajl::FFI::ParserError if the JSON data is malformed.
      #
      # Returns nothing.
      def <<(data)
        result = Yajl::FFI.parse(@handle, data, data.bytesize)
        error(data) if result == :error
        if @started && @depth == 0
          result = Yajl::FFI.complete_parse(@handle)
          error(data) if result == :error
        end
      end

      # Drain any remaining buffered characters into the parser to complete
      # the parsing of the document.
      #
      # This is only required when parsing a document containing a single
      # numeric value, integer or float. The parser has no other way to
      # detect when it should no longer expect additional characters with
      # which to complete the parse, so it must be signaled by a call to
      # this method.
      #
      # If you're parsing more typical object or array documents, there's no
      # need to call `finish` because the parse will complete when the final
      # closing `]` or `}` character is scanned.
      #
      # Raises a Yajl::FFI::ParserError if the JSON data is malformed.
      #
      # Returns nothing.
      def finish
        result = Yajl::FFI.complete_parse(@handle)
        error('') if result == :error
      end

      private

      # Raise a ParserError for the malformed JSON data sent to the parser.
      #
      # data - The malformed JSON String that the yajl parser rejected.
      #
      # Returns nothing.
      def error(data)
        pointer = Yajl::FFI.get_error(@handle, 1, data, data.bytesize)
        message = pointer.read_string
        Yajl::FFI.free_error(@handle, pointer)
        raise ParserError, message
      end

      # Invoke all registered observer procs for the event type.
      #
      # type - The Symbol listener name.
      # args - The argument list to pass into the observer procs.
      #
      # Examples
      #
      #    # broadcast events for {"answer": 42}
      #    notify(:start_object)
      #    notify(:key, "answer")
      #    notify(:value, 42)
      #    notify(:end_object)
      #
      # Returns nothing.
      def notify(type, *args)
        @started = true
        @listeners[type].each do |block|
          block.call(*args)
        end
      end

      # Build a native Callbacks struct that broadcasts parser state change
      # events to registered observers.
      #
      # The functions registered in the struct are invoked by the native yajl
      # parser. They convert the yajl callback data into the expected Ruby
      # objects and invoke observers registered on the parser with
      # `start_object`, `key`, `value`, and so on.
      #
      # The struct instance returned from this method must be stored in an
      # instance variable. This prevents the FFI::Function objects from being
      # garbage collected while the parser is still in use. The native function
      # bindings need to be collected at the same time as the Parser instance.
      #
      # Returns a Yajl::FFI::Callbacks struct.
      def callbacks
        callbacks = Yajl::FFI::Callbacks.new

        callbacks[:on_null] = ::FFI::Function.new(:int, [:pointer]) do |ctx|
          notify(:start_document) if @depth == 0
          notify(:value, nil)
          notify(:end_document) if @depth == 0
          CONTINUE_PARSE
        end

        callbacks[:on_boolean] = ::FFI::Function.new(:int, [:pointer, :int]) do |ctx, value|
          notify(:start_document) if @depth == 0
          notify(:value, value == 1)
          notify(:end_document) if @depth == 0
          CONTINUE_PARSE
        end

        # yajl only calls on_number
        callbacks[:on_integer] = nil
        callbacks[:on_double] = nil

        callbacks[:on_number] = ::FFI::Function.new(:int, [:pointer, :string, :size_t]) do |ctx, value, length|
          notify(:start_document) if @depth == 0
          value = value.slice(0, length)
          number = (value =~ FLOAT) ? value.to_f : value.to_i
          notify(:value, number)
          notify(:end_document) if @depth == 0
          CONTINUE_PARSE
        end

        callbacks[:on_string] = ::FFI::Function.new(:int, [:pointer, :pointer, :size_t]) do |ctx, value, length|
          notify(:start_document) if @depth == 0
          notify(:value, extract(value, length))
          notify(:end_document) if @depth == 0
          CONTINUE_PARSE
        end

        callbacks[:on_start_object] = ::FFI::Function.new(:int, [:pointer]) do |ctx|
          @depth += 1
          notify(:start_document) if @depth == 1
          notify(:start_object)
          CONTINUE_PARSE
        end

        callbacks[:on_key] = ::FFI::Function.new(:int, [:pointer, :pointer, :size_t]) do |ctx, key, length|
          notify(:key, extract(key, length))
          CONTINUE_PARSE
        end

        callbacks[:on_end_object] = ::FFI::Function.new(:int, [:pointer]) do |ctx|
          @depth -= 1
          notify(:end_object)
          notify(:end_document) if @depth == 0
          CONTINUE_PARSE
        end

        callbacks[:on_start_array] = ::FFI::Function.new(:int, [:pointer]) do |ctx|
          @depth += 1
          notify(:start_document) if @depth == 1
          notify(:start_array)
          CONTINUE_PARSE
        end

        callbacks[:on_end_array] = ::FFI::Function.new(:int, [:pointer]) do |ctx|
          @depth -= 1
          notify(:end_array)
          notify(:end_document) if @depth == 0
          CONTINUE_PARSE
        end

        callbacks
      end

      # Convert the binary encoded string data passed out of the yajl parser
      # into a UTF-8 encoded string.
      #
      # pointer - The FFI::Pointer containing the ASCII-8BIT encoded String.
      # length  - The Fixnum number of characters to extract from `pointer`.
      #
      # Raises a ParserError if the data contains malformed UTF-8 bytes.
      #
      # Returns a String.
      def extract(pointer, length)
        string = pointer.get_bytes(0, length)
        string.force_encoding(Encoding::UTF_8)
        unless string.valid_encoding?
          raise ParserError, 'Invalid UTF-8 byte sequence'
        end
        string
      end

      # Free the memory held by a yajl parser handle previously allocated
      # with Yajl::FFI.alloc.
      #
      # It's not sufficient to just allow the handle pointer to be freed
      # normally because it contains pointers that must also be freed. The
      # native yajl API provides a `yajl_free` function for this purpose.
      #
      # This method is invoked by the FFI::AutoPointer, wrapping the yajl
      # parser handle, when it's garbage collected by Ruby.
      #
      # pointer - The FFI::Pointer that references the native yajl parser.
      #
      # Returns nothing.
      def release(pointer)
        Yajl::FFI.free(pointer)
      end
    end
  end
end
