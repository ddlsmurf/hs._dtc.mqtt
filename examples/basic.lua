-- Basic MQTT Example
-- This demonstrates connecting to an MQTT broker, subscribing to topics,
-- and publishing messages

local mqtt = require("hs._dtc.mqtt")

-- Create a new MQTT client
local client = mqtt.new()

-- Set up message callback to handle incoming messages
client:setMessageCallback(function(topic, message, retained)
    print(string.format("Received on '%s': %s %s",
                       topic,
                       message,
                       retained and "(retained)" or ""))
end)

-- Set up state callback to track connection status
client:setStateCallback(function(state)
    print("MQTT state changed to: " .. state)

    if state == "connected" then
        print("Connected! Subscribing to topics...")
        -- Subscribe to a topic once connected
        client:subscribe("test/topic", mqtt.QoS.AtLeastOnce)

        -- You can also subscribe to multiple topics at once
        client:subscribe({
            ["another/topic"] = mqtt.QoS.AtMostOnce,
            ["third/topic"] = mqtt.QoS.AtLeastOnce
        })

        -- Publish a test message
        print("Publishing test message...")
        client:publish("test/topic", "Hello from Hammerspoon!", mqtt.QoS.AtLeastOnce, false)
    end
end)

-- Connect to MQTT broker
print("Connecting to MQTT broker...")
client:connect({
    host = "localhost",
    port = 1883,
    keepalive = 60,
    clean = true
})

-- To disconnect later:
-- client:disconnect()

-- Return the client so it doesn't get garbage collected
return client
