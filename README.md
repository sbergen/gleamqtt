# spoke

Spoke is a MQTT 3.1.1 client package very early in development,
written in Gleam.

You should probably not yet use it for anything important,
but feel free to try it out, and give feedback on anything!

Example usage:
```gleam
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/string
import spoke

pub fn main() {
  let client_id = "spoke" <> string.inspect(int.random(999_999_999))
  let topic = "spoke-test"

  let client =
    spoke.default_tcp_options("test.mosquitto.org")
    |> spoke.connect_with_id(client_id)
    |> spoke.start

  spoke.connect(client, True)

  let assert Ok(_) =
    spoke.subscribe(client, [spoke.SubscribeRequest(topic, spoke.AtLeastOnce)])

  let message =
    spoke.PublishData(
      topic,
      <<"Hello from spoke!">>,
      spoke.AtLeastOnce,
      retain: False,
    )
  spoke.publish(client, message)

  let updates = spoke.updates(client)

  let assert Ok(spoke.ConnectionStateChanged(spoke.ConnectAccepted(_))) =
    process.receive(updates, 1000)

  let message = process.receive(updates, 1000)
  io.println(string.inspect(message))

  spoke.disconnect(client)
}
```

This should print the following,
assuming `test.mosquitto.org` is up (it's not rare for it to be down):
```
Ok(ReceivedMessage("spoke-test", "Hello from spoke!", False))
```

## Development status

### Missing MQTT 3.1.1 features
- Auth
- Will
- Persistent sessions across restarts

### Transport channels
- [x] TCP
- [ ] WebSocket

### General improvements planned
- Better documentation of public parts of code
- Move TCP channel to separate package