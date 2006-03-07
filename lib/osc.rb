module OSC
  class DataType; end
  class Int32 < DataType; end
  class Timetag < DataType; end
  class Float32 < DataType; end
  class String < DataType; end
  class Blob < DataType; end

  class Packet; end
  class Message; end
  class AddressPattern; end
  class TypeTag < String; end
  class Argument < ::String; end
  class Bundle; end

  class Client; end
  class Server; end
end
