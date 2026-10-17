# frozen_string_literal: true
# Model the inspected native UDP calls using owned ephemeral sockets and
# synthetic loopback datagrams. This does not start Screen Sharing, test its
# firewall attribution, alter interfaces, or forward any user traffic.
require 'socket'
require 'json'

PACKETS = 4
LOOPBACK = '127.0.0.1'

def make_socket(reuse, owned)
  socket = UDPSocket.new(Socket::AF_INET)
  owned << socket
  if reuse
    socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
    socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEPORT, 1)
  end
  socket
end

def exchange(sockets, destinations)
  counts = {}
  unexpected = 0
  send_errors = {}
  token = Random.new.bytes(16)
  sockets.each do |sender, socket|
    begin
      connected = begin
        socket.remote_address
        true
      rescue Errno::ENOTCONN
        false
      end
      PACKETS.times do |index|
        payload = token + "#{sender}:#{index}"
        if connected
          socket.send(payload, 0)
        else
          socket.send(payload, 0, LOOPBACK, destinations.fetch(sender))
        end
      end
    rescue SystemCallError => error
      send_errors[sender] = error.class.name
    end
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.2
    loop do
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      break if remaining <= 0
      ready = IO.select(sockets.values, nil, nil, remaining)
      break unless ready
      ready[0].each do |receiver|
        # A bounded drain also prevents unrelated traffic from extending a run.
        16.times do
          packet = receiver.recvfrom_nonblock(256, exception: false)
          break if packet == :wait_readable
          payload, source = packet
          expected = (0...PACKETS).any? { |index| payload == token + "#{sender}:#{index}" }
          unless expected && source[3] == LOOPBACK && source[1] == socket.local_address.ip_port
            unexpected += 1
            next
          end
          direction = "#{sender}->#{sockets.key(receiver)}"
          counts[direction] = counts.fetch(direction, 0) + 1
        end
      end
    end
  end
  { 'received' => counts, 'sendErrors' => send_errors, 'unexpectedPackets' => unexpected }
end

def probe(first:, relay_reuse:, relay_connected:, relay_wildcard:)
  owned = []
  result = { 'first' => first, 'relayReuse' => relay_reuse,
             'relayConnected' => relay_connected, 'relayWildcard' => relay_wildcard }
  sockets = {}
  port = 0
  [first, first == 'native_model' ? 'relay' : 'native_model'].each do |role|
    result['stage'] = "#{role}.bind"
    native = role == 'native_model'
    socket = make_socket(native || relay_reuse, owned)
    socket.bind(native || relay_wildcard ? '0.0.0.0' : LOOPBACK, port)
    port = socket.local_address.ip_port
    sockets[role] = socket
    if native || relay_connected
      result['stage'] = "#{role}.connect"
      begin
        socket.connect(LOOPBACK, port)
      rescue Errno::EADDRINUSE => error
        # The inspected native method tolerates this specific connect failure.
        # Preserve it in the output; continued model sends do not mean success.
        result["#{role}ConnectError"] = error.class.name
      end
    end
  end
  result['stage'] = 'exchange'
  result.merge!(exchange(sockets, sockets.keys.to_h { |role| [role, port] }))
  result['bidirectionalDelivery'] = result['received'] == {
    'native_model->relay' => PACKETS, 'relay->native_model' => PACKETS
  } && result['sendErrors'].empty? && result['unexpectedPackets'].zero?
  result
rescue SystemCallError => error
  result.merge('errorType' => error.class.name)
ensure
  owned.each(&:close)
end

def receive_fixture(socket, expected, source_port)
  raise 'fixture receive timeout' unless IO.select([socket], nil, nil, 0.5)
  payload, source = socket.recvfrom_nonblock(256)
  raise 'fixture payload mismatch' unless payload == expected
  raise 'fixture source mismatch' unless source[3] == LOOPBACK && source[1] == source_port
end

# Model distinct network peers using two ephemeral ports on the existing
# loopback address. This isolates UDP demultiplexing; it does not reproduce
# Apple's equal media ports on two separate Macs or invoke AVConference.
def probe_prebound_peer
  owned = []
  result = {}
  remote = make_socket(false, owned)
  remote.bind(LOOPBACK, 0)
  remote_port = remote.local_address.ip_port
  relay = make_socket(true, owned)
  relay.bind(LOOPBACK, 0)
  local_port = relay.local_address.ip_port
  relay.connect(LOOPBACK, remote_port)
  remote.connect(LOOPBACK, local_port)

  native = make_socket(true, owned)
  native.bind('0.0.0.0', local_port)
  begin
    native.connect(LOOPBACK, remote_port)
    return { 'candidateAvailable' => false, 'reason' => 'duplicateConnectSucceeded' }
  rescue Errno::EADDRINUSE => error
    result['nativeConnectError'] = error.class.name
  end
  result['nativeRemainsWildcard'] = native.local_address.ip_address == '0.0.0.0'
  injector = make_socket(false, owned)
  injector.bind(LOOPBACK, 0)
  injector_port = injector.local_address.ip_port
  incoming = Random.new.bytes(32)
  feedback = Random.new.bytes(32)

  remote.send(incoming, 0)
  receive_fixture(relay, incoming, remote_port)
  result['remoteToRelay'] = true
  injector.send(incoming, 0, LOOPBACK, local_port)
  receive_fixture(native, incoming, injector_port)
  result['localInjectionToNative'] = true
  native.send(feedback, 0, LOOPBACK, remote_port)
  receive_fixture(remote, feedback, local_port)
  result['nativeFeedbackWithDestination'] = true
  begin
    native.send(feedback, 0)
    result['nativeSendWithoutDestination'] = 'accepted'
  rescue SystemCallError => error
    result['nativeSendWithoutDestination'] = error.class.name
  end
  result['candidateAvailable'] = true
  result
rescue StandardError => error
  result.merge('candidateAvailable' => false, 'errorType' => error.class.name)
ensure
  owned.each(&:close)
end

# A two-port control verifies that the fixture can observe both directions.
owned = []
begin
  sockets = %w[native_model relay].to_h do |role|
    socket = make_socket(false, owned)
    socket.bind(LOOPBACK, 0)
    [role, socket]
  end
  control = exchange(sockets, {
    'native_model' => sockets.fetch('relay').local_address.ip_port,
    'relay' => sockets.fetch('native_model').local_address.ip_port
  })
  raise 'two-port control failed' unless control == {
    'received' => { 'native_model->relay' => PACKETS, 'relay->native_model' => PACKETS },
    'sendErrors' => {}, 'unexpectedPackets' => 0
  }
ensure
  owned.each(&:close)
end

results = %w[relay native_model].product([false, true], [false, true], [false, true]).map do |first, reuse, connected, wildcard|
  probe(first: first, relay_reuse: reuse, relay_connected: connected, relay_wildcard: wildcard)
end
puts JSON.pretty_generate('ruby' => RUBY_VERSION, 'platform' => RUBY_PLATFORM,
                          'twoPortControl' => control, 'samePortCases' => results,
                          'preboundPeerModel' => probe_prebound_peer)
