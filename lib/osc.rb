require 'forwardable'
require 'socket'

# Of particular interest are OSC::Client, OSC::Server, OSC::Message and
# OSC::Bundle.
module OSC
  # abstract class for atomic data types
  class DataType
    attr_accessor :val
    def initialize(val) 
      @val = val 
    end

    def to_i; @val.to_i; end
    def to_f; @val.to_f; end
    def to_s; @val.to_s; end

    protected
    def padding(s)
      s + ("\000" * ((4 - (s.size % 4)) % 4))
    end
  end

  # 32-bit big-endian two's complement integer
  class Int32 < DataType
    def tag; 'i'; end
    def encode; [@val].pack 'N'; end
  end

  # 64-bit big-endian fixed-point time tag
  class TimeTag < DataType
    def initialize(t)
      case t
      when NIL # immediately
	t1 = 0
	t2 = 1
      when Numeric
	t1, fr = t.divmod(1)
	t2 = (fr * (2**32)).to_i
      when Time
	t1, fr = (t.to_f + 2208988800).divmod(1)
	t2 = (fr * (2**32)).to_i
      else
	raise ArgumentError, 'invalid time'
      end
      @encoded = [t1, t2].pack('N2')
    end
    def encode; @encoded; end
  end

  # 32-bit big-endian IEEE 754 floating point number
  class Float32 < DataType
    def tag; 'f'; end
    def encode; [@val].pack 'g'; end
  end

  # A sequence of non-null ASCII characters followed by a null, followed by 0-3
  # additional null characters to make the total number of bits a multiple of
  # 32.
  class OSCString < DataType
    def tag; 's'; end
    def encode
      padding(@val.sub(/\000.*\Z/, '') + "\000")
    end
  end

  # An int32 size count, followed by that many 8-bit bytes of arbitrary binary
  # data, followed by 0-3 additional zero bytes to make the total number of
  # bits a multiple of 32.
  class Blob < DataType
    def tag; 'b'; end
    def encode; 
      padding([@val.size].pack('N') + @val)
    end
  end

  class Message
    attr_accessor :address, :args

    # Address pattern, type tag string, and arguments. See the OSC
    # documentation for more details.
    def initialize(address, tags=nil, *args)
      @address = address
      @args = []
      args.each_with_index do |arg, i|
	if tags and tags[i]
	  case tags[i]
	  when ?i; @args << Int32.new(arg)
	  when ?f; @args << Float32.new(arg)
	  when ?s; @args << OSCString.new(arg)
	  when ?b; @args << Blob.new(arg)
	  when ?*; @args << arg
	  else;    raise ArgumentError, 'unknown type tag'
	  end
	else
	  case arg
	  when Integer;  @args << Int32.new(arg)
	  when Float;    @args << Float32.new(arg)
	  when String;   @args << OSCString.new(arg)
	  when DataType; @args << arg
	  end
	end
      end
    end

    def tags
      ',' + @args.collect{|arg| arg.tag}.join
    end

    def encode
      s = OSCString.new(@address).encode
      s << OSCString.new(tags).encode
      s << @args.collect{|arg| arg.encode}.join
    end

    def to_a; @args.collect{|x| x.val}; end

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

    def initialize(timetag=nil, *args)
      @timetag = TimeTag.new(timetag) unless timetag.nil?
      @args = args
    end

    def contents; @args; end
    def to_a; contents; end

    def encode()
      s = OSCString.new('#bundle').encode
      s << @timetag.encode
      s << @args.collect{ |x| 
	x2 = x.encode; [x2.size].pack('N') + x2
      }.join
    end

    extend Forwardable
    include Enumerable

    de = (Array.instance_methods - self.instance_methods)
    de -= %w(assoc flatten flatten! pack rassoc transpose)
    de += %w(include? sort)

    def_delegators(:@args, *de)

    undef_method :zip
  end

  # Unit of transmission. 
  class Packet

    # Helper class that acts a little bit like IO for parsing
    class PO
      def initialize(str) 
	@str, @index = str, 0 
      end

      def rem 
	@str.length - @index 
      end

      def eof?
	rem <= 0 
      end

      def skip(n) 
	@index += n 
      end

      def skip_padding 
	skip((4 - (@index % 4)) % 4) 
      end

      def getn(n)
	raise EOFError if rem < n
	s = @str[@index, n]
	skip(n)
	s
      end

      def getc
	raise EOFError if rem < 1
	c = @str[@index]
	skip(1)
	c
      end
    end

    def self.decode_int32(io)
      i = io.getn(4).unpack('N')[0]
      i = 2**32 - i if i > (2**31-1)
      i
    end

    def self.decode_float32(io)
      f = io.getn(4).unpack('g')[0]
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
      l = io.getn(4).unpack('N')[0]
      b = io.getn(l)
      io.skip_padding
      b
    end

    def self.decode_timetag(io)
      t1 = io.getn(4).unpack('N')[0]
      t2 = io.getn(4).unpack('N')[0]
      [t1, t2]
    end

    def self.decode2(time, packet, list)
      io = PO.new(packet)
      id = decode_string(io)
      if id =~ /\A\#/
	if id == '#bundle'
	  t1, t2 = decode_timetag(io)
	  if t1 == 0 and t2 == 1
	    time = nil
	  else
	    time = t1 + t2.to_f / (2**32)
	  end
	  until io.eof?
	    l = io.getn(4).unpack('N')[0]
	    s = io.getn(l)
	    decode2(time, s, list)
	  end
	end
      elsif id =~ /\//
	address = id
	if io.getc == ?,
	  tags = decode_string(io)
	  args = []
	  tags.scan(/./) do |t|
	    case t
	    when 'i'
	      i = decode_int32(io)
	      args << Int32.new(i)
	    when 'f'
	      f = decode_float32(io)
	      args << Float32.new(f)
	    when 's'
	      s = decode_string(io)
	      args << OSCString.new(s)
	    when 'b'
	      b = decode_blob(io)
	      args << Blob.new(b)
	    when /[htd]/; io.read(8)
	    when 'S'; decode_string(io)
	    when /[crm]/; io.read(4)
	    when /[TFNI\[\]]/;
	    end
	  end
	end
	list << [time, Message.new(address, nil, *args)]
      end
    end

    private_class_method :decode_int32, :decode_float32, :decode_string,
      :decode_blob, :decode_timetag, :decode2

    def self.decode(packet)
      list = []
      decode2(nil, packet, list)
      list
    end
  end

  # Base class for clients
  class Client
    # pass in a Message or Bundle and get out a raw string ready to send on
    # down the line
    def encode(payload)
      Packet.new(payload).encode
    end
  end

  # Base class for servers.
  # Just implement recv_packet (see the prototype here), and give it a Client
  # for sending replies.
  class Server
    attr_accessor :client

    def initialize
      @cb = []
    end

    # Prototype method that does nothing interesting. You should recv one raw
    # OSC packet of data and return Packet.decode(raw)
    def recv_packet
      raw = recv
      Packet.decode raw
    end

    # 	prock.respond_to?(:call) #=> true
    # Pass either prock or a block.
    def add_method(pat, prock=nil, &block)
      case pat
      when NIL; re = pat
      when Regexp; re = pat
      when String
	pat = pat.dup
	pat.gsub!(/[.^(|)]/, '\\1')
	pat.gsub!(/\?/, '[^/]')
	pat.gsub!(/\*/, '[^/]*')
	pat.gsub!(/\[!/, '[^')
	pat.gsub!(/\{/, '(')
	pat.gsub!(/,/, '|')
	pat.gsub!(/\}/, ')')
	pat.gsub!(/\A/, '\A')
	pat.gsub!(/\Z/, '\Z')
	re = Regexp.new(pat)
      else
	raise ArgumentError, 'invalid pattern'
      end
      if block_given? and prock
	raise ArgumentError, 'Specify either a block or a Proc, not both.'
      end
      prock = block if block_given?
      raise ArgumentError, "Prock doesn't respond to :call"
      @cb << [re, prock]
    end

    def dispatch(mesg)
      @cb.each do |re, obj|
	if re.nil? or re =~ mesg.address
	  obj.accept(mesg)
	end
      end
    end
    def dispatch_bundle(b)
      b.each {|m| dispatch m}
    end

    def serve
      loop do
	p = recv_packet
	case p
	when Bundle
	  diff = p.time - TimeTag.now
	  if diff <= 0
	    dispatch_bundle p
	  else
	    Thread.fork do
	      sleep diff
	      dispatch_bundle p
	    end
	  end
	when Message
	  dispatch p
	end
      end
    end
  end

  class UDPClient < UDPSocket
    def send(payload)
      super(encode(payload))
    end
  end
end

# TODO TimeTag, Packet.decode, Pattern
