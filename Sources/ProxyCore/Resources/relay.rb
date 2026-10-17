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
      @stopping = false
      @buffers, @eof, @write_closed = {}, {}, {}
    end

    def stop
      @stopping = true
    end

    def run
      configure(read_configuration)
      prepare
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
      event('failed', { 'code' => e.code })
      1
    rescue Errno::EADDRINUSE
      event('failed', { 'code' => 'addressInUse' })
      1
    rescue Errno::EADDRNOTAVAIL
      event('failed', { 'code' => 'localAddressUnavailable' })
      1
    rescue Errno::EPIPE, IOError
      1
    rescue SystemCallError
      event('failed', { 'code' => 'connectFailed' })
      1
    rescue StandardError
      # Exception strings can contain endpoints and user paths. Never emit them.
      event('failed', { 'code' => 'internalFailure' })
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

    def udp(address, peer, port_number)
      socket = own(UDPSocket.new(Socket::AF_INET))
      # Deliberately no SO_REUSEADDR/SO_REUSEPORT. Fail on a conflicting owner.
      socket.bind(address, port_number)
      socket.connect(peer, port_number)
      socket
    end

    def prepare
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
    end

    def flush_output
      written = @output.write_nonblock(@out, exception: false)
      @out = @out.byteslice(written..-1) || ''.b if written.is_a?(Integer)
    end

    def accept_native
      result = @listener.accept_nonblock(exception: false)
      return if result == :wait_readable
      @client = own(result[0])
      raise Failure.new('nativeSourceMismatch') unless @client.remote_address.ip_address == @native
      @listener.close
      @listener = nil
      @server = own(Socket.new(:INET, :STREAM, 0))
      [@client, @server].each { |s| s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1) }
      @server.bind(Socket.sockaddr_in(0, @external))
      @connecting = @server.connect_nonblock(Socket.sockaddr_in(@remote_port, @remote), exception: false) == :wait_writable
      @connect_deadline = ScreenSharingRelay.now + 10
      @buffers = { @client => ''.b, @server => ''.b }
      @peers = { @client => @server, @server => @client }
    end

    def read_tcp(socket)
      destination = @peers.fetch(socket)
      room = BUFFER_LIMIT - @buffers.fetch(destination).bytesize
      return if room <= 0
      data = socket.read_nonblock([room, 65_536].min, exception: false)
      if data.nil?
        @eof[socket] = true
      elsif data != :wait_readable
        @buffers[destination] << data
      end
    end

    def write_tcp(socket)
      data = @buffers.fetch(socket)
      return if data.empty?
      count = socket.write_nonblock(data, exception: false)
      return unless count.is_a?(Integer)
      @buffers[socket] = data.byteslice(count..-1) || ''.b
      socket == @client ? @received += count : @sent += count
    end

    def forward_udp(socket)
      32.times do
        begin
          packet = socket.recvmsg_nonblock(DATAGRAM_LIMIT, 0, 0, exception: false)
          break if packet == :wait_readable
          data, _sender, flags = packet
          if !@server || @connecting || (flags & Socket::MSG_TRUNC) != 0
            @udp_dropped += 1
            next
          end
          target, direction = @udp_routes.fetch(socket)
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
      now = ScreenSharingRelay.now
      raise Failure.new('connectionTimedOut') if (@listener && now >= @accept_deadline) || (@connecting && now >= @connect_deadline)
      reads = [@input] + @udp_routes.keys
      reads << @listener if @listener
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
          command = @input.read_nonblock(1, exception: false)
          if command.nil?
            @stopping = true
            return
          end
          raise Failure.new('incompatibleProtocol') unless command == :wait_readable
        end
        if @connecting && writable.include?(@server)
          error = @server.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR).int
          raise Failure.new('connectFailed') unless error.zero?
          @connecting = false
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
            destination.shutdown(Socket::SHUT_WR)
            @write_closed[destination] = true
          end
        end
        @stopping = true if @eof[@client] && @eof[@server] && @buffers.values.all?(&:empty?)
      end
      if now - @last_status >= 1
        status
        @last_status = now
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  relay = ScreenSharingRelay::Relay.new(STDIN, STDOUT)
  %w[TERM INT HUP].each { |signal| Signal.trap(signal) { relay.stop } }
  Signal.trap('PIPE', 'IGNORE')
  exit relay.run
end
