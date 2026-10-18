# frozen_string_literal: true

# Bidirectional relay on the existing 127.0.0.1 address. Apple
# connects TCP to this address; local media must present that same peer tuple.
require_relative 'relay'

module ScreenSharingRelay
  class LoopbackRelay < Relay
    private

    def configure(config)
      raise Failure.new('unavailable') unless RUBY_PLATFORM.include?('darwin')
      raise Failure.new('invalidConfiguration') unless config.is_a?(Hash) && config['version'] == 1
      identifier = config['sessionID']
      raise Failure.new('invalidConfiguration') unless identifier.is_a?(String) && identifier.match?(/\A[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z/)
      @session = identifier
      @remote = ipv4(config['remoteAddress'])
      raise Failure.new('invalidConfiguration') if @remote.start_with?('127.')
      @remote_port = port(config.fetch('remoteControlPort', 5900))
      @base = port(config.fetch('mediaBase', 5900), 65_533)
      # A separate peer base is for local fixtures only.
      @remote_base = port(config.fetch('remoteMediaBase', @base), 65_533)
      # Rubyfied can move the native receiver to its own loopback-only ports.
      # The standalone, unpatched-viewer experiment keeps its original layout.
      if config.key?('nativeMediaBase')
        @native_base = port(config['nativeMediaBase'], 65_533)
        raise Failure.new('invalidConfiguration') if (@native_base - @base).abs < 3
      end
      @listen_port = port(config.fetch('listenerPort', 15_900))
      @duration = config.fetch('maximumDurationSeconds', 1800)
      raise Failure.new('invalidConfiguration') unless @duration.is_a?(Integer) &&
        (@duration.zero? || (10..86_400).cover?(@duration))
      @local = @native = '127.0.0.1'
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

    def reserve(address, peer, local_port, peer_port, operation)
      @operation, @reservation_port = operation, local_port
      socket = own(UDPSocket.new(Socket::AF_INET))
      socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, 262_144)
      socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, 131_072)
      # Refuse an existing owner before permitting Apple's later wildcard bind.
      socket.bind(address, local_port)
      unless @native_base
        socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
        socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEPORT, 1)
      end
      @operation = 'udpPeerConnect'
      socket.connect(peer, peer_port)
      socket
    end

    def prepare
      @control_enabled = true
      @sequential_tcp = true
      @udp_routes = {}
      3.times do |offset|
        number = @base + offset
        external = reserve(@external, @remote, number, @remote_base + offset, 'udpExternalBind')
        if @native_base
          local = reserve(@local, @native, number, @native_base + offset, 'udpFeedbackBind')
          @udp_routes[external] = [local, :received]
          @udp_routes[local] = [external, :sent]
          next
        end
        feedback = reserve(@local, @local, number, number, 'udpFeedbackBind')
        # The connected self tuple receives native replies and makes Apple's
        # duplicate connect leave a wildcard, unconnected descriptor on Darwin.
        # Send media from that expected loopback peer to the existing LAN IP:
        # the wildcard native socket receives it, while the connected relay
        # sockets reject the different peer tuples. Do not send media to self.
        @operation = 'udpInjectorBind'
        injector = own(UDPSocket.new(Socket::AF_INET))
        injector.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, 131_072)
        injector.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
        injector.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEPORT, 1)
        injector.bind(@local, number)
        @operation = 'udpPeerConnect'
        injector.connect(@external, number)
        @udp_routes[external] = [injector, :received]
        @udp_routes[feedback] = [external, :sent]
      end
      @operation, @reservation_port = 'tcpListenerBind', @listen_port
      @listener = own(Socket.new(:INET, :STREAM, 0))
      # Allow a fresh experiment after our previous TCP session's TIME_WAIT.
      # No SO_REUSEPORT: another active listener must still prevent startup.
      @listener.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
      @listener.bind(Socket.sockaddr_in(@listen_port, @local))
      @operation = 'tcpListen'
      @listener.listen(1)
      @source_check = ScreenSharingRelay.now + 5
      @expires = ScreenSharingRelay.now + @duration unless @duration.zero?
      @ready = true
    end

    def tick
      now = ScreenSharingRelay.now
      raise Failure.new('connectionTimedOut') if @expires && now >= @expires
      check_source_address(now)
      super
    end
  end
end

if $PROGRAM_NAME == __FILE__
  relay = ScreenSharingRelay::LoopbackRelay.new(STDIN, STDOUT)
  %w[TERM INT HUP].each { |signal| Signal.trap(signal) { relay.stop } }
  Signal.trap('PIPE', 'IGNORE')
  exit relay.run
end
