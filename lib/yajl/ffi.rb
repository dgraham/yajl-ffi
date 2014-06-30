require 'ffi'
require 'stringio'
require 'yajl/ffi/builder'
require 'yajl/ffi/parser'
require 'yajl/ffi/version'

module Yajl
  module FFI
    extend ::FFI::Library

    ffi_lib ['yajl', 'libyajl.so.2']

    enum :status, [
      :ok,
      :client_canceled,
      :error
    ]

    enum :options, [
      :allow_comments,         0x01,
      :allow_invalid_utf8,     0x02,
      :allow_trailing_garbage, 0x04,
      :allow_multiple_values,  0x08,
      :allow_partial_values,   0x10
    ]

    class Callbacks < ::FFI::Struct
      layout \
        :on_null,         :pointer,
        :on_boolean,      :pointer,
        :on_integer,      :pointer,
        :on_double,       :pointer,
        :on_number,       :pointer,
        :on_string,       :pointer,
        :on_start_object, :pointer,
        :on_key,          :pointer,
        :on_end_object,   :pointer,
        :on_start_array,  :pointer,
        :on_end_array,    :pointer
    end

    typedef :pointer, :handle

    attach_function :alloc,              :yajl_alloc,              [:pointer, :pointer, :pointer],     :handle
    attach_function :free,               :yajl_free,               [:handle],                          :void
    attach_function :config,             :yajl_config,             [:handle, :options, :varargs],      :int
    attach_function :parse,              :yajl_parse,              [:handle, :pointer, :size_t],       :status
    attach_function :complete_parse,     :yajl_complete_parse,     [:handle],                          :status
    attach_function :get_error,          :yajl_get_error,          [:handle, :int, :pointer, :size_t], :pointer
    attach_function :free_error,         :yajl_free_error,         [:handle, :pointer],                :void
    attach_function :get_bytes_consumed, :yajl_get_bytes_consumed, [:handle],                          :size_t
    attach_function :status_to_string,   :yajl_status_to_string,   [:status],                          :string
  end
end
