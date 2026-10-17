# frozen_string_literal: true

# Experimental incoming UDP path. Apple retains direct TCP and outbound UDP.
# No interface aliases, packet-filter rules, private APIs or system services.
require_relative 'relay'

module ScreenSharingRelay
  class IncomingRelay < Relay
    private

    def configure(config)
      raise Failure.new('invalidConfiguration') unless config.is_a?(Hash) && config['version'] == 1
      identifier = config['sessionID']
      raise Failure.new('invalidConfiguration') unless identifier.is_a?(String) && identifier.match?(/\A[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z/)
      @session = identifier
      @remote = ipv4(config['remoteAddress'])
      @base = port(config.fetch('mediaBase', 5900), 65_533)
      # The app uses equal local/remote bases. A distinct peer base permits
      # real-socket fixtures on one existing address, without creating aliases.
      @remote_base = port(config.fetch('remoteMediaBase', @base), 65_533)
      @external = route_address
      raise Failure.new('invalidConfiguration') if @external == @remote && @base == @remote_base
    end

    def route_address
      probe = UDPSocket.new(Socket::AF_INET)
      begin
        probe.connect(@remote, @remote_base)
        ipv4(probe.local_address.ip_address)
      ensure
        probe.close
      end
    end

    def prepare
      @udp_routes = {}
      3.times do |offset|
        external = own(UDPSocket.new(Socket::AF_INET))
        external.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, 262_144)
        # Reserve exclusively first. An existing connected or wildcard socket
        # must prevent startup, even when that owner enabled reuse. Enable reuse
        # only after reservation so Apple's later wildcard bind can coexist.
        external.bind(@external, @base + offset)
        external.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
        external.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEPORT, 1)
        external.connect(@remote, @remote_base + offset)
        injector = own(UDPSocket.new(Socket::AF_INET))
        injector.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, 131_072)
        injector.bind('127.0.0.1', 0)
        injector.connect(@external, @base + offset)
        @udp_routes[external] = [injector, :received]
      end
      @route_check = ScreenSharingRelay.now + 5
      @expires = ScreenSharingRelay.now + 1800
      @ready = true
    end

    def forward_udp(socket)
      64.times do
        begin
          packet = socket.recvmsg_nonblock(DATAGRAM_LIMIT, 0, 0, exception: false)
          break if packet == :wait_readable
          data, _sender, flags = packet
          @received += data.bytesize
          @udp_received += 1
          if (flags & Socket::MSG_TRUNC) != 0
            @udp_dropped += 1
            next
          end
          injector = @udp_routes.fetch(socket).first
          sent = injector.sendmsg_nonblock(data, 0, nil, exception: false)
          if sent == data.bytesize
            @sent += sent
            @udp_sent += 1
          else
            @udp_dropped += 1
          end
        rescue Errno::ECONNREFUSED, Errno::ENOBUFS, Errno::EMSGSIZE, Errno::EHOSTUNREACH
          @udp_dropped += 1
          break
        end
      end
    end

    def tick
      now = ScreenSharingRelay.now
      raise Failure.new('connectionTimedOut') if now >= @expires
      if now >= @route_check
        raise Failure.new('localAddressUnavailable') unless route_address == @external
        @route_check = now + 5
      end
      selected = IO.select([@input] + @udp_routes.keys, @out.empty? ? [] : [@output], nil, 0.1)
      if selected
        readable, writable = selected
        if readable.include?(@input)
          command = @input.read_nonblock(1, exception: false)
          if command.nil?
            @stopping = true
            return
          end
          raise Failure.new('incompatibleProtocol') unless command == :wait_readable
        end
        readable.each { |socket| forward_udp(socket) unless socket == @input }
        flush_output if writable.include?(@output)
      end
      if now - @last_status >= 1
        status
        @last_status = now
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  relay = ScreenSharingRelay::IncomingRelay.new(STDIN, STDOUT)
  %w[TERM INT HUP].each { |signal| Signal.trap(signal) { relay.stop } }
  Signal.trap('PIPE', 'IGNORE')
  exit relay.run
end
