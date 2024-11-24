import gleam/bit_array
import gleam/bytes_tree
import gleam/option.{None}
import gleeunit/should
import spoke/internal/packet.{QoS0, QoS1, QoS2}
import spoke/internal/packet/client/outgoing
import spoke/internal/packet/decode

pub fn encode_connect_test() {
  let assert Ok(builder) =
    outgoing.encode_packet(outgoing.Connect("test-client-id", 15))

  let assert <<1:4, 0:4, rest:bits>> = bytes_tree.to_bit_array(builder)
  let rest = validate_remaining_len(rest)
  let assert Ok(#("MQTT", rest)) = decode.string(rest)

  // Protocol level
  let assert <<4:8, rest:bits>> = rest

  // Connect flags, we always just set clean session for now
  let assert <<0b10:8, rest:bits>> = rest

  // Keep-alive
  let assert <<15:big-size(16), rest:bits>> = rest

  let assert Ok(#("test-client-id", <<>>)) = decode.string(rest)
}

pub fn encode_subscribe_test() {
  let assert Ok(builder) =
    outgoing.encode_packet(
      outgoing.Subscribe(42, [
        packet.SubscribeRequest("topic0", QoS0),
        packet.SubscribeRequest("topic1", QoS1),
        packet.SubscribeRequest("topic2", QoS2),
      ]),
    )

  // flags are reserved
  let assert <<8:4, 2:4, rest:bits>> = bytes_tree.to_bit_array(builder)
  let rest = validate_remaining_len(rest)

  let assert <<42:big-size(16), rest:bits>> = rest

  let assert Ok(#("topic0", rest)) = decode.string(rest)
  let assert <<0:8, rest:bits>> = rest

  let assert Ok(#("topic1", rest)) = decode.string(rest)
  let assert <<1:8, rest:bits>> = rest

  let assert Ok(#("topic2", rest)) = decode.string(rest)
  let assert <<2:8>> = rest
}

pub fn encode_unsubscribe_test() {
  let assert Ok(bytes) =
    outgoing.encode_packet(outgoing.Unsubscribe(42, ["topic0", "topic1"]))

  let assert <<10:4, 2:4, rest:bits>> = bytes_tree.to_bit_array(bytes)
  let rest = validate_remaining_len(rest)

  let assert <<42:big-size(16), rest:bits>> = rest
  let assert Ok(#("topic0", rest)) = decode.string(rest)
  let assert Ok(#("topic1", <<>>)) = decode.string(rest)
}

pub fn encode_disconnect_test() {
  let assert Ok(builder) = outgoing.encode_packet(outgoing.Disconnect)
  let assert <<14:4, 0:4, 0:8>> = bytes_tree.to_bit_array(builder)
}

pub fn encode_ping_req_test() {
  let assert Ok(builder) = outgoing.encode_packet(outgoing.PingReq)
  let assert <<12:4, 0:4, 0:8>> = bytes_tree.to_bit_array(builder)
}

pub fn encode_publish_test() {
  let message =
    packet.MessageData("topic", <<"payload">>, qos: QoS0, retain: False)
  let data = packet.PublishData(message: message, dup: False, packet_id: None)

  let assert Ok(builder) = outgoing.encode_packet(outgoing.Publish(data))
  let assert <<3:4, 0:4, rest:bits>> = bytes_tree.to_bit_array(builder)
  let rest = validate_remaining_len(rest)
  let assert Ok(#("topic", rest)) = decode.string(rest)
  let assert <<"payload">> = rest
}

pub fn encode_pub_xxx_test() {
  let assert Ok(bytes) = outgoing.encode_packet(outgoing.PubAck(42))
  let assert <<4:4, 0:4, 2:8, 42:big-size(16)>> = bytes_tree.to_bit_array(bytes)

  let assert Ok(bytes) = outgoing.encode_packet(outgoing.PubRec(43))
  let assert <<5:4, 0:4, 2:8, 43:big-size(16)>> = bytes_tree.to_bit_array(bytes)

  let assert Ok(bytes) = outgoing.encode_packet(outgoing.PubRel(44))
  let assert <<6:4, 2:4, 2:8, 44:big-size(16)>> = bytes_tree.to_bit_array(bytes)

  let assert Ok(bytes) = outgoing.encode_packet(outgoing.PubComp(45))
  let assert <<7:4, 0:4, 2:8, 45:big-size(16)>> = bytes_tree.to_bit_array(bytes)
}

fn validate_remaining_len(bytes: BitArray) -> BitArray {
  let assert Ok(#(remaining_len, rest)) = decode.varint(bytes)
  let actual_len = bit_array.byte_size(rest)
  remaining_len |> should.equal(actual_len)

  rest
}
