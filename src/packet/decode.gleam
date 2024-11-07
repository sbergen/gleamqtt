import gleam/bit_array
import gleam/result
import packet/errors.{type DecodeError}

pub fn string(bits: BitArray) -> Result(#(String, BitArray), DecodeError) {
  case bits {
    <<len:big-size(16), bytes:bytes-size(len), rest:bits>> -> {
      use str <- result.try(
        bit_array.to_string(bytes)
        |> result.map_error(fn(_) { errors.InvalidUTF8 }),
      )
      Ok(#(str, rest))
    }
    _ -> Error(errors.InvalidStringLength)
  }
}

/// Standard MQTT big-endian 16-bit int
pub fn integer(bits: BitArray) -> Result(#(Int, BitArray), DecodeError) {
  case bits {
    <<val:big-size(16), rest:bytes>> -> Ok(#(val, rest))
    _ -> Error(errors.DataTooShort)
  }
}

pub fn varint(bytes: BitArray) -> Result(#(Int, BitArray), DecodeError) {
  accumulate_varint(0, 1, bytes)
}

fn accumulate_varint(
  value: Int,
  multiplier: Int,
  bytes: BitArray,
) -> Result(#(Int, BitArray), DecodeError) {
  case multiplier, bytes {
    268_435_456, _ -> Error(errors.InvalidVarint)
    _, <<continue:1, next:7, rest:bits>> -> {
      let value = value + multiplier * next
      case continue {
        0 -> Ok(#(value, rest))
        _ -> accumulate_varint(value, 128 * multiplier, rest)
      }
    }
    _, _ -> Error(errors.InvalidVarint)
  }
}
