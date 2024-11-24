//// Encoding of fundamental MQTT data types and shared error codes

import gleam/bit_array
import gleam/bool
import gleam/bytes_tree.{type BytesTree}
import gleam/list
import spoke/internal/packet.{
  type QoS, type SubscribeRequest, type SubscribeResult, QoS0, QoS1, QoS2,
}

const protocol_level: Int = 4

pub type EncodeError {
  EmptySubscribeList
  EmptyUnsubscribeList
}

pub fn connect(client_id: String, keep_alive: Int) -> BytesTree {
  let user_name = 0
  let password = 0
  let will_retain = 0
  let will_qos = 0
  let will_flag = 0
  let clean_session = 1

  let header = <<
    string("MQTT"):bits,
    protocol_level:8,
    user_name:1,
    password:1,
    will_retain:1,
    will_qos:2,
    will_flag:1,
    clean_session:1,
    0:1,
    keep_alive:big-size(16),
  >>

  let payload =
    bytes_tree.new()
    |> bytes_tree.append(string(client_id))
  // More strings to be added here

  encode_parts(1, <<0:4>>, header, payload)
}

pub fn publish(data: packet.PublishData) -> BytesTree {
  // TODO validate dup and packet id against QoS

  let message = data.message
  let dup = bool.to_int(data.dup)
  let retain = bool.to_int(message.retain)
  let flags = <<dup:1, encode_qos(message.qos):2, retain:1>>
  // TODO packet id for QoS > 0
  let header = string(message.topic)
  let payload = bytes_tree.from_bit_array(message.payload)
  encode_parts(3, flags, header, payload)
}

pub fn subscribe(
  packet_id: Int,
  topics: List(SubscribeRequest),
) -> Result(BytesTree, EncodeError) {
  case topics {
    [] -> Error(EmptySubscribeList)
    _ -> {
      let header = <<packet_id:big-size(16)>>
      let payload = {
        use builder, topic <- list.fold(topics, bytes_tree.new())
        builder
        |> bytes_tree.append(string(topic.filter))
        |> bytes_tree.append(<<encode_qos(topic.qos):8>>)
      }

      Ok(encode_parts(8, <<2:4>>, header, payload))
    }
  }
}

pub fn suback(
  packet_id: Int,
  results: List(SubscribeResult),
) -> Result(BytesTree, EncodeError) {
  case results {
    [] -> Error(EmptySubscribeList)
    _ -> {
      let header = <<packet_id:big-size(16)>>
      let payload = {
        use builder, result <- list.fold(results, bytes_tree.new())
        builder
        |> bytes_tree.append(<<encode_suback_result(result):8>>)
      }

      Ok(encode_parts(9, <<0:4>>, header, payload))
    }
  }
}

pub fn unsubscribe(
  packet_id: Int,
  topics: List(String),
) -> Result(BytesTree, EncodeError) {
  case topics {
    [] -> Error(EmptyUnsubscribeList)
    _ -> {
      let header = <<packet_id:big-size(16)>>
      let payload = {
        use builder, topic <- list.fold(topics, bytes_tree.new())
        builder
        |> bytes_tree.append(string(topic))
      }

      Ok(encode_parts(10, <<2:4>>, header, payload))
    }
  }
}

pub fn connack(result: packet.ConnAckResult) -> BytesTree {
  let header = case result {
    Ok(True) -> <<1, 0>>
    Ok(False) -> <<0, 0>>
    Error(e) -> <<0, encode_connack_error(e):8>>
  }
  encode_parts(2, flags: <<0:4>>, header: header, payload: bytes_tree.new())
}

pub fn only_packet_type(type_id: Int) -> BytesTree {
  encode_parts(type_id, flags: <<0:4>>, header: <<>>, payload: bytes_tree.new())
}

pub fn only_packet_id(type_id: Int, flags: Int, packet_id: Int) -> BytesTree {
  encode_parts(
    type_id,
    flags: <<flags:4>>,
    header: <<packet_id:big-size(16)>>,
    payload: bytes_tree.new(),
  )
}

pub fn string(str: String) -> BitArray {
  let data = bit_array.from_string(str)
  let len = <<bit_array.byte_size(data):big-size(16)>>
  bit_array.concat([len, data])
}

pub fn varint(i: Int) -> BitArray {
  // TODO: Do we care about the max value (4 bytes)?
  <<>> |> build_varint(i)
}

fn build_varint(bits: BitArray, i: Int) -> BitArray {
  case i < 128 {
    True -> <<bits:bits, i:8>>
    False -> {
      let remainder = i % 128
      <<bits:bits, 1:1, remainder:7>> |> build_varint(i / 128)
    }
  }
}

fn encode_parts(
  id: Int,
  flags flags: BitArray,
  header header: BitArray,
  payload payload: BytesTree,
) {
  let variable_content =
    payload
    |> bytes_tree.prepend(header)
  let remaining_len = bytes_tree.byte_size(variable_content)
  let fixed_header = <<id:4, flags:bits, varint(remaining_len):bits>>
  bytes_tree.prepend(variable_content, fixed_header)
}

fn encode_qos(qos: QoS) -> Int {
  case qos {
    QoS0 -> 0
    QoS1 -> 1
    QoS2 -> 2
  }
}

fn encode_suback_result(result: SubscribeResult) -> Int {
  case result {
    Ok(qos) -> encode_qos(qos)
    Error(_) -> 0x80
  }
}

fn encode_connack_error(code: packet.ConnectError) -> Int {
  case code {
    packet.UnacceptableProtocolVersion -> 1
    packet.IdentifierRefused -> 2
    packet.ServerUnavailable -> 3
    packet.BadUsernameOrPassword -> 4
    packet.NotAuthorized -> 5
  }
}
