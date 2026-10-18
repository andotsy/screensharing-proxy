# frozen_string_literal: true

# Runs under Apple's /usr/bin/ruby (2.6). No gems, shell, firewall operations,
# protocol decoding or payload logging. Configuration arrives over the owned pipe.
require 'socket'
require 'json'
require 'ipaddr'

module ScreenSharingRelay
  class Failure < StandardError
    attr_reader :code
    def initialize(code)
      @code = code
      super(code)
    end
  end

  def self.now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  class Relay
    BUFFER_LIMIT = 1_048_576
    OUTPUT_LIMIT = 65_536
    DATAGRAM_LIMIT = 65_535
    attr_reader :session

    def initialize(input, output)
      @input, @output = input, output
      @owned = []
      @out = ''.b
      @session = '00000000-0000-0000-0000-000000000000'
      @received = @sent = @udp_received = @udp_sent = @udp_dropped = 0
      @tcp_accepted = @tcp_connected = @tcp_completed = 0
      @stopping = false
      @buffers, @eof, @write_closed = {}, {}, {}
    end

    def stop
      @stopping = true
    end

    def run
      @operation = 'configuration'
      configure(read_configuration)
      @operation = 'socketReservation'
      prepare
      @reservation_port = nil
      event('ready', {})
      @last_status = ScreenSharingRelay.now
      @accept_deadline = @last_status + 120
      until @stopping
        tick
      end
      status if @ready
      event('stopped', {})
      0
    rescue Failure => e
      failure(e.code, e)
      1
    rescue Errno::EADDRINUSE => e
      failure('addressInUse', e)
      1
    rescue Errno::EADDRNOTAVAIL => e
      failure('localAddressUnavailable', e)
      1
    rescue Errno::EPIPE, IOError => e
      failure('connectFailed', e) unless @operation == 'eventOutput'
      1
    rescue SystemCallError => e
      failure('connectFailed', e)
      1
    rescue StandardError
      # Exception strings can contain endpoints and user paths. Never emit them.
      failure('internalFailure')
      1
    ensure
      @owned.each { |socket| socket.close unless socket.closed? }
      flush_deadline = ScreenSharingRelay.now + 1
      while !@out.empty? && ScreenSharingRelay.now < flush_deadline
        break unless IO.select(nil, [@output], nil, 0.1)
        begin
          flush_output
        rescue IOError, SystemCallError
          break
        end
      end
    end

    private

    def read_configuration
      bytes = ''.b
      deadline = ScreenSharingRelay.now + 5
      loop do
        raise Failure.new('invalidConfiguration') if ScreenSharingRelay.now >= deadline
        raise Failure.new('invalidConfiguration') if @stopping
        next unless IO.select([@input], nil, nil, 0.1)
        chunk = @input.read_nonblock(8193, exception: false)
        raise Failure.new('invalidConfiguration') if chunk.nil?
        next if chunk == :wait_readable
        bytes << chunk
        raise Failure.new('invalidConfiguration') if bytes.bytesize > 8192
        if bytes.include?("\n")
          raise Failure.new('invalidConfiguration') unless bytes.end_with?("\n") && bytes.count("\n") == 1
          begin
            return JSON.parse(bytes)
          rescue JSON::ParserError
            raise Failure.new('invalidConfiguration')
          end
        end
      end
    end

    def ipv4(value)
      raise Failure.new('invalidConfiguration') unless value.is_a?(String) && value.match?(/\A\d{1,3}(\.\d{1,3}){3}\z/)
      address = IPAddr.new(value)
      raise Failure.new('invalidConfiguration') unless address.ipv4? && address.to_s == value
      first = value.split('.').first.to_i
      raise Failure.new('invalidConfiguration') unless (1..223).cover?(first)
      value
    rescue IPAddr::InvalidAddressError
      raise Failure.new('invalidConfiguration')
    end

    def port(value, maximum = 65_535)
      raise Failure.new('invalidConfiguration') unless value.is_a?(Integer) && (1024..maximum).cover?(value)
      value
    end

    def configure(config)
      raise Failure.new('invalidConfiguration') unless config.is_a?(Hash) && config['version'] == 1
      identifier = config['sessionID']
      raise Failure.new('invalidConfiguration') unless identifier.is_a?(String) && identifier.match?(/\A[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z/)
      @session = identifier
      @remote = ipv4(config['remoteAddress'])
      @remote_port = port(config.fetch('remoteControlPort', 5900))
      @base = port(config.fetch('mediaBase', 5900), 65_533)
      @local = ipv4(config.fetch('listenerAddress', '127.0.0.2'))
      @native = ipv4(config.fetch('nativeAddress', '127.0.0.1'))
      raise Failure.new('invalidConfiguration') unless @local.start_with?('127.') && @native.start_with?('127.') && @native != @local
      @listen_port = port(config.fetch('listenerPort', 15_900))
      probe = UDPSocket.new(Socket::AF_INET)
      begin
        probe.connect(@remote, @remote_port)
        @external = ipv4(config.fetch('externalAddress', probe.local_address.ip_address))
      ensure
        probe.close
      end
      raise Failure.new('invalidConfiguration') unless [@local, @native, @external, @remote].uniq.length == 4
    end

    def own(socket)
      @owned << socket
      socket.close_on_exec = true
      socket
    end

    def check_source_address(now)
      return if now < @source_check
      @operation = 'sourceCheck'
      # Existing sockets remain bound to this address. A fresh unbound socket
      # can select a different source without invalidating those bindings.
      # Never move a live session to that other address; fail if ours is gone.
      available = Socket.getifaddrs.any? do |interface|
        address = interface.addr
        address && address.ipv4? && address.ip_address == @external &&
          (interface.flags & Socket::IFF_UP) != 0
      end
      raise Failure.new('localAddressUnavailable') unless available
      @source_check = now + 5
    end

    def udp(address, peer, port_number)
      socket = own(UDPSocket.new(Socket::AF_INET))
      # Deliberately no SO_REUSEADDR/SO_REUSEPORT. Fail on a conflicting owner.
      socket.bind(address, port_number)
      socket.connect(peer, port_number)
      socket
    end

    def prepare
      @control_enabled = true
      @udp_routes = {}
      3.times do |offset|
        local = udp(@local, @native, @base + offset)
        external = udp(@external, @remote, @base + offset)
        @udp_routes[local] = [external, :sent]
        @udp_routes[external] = [local, :received]
      end
      @listener = own(Socket.new(:INET, :STREAM, 0))
      @listener.bind(Socket.sockaddr_in(@listen_port, @local))
      @listener.listen(1)
      @ready = true
    end

    def event(name, values)
      line = JSON.generate('version' => 1, 'sessionID' => @session, 'event' => { name => values }) + "\n"
      # A parent that stops consuming status must not cause unbounded memory use.
      if @out.bytesize + line.bytesize > OUTPUT_LIMIT
        @stopping = true
        return
      end
      @out << line
    end

    def status
      event('traffic', 'receivedBytes' => @received, 'sentBytes' => @sent)
      event('media', 'receivedDatagrams' => @udp_received, 'sentDatagrams' => @udp_sent, 'droppedDatagrams' => @udp_dropped)
      if @control_enabled
        event('control', control_status)
        event('controlConnections', 'accepted' => @tcp_accepted, 'connected' => @tcp_connected,
              'completed' => @tcp_completed)
      end
    end

    def control_status
      return @last_control if !@client && @last_control
      { 'nativeAccepted' => !@client.nil?, 'remoteConnected' => @remote_connected == true,
        'nativeReadClosed' => @eof[@client] == true, 'remoteReadClosed' => @eof[@server] == true }
    end

    def failure(code, error = nil)
      system_error = case error
                     when Errno::EADDRNOTAVAIL then 'addressUnavailable'
                     when Errno::EADDRINUSE then 'addressInUse'
                     when Errno::ECONNREFUSED then 'connectionRefused'
                     when Errno::ECONNRESET then 'connectionReset'
                     when Errno::ENETUNREACH then 'networkUnreachable'
                     when Errno::EHOSTUNREACH then 'hostUnreachable'
                     when Errno::EPERM, Errno::EACCES then 'permissionDenied'
                     when SystemCallError then 'other'
                     end
      # Retain the final counters even when failure occurs between periodic
      # updates. Only fixed labels are emitted, never exception text or errno paths.
      status if @ready
      context = { 'operation' => @operation, 'systemError' => system_error }
      context['port'] = @reservation_port if @reservation_port
      event('failureContext', context)
      event('failed', 'code' => code)
    end

    def flush_output
      @operation = 'eventOutput'
      written = @output.write_nonblock(@out, exception: false)
      @out = @out.byteslice(written..-1) || ''.b if written.is_a?(Integer)
    end

    def accept_native
      @operation = 'viewerAccept'
      result = @listener.accept_nonblock(exception: false)
      return if result == :wait_readable
      @client = own(result[0])
      raise Failure.new('nativeSourceMismatch') unless @client.remote_address.ip_address == @native
      @tcp_accepted += 1
      @last_control = nil
      @remote_connected = false
      unless @sequential_tcp
        @listener.close
        @listener = nil
      end
      @server = own(Socket.new(:INET, :STREAM, 0))
      [@client, @server].each { |s| s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1) }
      @operation = 'hostBind'
      @server.bind(Socket.sockaddr_in(0, @external))
      @operation = 'hostConnect'
      @connecting = @server.connect_nonblock(Socket.sockaddr_in(@remote_port, @remote), exception: false) == :wait_writable
      @remote_connected = !@connecting
      @tcp_connected += 1 if @remote_connected
      @connect_deadline = ScreenSharingRelay.now + 10
      @buffers = { @client => ''.b, @server => ''.b }
      @peers = { @client => @server, @server => @client }
    end

    def complete_tcp(reason = 'endOfStream')
      @tcp_completed += 1
      unless @sequential_tcp
        @stopping = true
        return
      end
      # Apple's viewer can close its discovery connection before reconnecting
      # for login. Keep the listener and media reservations through that gap.
      # Only one pair is active; release it after both half-closes have drained.
      @last_control = control_status
      discarded = @buffers.values.sum(&:bytesize)
      [@client, @server].each do |socket|
        socket.close
        @owned.delete(socket)
      end
      @client = @server = nil
      @buffers, @eof, @write_closed, @peers = {}, {}, {}, {}
      @connecting = false
      @accept_deadline = ScreenSharingRelay.now + 120
      status
      event('connectionClosed', 'reason' => reason, 'discardedBytes' => discarded)
    end

    def read_tcp(socket)
      @operation = 'tcpRead'
      destination = @peers.fetch(socket)
      room = BUFFER_LIMIT - @buffers.fetch(destination).bytesize
      return if room <= 0
      data = socket.read_nonblock([room, 262_144].min, exception: false)
      if data.nil?
        @eof[socket] = true
      elsif data != :wait_readable
        if @buffers[destination].empty?
          @buffers[destination] = data
        else
          @buffers[destination] << data
        end
        # Forward fresh bytes in this wakeup instead of allocating another
        # select set and waiting for the next event-loop pass. Backpressure
        # still retains at most BUFFER_LIMIT and uses writable readiness.
        write_tcp(destination) unless destination == @server && @connecting
      end
    end

    def write_tcp(socket)
      @operation = 'tcpWrite'
      data = @buffers.fetch(socket)
      return if data.empty?
      count = socket.write_nonblock(data, exception: false)
      return unless count.is_a?(Integer)
      if count == data.bytesize
        data.clear
      else
        @buffers[socket] = data.byteslice(count..-1)
      end
      socket == @client ? @received += count : @sent += count
    end

    def forward_udp(socket)
      32.times do
        begin
          @operation = 'udpReceive'
          packet = socket.recvmsg_nonblock(DATAGRAM_LIMIT, 0, 0, exception: false)
          break if packet == :wait_readable
          data, _sender, flags = packet
          if !@server || @connecting || (flags & Socket::MSG_TRUNC) != 0
            @udp_dropped += 1
            next
          end
          target, direction = @udp_routes.fetch(socket)
          @operation = 'udpSend'
          sent = target.sendmsg_nonblock(data, 0, nil, exception: false)
          if sent == data.bytesize
            if direction == :received
              @received += sent
              @udp_received += 1
            else
              @sent += sent
              @udp_sent += 1
            end
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
      @operation = 'waiting'
      now = ScreenSharingRelay.now
      if @sequential_tcp && !@server && @tcp_completed > 0 && now >= @accept_deadline
        @stopping = true
        return
      end
      if @connecting && now >= @connect_deadline
        @operation = 'hostConnect'
        raise Failure.new('connectionTimedOut')
      end
      if @listener && !@server && now >= @accept_deadline
        @operation = 'viewerAccept'
        raise Failure.new('connectionTimedOut')
      end
      reads = [@input] + @udp_routes.keys
      reads << @listener if @listener && !@server
      writes = @out.empty? ? [] : [@output]
      if @server
        @peers.each do |source, destination|
          next if source == @server && @connecting
          reads << source unless @eof[source] || @buffers[destination].bytesize >= BUFFER_LIMIT
        end
        writes << @server if @connecting || !@buffers[@server].empty?
        writes << @client unless @buffers[@client].empty?
      end
      selected = IO.select(reads, writes, nil, 0.1)
      if selected
        readable, writable = selected
        if readable.include?(@input)
          @operation = 'parentInput'
          command = @input.read_nonblock(1, exception: false)
          if command.nil?
            @stopping = true
            return
          end
          raise Failure.new('incompatibleProtocol') unless command == :wait_readable
        end
        if @connecting && writable.include?(@server)
          @operation = 'hostConnect'
          error = @server.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR).int
          raise SystemCallError.new('connect', error) unless error.zero?
          @connecting = false
          @remote_connected = true
          @tcp_connected += 1
        end
        readable.each do |socket|
          next if socket == @input
          if socket == @listener
            accept_native
          elsif @udp_routes.key?(socket)
            forward_udp(socket)
          else
            read_tcp(socket)
          end
        end
        writable.each do |socket|
          socket == @output ? flush_output : write_tcp(socket)
        end
      end
      if @server && !@connecting
        @peers.each do |destination, source|
          if @eof[source] && @buffers[destination].empty? && !@write_closed[destination]
            @operation = 'tcpShutdown'
            destination.shutdown(Socket::SHUT_WR)
            @write_closed[destination] = true
          end
        end
        complete_tcp if @eof[@client] && @eof[@server] && @buffers.values.all?(&:empty?)
      end
      if now - @last_status >= 1
        status
        @last_status = now
      end
    rescue Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN => error
      # Closing the native window may reset a stream with queued video. End
      # only that pair; never hide startup, network, or parent-pipe errors.
      raise unless @sequential_tcp && @server && %w[tcpRead tcpWrite tcpShutdown].include?(@operation)
      complete_tcp(error.is_a?(Errno::ECONNRESET) ? 'peerReset' : 'peerClosed')
    end
  end
end

if $PROGRAM_NAME == __FILE__
  relay = ScreenSharingRelay::Relay.new(STDIN, STDOUT)
  %w[TERM INT HUP].each { |signal| Signal.trap(signal) { relay.stop } }
  Signal.trap('PIPE', 'IGNORE')
  exit relay.run
end
