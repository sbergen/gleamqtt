import gleam/option.{None}
import gleeunit/should
import spoke/internal/packet.{QoS0, QoS1, QoS2}
import spoke/internal/packet/client/incoming
import spoke/internal/packet/decode.{InvalidData}
import spoke/internal/packet/encode

pub fn decode_too_short_test() {
  incoming.decode_packet(<<0:7>>)
  |> should.equal(Error(decode.DataTooShort))
}

pub fn decode_invalid_id_test() {
  incoming.decode_packet(<<0:8>>)
  |> should.equal(Error(decode.InvalidPacketIdentifier(0)))
}

pub fn connack_decode_invalid_length_test() {
  incoming.decode_packet(<<2:4, 0:4, 3:8, 0:32>>)
  |> should.equal(Error(decode.InvalidData))
}

pub fn connack_decode_too_short_test() {
  incoming.decode_packet(<<2:4, 1:4, 2:8, 0:8>>)
  |> should.equal(Error(decode.DataTooShort))
}

pub fn connack_decode_invalid_flags_test() {
  incoming.decode_packet(<<2:4, 1:4, 2:8, 0:16>>)
  |> should.equal(Error(decode.InvalidData))
}

pub fn connack_decode_invalid_return_code_test() {
  incoming.decode_packet(<<2:4, 0:4, 2:8, 0:8, 6:8>>)
  |> should.equal(Error(decode.InvalidData))
}

pub fn ping_resp_decode_test() {
  let assert Ok(#(packet, rest)) =
    incoming.decode_packet(<<13:4, 0:4, 0:8, 1:8>>)
  rest |> should.equal(<<1:8>>)
  packet |> should.equal(incoming.PingResp)
}

pub fn ping_resp_too_short_test() {
  let assert Error(decode.DataTooShort) = incoming.decode_packet(<<13:4, 0:4>>)
}

pub fn ping_resp_invalid_length_test() {
  let assert Error(decode.InvalidData) =
    incoming.decode_packet(<<13:4, 0:4, 1:8, 1:8>>)
}

pub fn publish_decode_qos0_test() {
  // topic length + topic + payload (raw)
  let len = 2 + 5 + 3
  let data = <<
    3:4,
    0:4,
    encode.varint(len):bits,
    5:big-size(16),
    "topic",
    "foo",
    42:8,
  >>

  let assert Ok(#(incoming.Publish(data), rest)) = incoming.decode_packet(data)
  rest |> should.equal(<<42:8>>)

  data.message
  |> should.equal(packet.MessageData(
    "topic",
    <<"foo">>,
    qos: QoS0,
    retain: False,
  ))

  data.dup |> should.equal(False)
  data.packet_id |> should.equal(None)
}

// TODO: Use a property based test?
pub fn publish_decode_should_be_retained_test() {
  let data = <<3:4, 1:4, encode.varint(2):bits, 0:big-size(16)>>

  let assert Ok(#(incoming.Publish(data), <<>>)) = incoming.decode_packet(data)

  data.message.retain |> should.equal(True)
}

pub fn pub_xxx_decode_invalid_test() {
  // Size is too long
  let data = <<4:4, 0:4, encode.varint(3):bits, 42:big-size(16), 1>>
  let assert Error(InvalidData) = incoming.decode_packet(data)

  // flags are invalid
  let data = <<5:4, 1:4, encode.varint(2):bits, 43:big-size(16)>>
  let assert Error(InvalidData) = incoming.decode_packet(data)
}

pub fn unsuback_decode_test() {
  let data = <<11:4, 0:4, encode.varint(2):bits, 42:big-size(16)>>
  let assert Ok(#(incoming.UnsubAck(42), <<>>)) = incoming.decode_packet(data)
}
