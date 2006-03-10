require 'osc'
require 'time'
require 'test/unit'

class TC_OSC < Test::Unit::TestCase
  include OSC
  # def setup
  # end

  # def teardown
  # end

  def test_datatype
    s = 'foo'
    i = 42
    f = 3.14

    dt = Int32.new i
    assert_equal i,dt.to_i
    assert_equal 'i',dt.tag
    dt = Float32.new f
    assert_equal f,dt.to_f
    assert_equal 'f',dt.tag
    dt = OSCString.new s
    assert_equal s,dt.to_s
    assert_equal 's',dt.tag
    assert_equal s+"\000",dt.encode
    b = File.read($0)
    dt = Blob.new b
    assert_equal b,dt.to_s
    assert_equal 'b',dt.tag
    assert_equal b.size+4 + (b.size+4)%4, dt.encode.size
  end

  def test_timetag
    t1 = TimeTag::JAN_1970
    t2 = Time.now
    t3 = t2.to_f+t1

    tt = TimeTag.new t2
    assert_equal t3, tt.to_f
    assert_equal t3.floor, tt.to_i
    assert_equal t3.floor - t3, tt.to_i - tt.to_f
    assert_equal [0,1].pack('NN'), TimeTag.new(nil).encode
    assert_equal t2.to_i,tt.to_time.to_i # to_f has roundoff error at the lsb
  end

  def test_message
    a = 'foo'
    b = 'quux'
    m = Message.new '/foobar', 'ssi', a, b, 1
    assert_equal "/foobar\000"+",ssi\000\000\000\000"+
      "foo\000"+"quux\000\000\000\000"+"\001\000\000\000", m.encode
  end

  def test_bundle
    m1 = Message.new '/foo','s','foo'
    m2 = Message.new '/bar','s','bar'
    t = Time.now
    b = Bundle.new(TimeTag.new(Time.at(t + 10)), m1, m2)
    b2 = Bundle.new(nil, b, m1)

    assert_equal 10, b.timetag.to_time.to_i - t.to_i
    e = b2.encode
    assert_equal '#bundle', e[0,7]
    assert_equal "\000\000\000\000\000\000\000\001", e[8,8]
    assert_equal '#bundle', e[16+4,7]
    assert_equal '/foo', e[16+4+b.encode.size+4,4]
    assert_equal 0, e.size % 4

    assert_instance_of Array, b2.to_a
    assert_instance_of Bundle, b2.to_a[0]
    assert_instance_of Message, b2.to_a[1]
  end

  def test_packet
    m = Message.new '/foo','s','foo'
    b = Bundle.new nil,m
    p1 = Packet.new m
    p2 = Packet.new b
    assert_equal 4+m.encode.size, p1.encode.size
    assert_equal m.encode, p1.encode[4,m.encode.size]
    assert_equal [m.encode.size], p1.encode[0,4].unpack('N')
    assert_equal 4+b.encode.size, p2.size

    p3 = Packet.decode(p1.encode)
    assert_equal p1,p3
  end

  def test_server
  end

  def test_client
  end
end
