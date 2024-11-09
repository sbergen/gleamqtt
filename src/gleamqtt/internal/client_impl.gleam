import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleamqtt.{type ConnectOptions, type SubscribeRequest, type Update}
import gleamqtt/internal/packet/incoming.{type SubscribeResult}
import gleamqtt/internal/packet/outgoing
import gleamqtt/internal/transport/channel.{type EncodedChannel}
import gleamqtt/transport.{type ChannelResult}

pub opaque type ClientImpl {
  ClientImpl(subject: Subject(ClientMsg))
}

pub fn run(
  options: ConnectOptions,
  connect: fn() -> EncodedChannel,
  updates: Subject(Update),
) -> ClientImpl {
  let state = new_state(options, connect, updates)
  let assert Ok(client) = actor.start(state, run_client)
  process.send(client, Connect)
  ClientImpl(client)
}

pub fn subscribe(client: ClientImpl, topics: List(SubscribeRequest)) -> Nil {
  // TODO: Configurable timeout
  process.call(client.subject, Subscribe(topics, _), 100)
}

type ClientState {
  ClientState(
    options: ConnectOptions,
    connect: fn() -> EncodedChannel,
    updates: Subject(Update),
    conn_state: ConnectionState,
    packet_id: Int,
    pending_subs: Dict(Int, Subject(Nil)),
  )
}

type ClientMsg {
  Connect
  Received(ChannelResult(incoming.Packet))
  Subscribe(List(SubscribeRequest), Subject(Nil))
}

type ConnectionState {
  Disconnected
  ConnectingToServer(EncodedChannel)
  Connected(EncodedChannel)
}

fn new_state(
  options: ConnectOptions,
  connect: fn() -> EncodedChannel,
  updates: Subject(Update),
) -> ClientState {
  ClientState(options, connect, updates, Disconnected, 0, dict.new())
}

fn run_client(
  msg: ClientMsg,
  state: ClientState,
) -> actor.Next(ClientMsg, ClientState) {
  case msg {
    Connect -> connect(state)
    Received(r) -> handle_receive(state, r)
    Subscribe(topics, reply_to) -> handle_subscribe(state, topics, reply_to)
  }
}

fn connect(state: ClientState) -> actor.Next(ClientMsg, ClientState) {
  let assert Disconnected = state.conn_state
  let channel = state.connect()

  let receives = process.new_subject()
  let new_selector =
    process.new_selector()
    |> process.selecting(receives, Received(_))
  channel.start_receive(receives)

  let connect_packet =
    outgoing.Connect(state.options.client_id, state.options.keep_alive)
  let assert Ok(_) = channel.send(connect_packet)

  let new_state = ClientState(..state, conn_state: ConnectingToServer(channel))
  actor.with_selector(actor.continue(new_state), new_selector)
}

fn handle_receive(
  state: ClientState,
  data: ChannelResult(incoming.Packet),
) -> actor.Next(ClientMsg, ClientState) {
  let assert Ok(packet) = data

  case packet {
    incoming.ConnAck(session_present, status) ->
      handle_connack(state, session_present, status)
    incoming.SubAck(id, results) -> handle_suback(state, id, results)
    _ -> todo as "Packet type not handled"
  }
}

fn handle_connack(
  state: ClientState,
  session_present: Bool,
  status: gleamqtt.ConnectReturnCode,
) -> actor.Next(ClientMsg, ClientState) {
  let assert ConnectingToServer(connection) = state.conn_state

  process.send(state.updates, gleamqtt.ConnectFinished(status, session_present))

  case status {
    gleamqtt.ConnectionAccepted ->
      actor.continue(ClientState(..state, conn_state: Connected(connection)))
    _ -> todo as "Should disconnect"
  }
}

fn handle_suback(
  state: ClientState,
  id: Int,
  results: List(SubscribeResult),
) -> actor.Next(ClientMsg, ClientState) {
  let subs = state.pending_subs
  let assert Ok(reply_to) = dict.get(subs, id)
  process.send(reply_to, Nil)
  actor.continue(ClientState(..state, pending_subs: dict.delete(subs, id)))
}

fn handle_subscribe(
  state: ClientState,
  topics: List(SubscribeRequest),
  reply_to: Subject(Nil),
) -> actor.Next(ClientMsg, ClientState) {
  let id = state.packet_id
  let pending_subs = state.pending_subs |> dict.insert(id, reply_to)

  let assert Ok(_) = get_channel(state).send(outgoing.Subscribe(id, topics))

  actor.continue(
    ClientState(..state, packet_id: id + 1, pending_subs: pending_subs),
  )
}

// TODO: This should do some kind of error handling
// From specs, not sure what to do with this yet:
// Clients are allowed to send further Control Packets immediately after sending a CONNECT Packet;
// Clients need not wait for a CONNACK Packet to arrive from the Server.
// If the Server rejects the CONNECT, it MUST NOT process any data sent by the Client after the CONNECT Packet
//
// Non normative comment
// Clients typically wait for a CONNACK Packet, However,
// if the Client exploits its freedom to send Control Packets before it receives a CONNACK,
// it might simplify the Client implementation as it does not have to police the connected state.
// The Client accepts that any data that it sends before it receives a CONNACK packet from the Server
// will not be processed if the Server rejects the connection.
fn get_channel(state: ClientState) {
  case state.conn_state {
    Connected(channel) -> channel
    ConnectingToServer(channel) -> channel
    Disconnected -> todo as "Not connected, handle better"
  }
}
