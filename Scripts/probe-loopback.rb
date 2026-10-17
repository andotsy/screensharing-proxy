# frozen_string_literal: true
# Opens and closes temporary sockets only. Never changes interfaces or routes.
require 'socket'
require 'json'

results = []
['127.0.0.1', '127.0.0.2', '127.0.0.3', '127.0.0.4', '::1', 'fe80::1%lo0'].each do |address|
  owned = []
  result = { 'address' => address }
  begin
    family = address.include?(':') ? Socket::AF_INET6 : Socket::AF_INET
    udp = UDPSocket.new(family)
    owned << udp
    udp.bind(address, 0)
    result['udpBind'] = true
    server = TCPServer.new(address, 0)
    owned << server
    client = Socket.new(family, Socket::SOCK_STREAM, 0)
    owned << client
    pending = client.connect_nonblock(Socket.sockaddr_in(server.local_address.ip_port, address), exception: false)
    if pending == :wait_writable
      raise 'connectTimeout' unless IO.select(nil, [client], nil, 2)
      raise 'connectFailed' unless client.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR).int.zero?
    end
    result['tcpConnect'] = true
    result['nativeSource'] = client.local_address.ip_address
  rescue StandardError => e
    result['errorType'] = e.class.name
  ensure
    owned.each(&:close)
  end
  results << result
end
puts JSON.pretty_generate('ruby' => RUBY_VERSION, 'loopback' => results)
