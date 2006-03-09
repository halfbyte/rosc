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
  end

  def test_packet
  end

  def test_server
  end

  def test_client
  end
end
