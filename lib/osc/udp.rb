require 'socket'

module OSC
  MAX_MSG_SIZE=32768
  # A ::UDPSocket with a send method that accepts a Message or Bundle or
  # a raw String.
  class UDPSocket < ::UDPSocket
    def send(msg, *args)
      case msg
      when Message,Bundle
        super(msg.encode, *args)
      else
        super(msg, *args)
      end
    end

    def recvfrom(len, flags=0)
      data, sender = super(len, flags)
      m = Packet.decode(data)
      m.source = sender
      [m, sender]
    rescue
      return [data, sender]
    end

    def send_timestamped(msg, ts, *args)
      m = Bundle.new(ts, msg)
      send(m, *args)
    end
    alias :send_ts :send_timestamped
  end

  class UDPServer < OSC::UDPSocket
    include Server
    def serve
      loop do
	p, sender = recvfrom(MAX_MSG_SIZE)
	dispatch p
      end
    end

    # send msg2 as a reply to msg1
    def reply(msg1, msg2)
      domain, port, host, ip = msg2.source
      send(msg2, 0, host, port)
    end
  end
end
