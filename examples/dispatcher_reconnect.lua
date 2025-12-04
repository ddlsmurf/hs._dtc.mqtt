-- MQTT Dispatcher with Auto-Reconnect Example
-- Demonstrates using the reconnector wrapper with the dispatcher module
-- This shows that reconnector works with any MQTT client type
--
-- Features demonstrated:
--   ✓ Per-topic callbacks (from dispatcher)
--   ✓ Automatic reconnection (from reconnector)
--   ✓ Wildcard subscriptions
--   ✓ All methods work transparently through wrapper
--
-- API:
--   client:reconnectStatus()        -- Get {attempts, nextDelay}
--   client:disconnect()             -- Stop reconnecting
--

local Dispatcher = require("hs._dtc.mqtt.dispatcher")
local Reconnector = require("hs._dtc.mqtt.reconnector")
local mqtt = require("hs._dtc.mqtt")

-- Create dispatcher client and wrap with reconnector
local client = Reconnector.new(Dispatcher, {
    baseDelay = 2,
    maxDelay = 30,
    backoffMultiplier = 1.5
})

-- Set up state callback for connection monitoring
client:setStateCallback(function(state)
    print(string.format("[%s] State: %s", os.date("%H:%M:%S"), state))

    if state == "connected" then
        local status = client:reconnectStatus()
        print(string.format("✓ Connected (reconnect attempts: %d)", status.attempts))
    elseif state == "error" or state == "closed" then
        local status = client:reconnectStatus()
        print(string.format("✗ Disconnected (after current delay, next retry: %ds)", status.nextDelay))
    end
end)

-- Subscribe to multiple topics with individual callbacks
-- These work transparently through both the reconnector and dispatcher wrappers
client:subscribe("home/living-room/temperature", mqtt.QoS.AtLeastOnce, function(topic, message)
    print(string.format("Living room: %s°C", message))
end)

client:subscribe("home/bedroom/temperature", mqtt.QoS.AtLeastOnce, function(topic, message)
    print(string.format("Bedroom: %s°C", message))
end)

client:subscribe("home/+/humidity", mqtt.QoS.AtMostOnce, function(topic, message)
    print(string.format("%s humidity: %s%%", topic[1], message))
end)

client:subscribe("sensors/#", mqtt.QoS.AtMostOnce, function(topic, message)
    print(string.format("Sensor data: %s = %s", topic[1], message))
end)

-- Catch-all for any other topics
client:subscribe("#", mqtt.QoS.AtMostOnce, function(topic, message)
    print(string.format("Other: [%s] %s", topic[0], message)) -- the same as [1] for "#" but hey
end)

-- Connect to broker
client:connect({
    host = "localhost",
    port = 1883,
    keepalive = 30,
    clean = true,
    clientId = "hammerspoon_dispatcher_reconnect",

    -- Presence tracking
    willTopic = "presence/hammerspoon/dispatcher",
    willMessage = "offline",
    willQoS = mqtt.QoS.AtLeastOnce,
    willRetain = true,
    onlineMessage = "online"
})

-- Test publishing after a delay
hs.timer.doAfter(2, function()
    if client:state() == "connected" then
        client:publish("home/living-room/temperature", "22.5", mqtt.QoS.AtLeastOnce)
        client:publish("home/bedroom/temperature", "20.1", mqtt.QoS.AtLeastOnce)
        client:publish("home/kitchen/humidity", "65", mqtt.QoS.AtMostOnce)
        client:publish("sensors/outdoor/wind", "12 km/h", mqtt.QoS.AtMostOnce)
        print("📤 Test messages published")
    end
end)

return client
