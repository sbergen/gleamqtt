import fake_server.{
  type ConnectedServer, type ListeningServer, type ReceivedConnectData,
}
import gleam/erlang/process
import gleeunit/should
import spoke.{ConnectionStateChanged}
import spoke/internal/packet
import spoke/internal/packet/server/outgoing as server_out

const default_client_id = "fake-client-id"

pub fn connect_and_disconnect_test() {
  let #(client, server, details) = connect(False, "test-client-id", 42)

  details.client_id |> should.equal("test-client-id")
  details.keep_alive |> should.equal(42)

  fake_server.disconnect(client, server)
}

pub fn reconnect_after_rejected_connect_test() {
  let #(client, server, result, _details) =
    connect_with_error(packet.BadUsernameOrPassword, default_client_id, 10)

  result |> should.equal(spoke.BadUsernameOrPassword)

  let server = fake_server.reconnect(client, server, True)

  fake_server.disconnect(client, server)
}

pub fn aborted_connect_disconnects_expectedly_test() {
  let server = fake_server.start_server()
  let client = start_client_with_defaults(server.port)

  spoke.connect(client)

  let server = fake_server.expect_connection_established(server)
  spoke.disconnect(client)

  let assert Ok(ConnectionStateChanged(spoke.Disconnected)) =
    process.receive(spoke.updates(client), 10)

  fake_server.expect_connection_closed(server)
}

pub fn connecting_when_already_connected_succeeds_test() {
  let server = fake_server.start_server()
  let client = start_client_with_defaults(server.port)

  // Start first connect
  spoke.connect(client)
  let socket = fake_server.expect_connection_established(server)

  // Start overlapping connect
  spoke.connect(client)

  // Finish initial connect
  fake_server.drop_incoming_data(socket)
  fake_server.send_response(socket, server_out.ConnAck(Ok(False)))
  let assert Ok(ConnectionStateChanged(spoke.ConnectAccepted(False))) =
    process.receive(spoke.updates(client), 10)

  fake_server.disconnect(client, socket)
}

pub fn channel_error_on_connect_fails_connect_test() {
  let client = start_client_with_defaults(9999)

  let _ = spoke.connect(client)

  let assert Ok(ConnectionStateChanged(spoke.ConnectFailed(_))) =
    process.receive(spoke.updates(client), 10)
}

pub fn channel_error_after_establish_fails_connect_test() {
  let server = fake_server.start_server()
  let client = start_client_with_defaults(server.port)

  spoke.connect(client)
  fake_server.reject_connection(server)

  let assert Ok(ConnectionStateChanged(spoke.ConnectFailed(_))) =
    process.receive(spoke.updates(client), 10)
}

pub fn timed_out_connect_test() {
  let server = fake_server.start_server()
  let connect_opts = spoke.ConnectOptions(default_client_id, 10, 5)
  let client =
    spoke.start(connect_opts, fake_server.default_options(server.port))
  spoke.connect(client)

  fake_server.expect_connection_established(server)

  let assert Ok(ConnectionStateChanged(spoke.ConnectFailed(_))) =
    process.receive(spoke.updates(client), 10)
}

fn connect(
  session_present: Bool,
  client_id: String,
  keep_alive: Int,
) -> #(spoke.Client, ConnectedServer, ReceivedConnectData) {
  let #(client, server) = start_client_and_server(client_id, keep_alive)
  let #(server, details) =
    fake_server.connect_client(client, server, session_present)
  #(client, server, details)
}

fn connect_with_error(
  error: packet.ConnectError,
  client_id: String,
  keep_alive: Int,
) -> #(spoke.Client, ListeningServer, spoke.ConnectError, ReceivedConnectData) {
  let #(client, server) = start_client_and_server(client_id, keep_alive)
  let #(server, error, details) =
    fake_server.connect_client_with_error(client, server, error)
  #(client, server, error, details)
}

fn start_client_and_server(
  client_id: String,
  keep_alive: Int,
) -> #(spoke.Client, ListeningServer) {
  let server = fake_server.start_server()

  let connect_opts = spoke.ConnectOptions(client_id, keep_alive, 100)
  let client =
    spoke.start(connect_opts, fake_server.default_options(server.port))

  #(client, server)
}

fn start_client_with_defaults(port: Int) -> spoke.Client {
  let connect_opts = spoke.ConnectOptions(default_client_id, 10, 100)
  spoke.start(connect_opts, fake_server.default_options(port))
}
