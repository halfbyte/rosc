require 'time'
require 'forwardable'
require 'socket'
require 'stringio'

# Test for broken pack/unpack
if [1].pack('n') == "\001\000"
  class String
    alias_method :broken_unpack, :unpack
    def unpack(spec)
      broken_unpack(spec.tr("nNvV","vVnN"))
    end
  end
  class Array
    alias_method :broken_pack, :pack
    def pack(spec)
      broken_pack(spec.tr("nNvV","vVnN"))
    end
  end
end


class StringIO
  def skip(n)
    self.seek(n, IO::SEEK_CUR)
  end
  def skip_padding 
    self.skip((4-pos)%4)
  end
end

# Of particular interest are OSC::Client, OSC::Server, OSC::Message and
# OSC::Bundle.
module OSC
  MAX_MSG_SIZE=32768
  # 64-bit big-endian fixed-point time tag
  class TimeTag
    JAN_1970 = 0x83aa7e80
    # nil:: immediately
    # Numeric:: seconds since January 1, 1900 00:00
    # Array:: int,frac parts of a TimeTag.
    # Time:: convert from Ruby's Time
    def initialize(t)
      case t
      when NIL # immediately
	@int = 0
	@frac = 1
      when Numeric
	@int, fr = t.divmod(1)
	@frac = (fr * (2**32)).to_i
      when Array
	@int,@frac = t
      when Time
	@int, fr = (t.to_f+JAN_1970).divmod(1)
	@frac = (fr * (2**32)).to_i
      else
	raise ArgumentError, 'invalid time'
      end
    end
    # Integer part
    def to_i; to_f.to_i; end
    # Ruby's Float can handle the 64 bits so we have the luxury of dealing with
    # Float directly
    def to_f; @int.to_f + @frac.to_f/(2**32); end
    # [int,frac]
    def to_a; [@int,@frac]; end
    # Human-readable, like the output of Time#to_s
    def to_s; to_time.to_s; end
    # Ruby Time object
    def to_time; Time.at(to_f-JAN_1970); end
    def self.now; TimeTag.new(Time.now); end
  end

  class Blob < String
  end

  class Message
    attr_accessor :address, :args

    # Address pattern, type tag string, and arguments. See the OSC
    # documentation for more details.
    # Arguments will be coerced into the appropriate type tags.
    def initialize(address, tags=nil, *args)
      @address = address
      @args = []
      args.each_with_index do |arg, i|
	if tags and tags[i]
	  case tags[i]
	  when ?i; @args << arg.to_i
	  when ?f; @args << arg.to_f
	  when ?s; @args << arg.to_s
	  when ?b; @args << Blob.new(arg.to_s)
	  else
	    raise ArgumentError, 'unknown type tag'
	  end
	else
	  case arg
	  when Fixnum,Float,String,TimeTag,Blob
	    @args << arg
	  end
	end
      end
    end

    def tags
      ',' + @args.collect{|x| Packet.tag(x)}.join
    end

    # Array of the arguments
    def to_a; @args; end

    extend Forwardable
    include Enumerable

    de = (Array.instance_methods - self.instance_methods)
    de -= %w(assoc flatten flatten! pack rassoc transpose)
    de += %w(include? sort)

    def_delegators(:@args, *de)

    undef_method :zip
  end

  # bundle of messages and/or bundles
  class Bundle
    attr_accessor :timetag 
    attr_accessor :args
    alias :messages :args

    # New bundle with time and messages
    def initialize(t=nil, *args)
      @timetag = 
	case t
	when TimeTag
	  t
	else
	  TimeTag.new(t)
	end
      @args = args
    end

    # The messages in this bundle
    def contents; @args; end
    alias :to_a :contents


    extend Forwardable
    include Enumerable

    de = (Array.instance_methods - self.instance_methods)
    de -= %w(assoc flatten flatten! pack rassoc transpose)
    de += %w(include? sort)

    def_delegators(:@args, *de)

    undef_method :zip
  end

  # Unit of transmission.  Really needs revamping
  module Packet
    # XXX I might fold this and its siblings back into the decode case
    # statement
    def self.decode_int32(io)
      i = io.read(4).unpack('N')[0]
      i = 2**32 - i if i > (2**31-1) # two's complement
      i
    end

    def self.decode_float32(io)
      f = io.read(4).unpack('g')[0]
      f
    end

    def self.decode_string(io)
      s = ''
      until (c = io.getc) == 0
	s << c
      end
      io.skip_padding
      s
    end

    def self.decode_blob(io)
      l = io.read(4).unpack('N')[0]
      b = io.read(l)
      io.skip_padding
      b
    end

    def self.decode_timetag(io)
      t1 = io.read(4).unpack('N')[0]
      t2 = io.read(4).unpack('N')[0]
      TimeTag.new [t1,t2]
    end

    # Takes a string containing one packet
    def self.decode(packet)
      # XXX I think it would have been better to use a StringScanner. Maybe I
      # will convert it someday...
      io = StringIO.new(packet)
      id = decode_string(io)
      if id =~ /\A\#/
	if id == '#bundle'
	  b = Bundle.new(decode_timetag(io))
	  until io.eof?
	    l = io.read(4).unpack('N')[0]
	    s = io.read(l)
	    b << decode(s)
	  end
	  b
	end
      elsif id =~ /\//
	m = Message.new(id)
	if io.getc == ?,
	  tags = decode_string(io)
	  tags.scan(/./) do |t|
	    case t
	    when 'i'
	      m << decode_int32(io)
	    when 'f'
	      m << decode_float32(io)
	    when 's'
	      m << decode_string(io)
	    when 'b'
	      m << decode_blob(io)

	    # right now we skip over nonstandard datatypes, but we'll want to
	    # add these datatypes too.
	    when /[htd]/; io.read(8)
	    when 'S'; decode_string(io)
	    when /[crm]/; io.read(4)
	    when /[TFNI\[\]]/;
	    end
	  end
	end
	m
      end
    end

    def self.pad(s)
      s + ("\000" * ((4 - s.size)%4))
    end

    def self.tag(o)
      case o
      when Fixnum;  'i'
      when TimeTag; 't'
      when Float;   'f'
      when Blob;    'b'
      when String;  's'
      else;         nil
      end
    end

    def self.encode(o)
      case o
      when Fixnum;  [o].pack 'N'
      when Float;   [o].pack 'g'
      when Blob;    pad([o.size].pack('N') + o)
      when String;  pad(o.sub(/\000.*\Z/, '') + "\000")
      when TimeTag; o.to_a.pack('NN')

      when Message
	s = encode(o.address)
	s << encode(o.tags)
	s << o.args.collect{|x| encode(x)}.join

      when Bundle
	s = encode('#bundle')
	s << encode(o.timetag)
	s << o.args.collect { |x| 
	  x2 = encode(x); [x2.size].pack('N') + x2 
	}.join
      end
    end

    private_class_method :decode_int32, :decode_float32, :decode_string,
      :decode_blob, :decode_timetag
  end

  # Mixin for making servers.
  # Your job is to read a packet and call dispatch(Packet.decode(raw)), ad
  # infinitum. You might mixin Client too for sending replies.
  module Server
    # 	prock.respond_to?(:call) #=> true
    # Pass an OSC pattern and either prock or a block.
    def add_method(pat, prock=nil, &block)
      pat = Pattern.new(pat) unless Pattern === pat
      if block_given? and prock
	raise ArgumentError, 'Specify either a block or a Proc, not both.'
      end
      prock = block if block_given?
      unless prock.respond_to?(:call)
	raise ArgumentError, "Prock doesn't respond to :call"
      end
      @cb ||= []
      @cb << [pat, prock]
    end

    # dispatch the provided message. It can be raw or already decoded with
    # Packet.decode
    def dispatch(mesg)
      unless Bundle === mesg or Message === mesg
        mesg = Packet.decode(mesg)
      end

      case mesg
      when Bundle; dispatch_bundle(mesg)
      when Message
	@cb.each do |pat, obj|
	  if pat.nil? or Pattern.intersect?(pat, mesg.address)
	    obj.call(mesg)
	  end
	end unless @cb.nil?
      else
	raise ArgumentError, "bad mesg"
      end
    end

    # May create a new thread to wait to dispatch according to p.timetag.
    def dispatch_bundle(p)
      diff = p.timetag.to_f - TimeTag.now
      if diff <= 0
	p.each {|m| dispatch m}
      else
	Thread.new do
	  sleep diff
	  p.each {|m| dispatch m}
	end
      end
    end
  end

  # Mixin for clients
  module Client
    # Message, Bundle, or as a shortcut the parameters to construct a Message.
    def encode(payload)
      case payload
      when Message,Bundle
      when Array
	payload = Message.new(*payload)
      else 
	raise ArgumentError
      end
      Packet.encode(payload)
    end
  end

  class UDPClient < UDPSocket
    include Client
    def send(mesg, flags, *args)
      super encode(mesg), flags, *args
    end
  end

  class UDPServer < UDPSocket
    include Server
    def serve
      loop do
	p,@peer = recvfrom(MAX_MSG_SIZE)
	dispatch Packet.decode(p)
      end
    end
  end
end

require 'osc/pattern'
