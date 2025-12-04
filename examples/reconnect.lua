-- MQTT Auto-Reconnect Example
--
-- The client uses hs._dtc.mqtt.reconnector for automatic reconnection
-- The reconnector wraps any MQTT client and adds automatic reconnection
--
-- Configuration:
--   Base delay: 1s
--   Max delay: 60s
--   Backoff multiplier: 2x
--
-- Retry schedule:
--   Attempt 1: 1s delay
--   Attempt 2: 2s delay
--   Attempt 3: 4s delay
--   Attempt 4: 8s delay
--   ...
--   Max: 60s delay
--
-- Behavior:
--   - Automatically reconnects on any disconnection/error
--   - Stops reconnecting when you call client:disconnect()
--   - Resets retry delay on successful connection
--
-- To test reconnection:
--   - Stop your MQTT broker and watch it retry with backoff
--   - Restart broker and see it reconnect automatically
--   - Disconnect network and reconnect
--
-- API:
--   client:reconnectStatus()  -- Get {attempts, nextDelay}
--   client:disconnect()       -- Stop reconnecting
--

local mqtt = require("hs._dtc.mqtt")
local Reconnector = require("hs._dtc.mqtt.reconnector")

-- Create MQTT client and wrap with reconnector
local client = Reconnector.new(mqtt, {
    baseDelay = 1,            -- Initial retry delay in seconds
    maxDelay = 60,            -- Maximum retry delay in seconds
    backoffMultiplier = 2     -- Multiply delay by this on each retry
})

-- Set up message callback (works transparently through wrapper)
client:setMessageCallback(function(topic, message, retained)
    print(string.format("[%s] Message on '%s': %s %s",
          os.date("%H:%M:%S"),
          topic,
          message,
          retained and "(retained)" or ""))
end)

-- Set up state callback
client:setStateCallback(function(state)
    print(string.format("[%s] State changed: %s", os.date("%H:%M:%S"), state))

    if state == "connected" then
        local status = client:reconnectStatus()
        print(string.format("✓ Connected successfully (attempt #%d)", status.attempts))

        -- Subscribe to topics
        client:subscribe("test/#", mqtt.QoS.AtLeastOnce)
        client:subscribe("system/+/status", mqtt.QoS.AtMostOnce)

        -- Publish test message
        client:publish("test/reconnect", "Hello from auto-reconnect", mqtt.QoS.AtLeastOnce)

    elseif state == "error" then
        local status = client:reconnectStatus()
        print(string.format("✗ Connection error (delay after current will be %fs)", status.nextDelay))

    elseif state == "closed" then
        print("✗ Connection closed (will auto-reconnect)")
    end
end)

-- Connect to broker
client:connect({
    host = "localhost",
    port = 1883,
    keepalive = 30,
    clean = true,

    -- Last will for presence
    willTopic = "presence/hammerspoon/status",
    willMessage = "offline",
    willQoS = mqtt.QoS.AtLeastOnce,
    willRetain = true,

    -- Auto-online message
    onlineMessage = "online"
})

-- Return client for interactive control
return client
