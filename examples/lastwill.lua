-- MQTT Last Will and Online Message Example
-- This demonstrates using last will testament and automatic online messages
-- This is useful for presence detection - other clients can monitor when this
-- client goes offline unexpectedly
--
-- What's happening:
-- 1. When connected, 'online' is published to presence/hammerspoon/status
-- 2. If disconnected normally with :disconnect(), the last will is NOT sent
-- 3. If disconnected abnormally (crash, network failure), broker sends 'offline'
--
-- To test the last will, you can:
--   - Kill Hammerspoon suddenly
--   - Disconnect your network
--   - Or just call client:disconnect() (but this won't trigger last will, this must be manual for clean disconnects)
--

local mqtt = require("hs._dtc.mqtt")

-- Create a new MQTT client
local client = mqtt.new()

-- Set up message callback
client:setMessageCallback(function(topic, message, retained)
    print(string.format("[%s] %s", topic, message))
end)

-- Set up state callback
client:setStateCallback(function(state)
    print("Connection state: " .. state)

    if state == "connected" then
        print("✓ Connected and published online status")

        -- Subscribe to status topics to see other clients' status
        client:subscribe("presence/+/status", mqtt.QoS.AtLeastOnce)

        -- Publish some data
        client:publish("hammerspoon/data", "System is running", mqtt.QoS.AtLeastOnce, true)
    elseif state == "closed" or state == "error" then
        print("✗ Disconnected - last will should be published by broker")
    end
end)

-- Connect with last will and online message configuration
print("Connecting with last will and online message...")
client:connect({
    host = "localhost",
    port = 1883,
    keepalive = 30,
    clean = true,

    -- Username/password authentication (if required by your broker)
    -- username = "myuser",
    -- password = "mypassword",

    -- Last Will Testament - published by broker when we disconnect unexpectedly
    willTopic = "presence/hammerspoon/status",
    willMessage = "offline",
    willQoS = mqtt.QoS.AtLeastOnce,
    willRetain = true,

    -- Online message - automatically published when connection succeeds
    onlineTopic = "presence/hammerspoon/status",
    onlineMessage = "online"
})

-- To disconnect gracefully (last will will NOT be published):
-- client:disconnect()

-- Return the client so it doesn't get garbage collected
return client
