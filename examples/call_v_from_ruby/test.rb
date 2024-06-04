require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'ffi'
end

require 'ffi'

# extension for shared libraries varies by platform - see vlib/dl/dl.v
# get_shared_library_extension()
def shared_library_extension
  if Gem.win_platform?
    '.dll'
  elsif RUBY_PLATFORM =~ /darwin/ # MacOS
    '.dylib'
  else
    '.so'
  end
end

class VString < FFI::Struct
  layout :str, :pointer,
         :len, :int,
         :is_lit, :int
  def initialize(mystring)
    s = mystring.to_s
    pointer = FFI::MemoryPointer.from_string(s.to_str.encode(Encoding::UTF_8))
    self[:str] = pointer
    self[:len] = pointer.size
  end
  def to_ss()
    print "-------------------- :str ", self[:str], "\n"
    print "-------------------- :len ", self[:len], "\n"
    print "-----------------------------------------------\n"
    self[:str].read_string_length(self[:len])
  end
end

module Lib
  extend FFI::Library

  begin
    ffi_lib File.join(File.dirname(__FILE__), 'test' + shared_library_extension)
  rescue LoadError
    abort("No shared library test#{shared_library_extension} found. Check examples/call_v_from_ruby/README.md")
  end

  attach_function :square, [:int], :int
  attach_function :sqrt_of_sum_of_squares, [:double, :double], :double
  attach_function :process_v_string, [VString.val], VString.val
end

puts "Lib.square(10) result is #{Lib.square(10)}"
raise 'Cannot validate V square().' unless Lib.square(10) == 100

raise 'Cannot validate V sqrt_of_sum_of_squares().' unless \
  Lib.sqrt_of_sum_of_squares(1.1, 2.2) == Math.sqrt(1.1*1.1 + 2.2*2.2)

##pointer = FFI::MemoryPointer.from_string('hi'.to_str.encode(Encoding::UTF_8))
inp = VString.new("hi")
puts inp
puts inp.to_ss
puts "------------------------------------------------ calling --------------------------------------"
res = Lib.process_v_string(VString.new("hi"))
puts "------------------------------------------------ V function called -------------------------------------"
puts res
puts res.to_ss
puts "done"

