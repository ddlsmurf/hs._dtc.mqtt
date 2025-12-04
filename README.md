# hs._dtc.mqtt - MQTT Client for Hammerspoon

A concise MQTT client extension for [Hammerspoon](https://www.hammerspoon.org/), based on [MQTT-Client-Framework](https://github.com/novastone-media/MQTT-Client-Framework).

## Features

- Usual MQTT stuff
- Handles presence publication using LWT, automatic online and offline (same as LWT) publications even on clean disconnects by default.

## Installation

0. Download [the latest release here](https://github.com/ddlsmurf/hs._dtc.mqtt/releases/latest).
1. Extract the downloaded archive
2. Copy the `hs/_dtc/mqtt` directory to `~/.hammerspoon/hs/_dtc/mqtt` (create folders as required)
3. Reload your Hammerspoon configuration or restart Hammerspoon

## Uninstallation

Just delete `~/.hammerspoon/hs/_dtc/mqtt`.

## Quick Start

```lua
local mqtt = require("hs._dtc.mqtt")

-- Create client
local client = mqtt.new()

-- Handle incoming messages
client:setMessageCallback(function(topic, message, retained)
    print("Received:", topic, message)
end)

-- Handle connection state changes
client:setStateCallback(function(state)
    if state == "connected" then
        -- Subscribe to topics
        client:subscribe("home/temperature", mqtt.QoS.AtLeastOnce)

        -- Publish a message
        client:publish("home/status", "online", mqtt.QoS.AtLeastOnce, true)
    end
end)

-- Connect to broker
client:connect({
    host = "localhost",
    port = 1883,
    keepalive = 60,
    clean = true
})
```

## API Reference

Up to date reference in the console: `help.hs._dtc.mqtt`

### Module Functions

#### `mqtt.new()`
Create a new MQTT client instance.

Returns: MQTT client object

**Note**: The client ID is specified in the `connect()` options. If not provided there, a random one will be generated.

### Client Methods

#### `client:connect(options)`
Connect to an MQTT broker.

Options table fields:
- `host` (string, default: "localhost"): Broker hostname or IP address
- `port` (number, default: 1883): Broker port
- `tls` (boolean, default: false): Use TLS/SSL encryption
- `keepalive` (number, default: 60): Keep-alive interval in seconds
- `clean` (boolean, default: true): Clean session flag
- `username` (string, optional): Authentication username
- `password` (string, optional): Authentication password
- `clientId` (string, optional): Client identifier
- `willTopic` (string, optional): Last will topic
- `willMessage` (string, optional): Last will message payload
- `willQoS` (number, default: 0): Last will QoS level (0-2)
- `willRetain` (boolean, default: false): Last will retain flag
- `publishWillOnDisconnect` (boolean, default: true): Publish will message on clean disconnect
- `onlineTopic` (string, optional): Topic for automatic online message (defaults to willTopic if onlineMessage is set)
- `onlineMessage` (string, optional): Payload for automatic online message
- `onlineQoS` (number, optional): QoS for online message (defaults to willQoS if onlineMessage is set)
- `onlineRetain` (boolean, optional): Retain flag for online message (defaults to willRetain if onlineMessage is set)

Returns: self (for method chaining)

#### `client:disconnect()`
Disconnect from the broker gracefully.

**Note**: By default, this will publish the last will message before disconnecting (if configured). Set `publishWillOnDisconnect=false` in connect options to disable this behavior.

Returns: self

#### `client:publish(topic, message, qos, retain)`
Publish a message to a topic.

- `topic` (string): Topic to publish to
- `message` (string): Message payload
- `qos` (number, default: 0): Quality of Service level (0-2)
- `retain` (boolean, default: false): Retain flag

Returns: Message ID (0 for QoS 0)

#### `client:subscribe(topics, qos)`
Subscribe to one or more topics.

**Single topic**:
```lua
client:subscribe("home/temperature", mqtt.QoS.AtLeastOnce)
```

**Multiple topics**:
```lua
client:subscribe({
    ["home/temperature"] = mqtt.QoS.AtLeastOnce,
    ["home/humidity"] = mqtt.QoS.AtMostOnce
})
```

Returns: self

#### `client:unsubscribe(topics)`
Unsubscribe from one or more topics.

**Single topic**:
```lua
client:unsubscribe("home/temperature")
```

**Multiple topics**:
```lua
client:unsubscribe({"home/temperature", "home/humidity"})
```

Returns: self

#### `client:setMessageCallback(function)`
Set callback for received messages.

Callback signature: `function(topic, message, retained)`
- `topic` (string): Topic the message was received on
- `message` (string): Message payload as string
- `retained` (boolean): Whether this is a retained message

#### `client:setStateCallback(function)`
Set callback for connection state changes.

Callback signature: `function(state)`
- `state` (string): One of: "starting", "connecting", "connected", "error", "closing", "closed"

#### `client:state()`
Get current connection state.

Returns: state string

### QoS Constants

- `mqtt.QoS.AtMostOnce` (0): Fire and forget
- `mqtt.QoS.AtLeastOnce` (1): Acknowledged delivery
- `mqtt.QoS.ExactlyOnce` (2): Assured single delivery

## Examples

See the included example files:
- `examples/basic.lua` - Basic pub/sub operations
- `examples/lastwill.lua` - Last will testament and online messages
- `examples/reconnect.lua` - Automatic reconnection with exponential backoff
- `examples/dispatcher_reconnect.lua` - Combining dispatcher and reconnector
- `examples/dispatcher.lua` - Using the subscription dispatcher

### Automatic Reconnection

The module includes `hs._dtc.mqtt.reconnector`, which wraps any MQTT client to add automatic reconnection with exponential backoff:

```lua
local mqtt = require("hs._dtc.mqtt")
local Reconnector = require("hs._dtc.mqtt.reconnector")

-- Wrap client with reconnector
local rawClient = mqtt.new()
local client = Reconnector.new(rawClient, {
    baseDelay = 1,            -- Initial retry delay (seconds)
    maxDelay = 60,            -- Maximum retry delay (seconds)
    backoffMultiplier = 2     -- Delay multiplier per retry
})

-- Use client normally - reconnection is automatic
client:connect({host = "localhost"})
client:subscribe("test/#", mqtt.QoS.AtLeastOnce)

-- Calling disconnect() stops automatic reconnection
client:disconnect()

-- Check reconnection status
local status = client:reconnectStatus()
-- Returns: {attempts = N, nextDelay = seconds}
```

**Features:**
- Works with both `hs._dtc.mqtt` and `hs._dtc.mqtt.dispatcher`
- Exponential backoff prevents overwhelming the broker
- Transparent wrapper - all client methods work normally

### Subscription Dispatcher

The module includes `hs._dtc.mqtt.dispatcher`, a subscription dispatcher that allows you to subscribe with per-topic callbacks:

```lua
local MQTTClient = require("hs._dtc.mqtt.dispatcher")
local mqtt = require("hs._dtc.mqtt")
local client = MQTTClient.new()

-- Subscribe with inline callbacks
client:subscribe("home/temperature", mqtt.QoS.AtLeastOnce, function(topic, message, retained)
    print("Temperature: " .. message)
    -- return "pass" -- continue testing the following subscriptions
end)

client:subscribe("home/+/humidity", function(topic, message)
    print("Humidity: " .. message)
end)

client:connect({host = "localhost"})
```

**Features:**
- Per-topic callbacks instead of global message handler
- First-match-wins dispatching (subscription order matters)
- All original client methods still available

### Combining Modules

You can combine reconnector and dispatcher:

```lua
local Dispatcher = require("hs._dtc.mqtt.dispatcher")
local Reconnector = require("hs._dtc.mqtt.reconnector")

local rawClient = Dispatcher.new()
local client = Reconnector.new(rawClient, {baseDelay = 2})

-- Now you have both per-topic callbacks AND auto-reconnect!
client:subscribe("home/+/temp", mqtt.QoS.AtLeastOnce, function(topic, msg)
    print("Temperature: " .. msg)
end)

client:connect({host = "localhost"})
```

## Building from Source

### Requirements

- Hammerspoon installed in `/Applications` (or set `HS_APPLICATION` environment
  variable - spaces in the path are not supported)
- macOS 10.13 or later
- Xcode Command Line Tools

### Compilation

```bash
make clean
make docs # Optional. Requires the `hs` cli
make all

# Install to ~/.hammerspoon
make install

# Or install to custom location
PREFIX=/custom/path make install

# Remove:
#[PREFIX=/custom/path] make uninstall
```

## License

This module bridges to MQTT-Client-Framework which is licensed under EPLv1.
See the `deps/MQTT-Client-Framework` directory for details.

Otherwise consider this MIT license.

## Credits

Built with:
- [MQTT-Client-Framework](https://github.com/novastone-media/MQTT-Client-Framework) - Objective-C MQTT client
- [Hammerspoon](https://www.hammerspoon.org/) - macOS automation framework
