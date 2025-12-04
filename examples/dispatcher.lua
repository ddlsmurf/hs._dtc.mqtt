-- Example: Using the MQTT Subscription Dispatcher with Per-Topic Callbacks
-- This demonstrates the convenient subscribe-with-callback pattern
--
-- Key Features Demonstrated:
-- 1. Per-topic callbacks - each subscribe() call has its own handler
-- 2. First-match wins - messages dispatched to first matching subscription
-- 3. Wildcard support - both + (single level) and # (multi-level)
-- 4. Subscription order matters - more specific patterns should come first
-- 5. Original API available - all client methods still work
--
-- To disconnect: client:disconnect()
--

local MQTTClient = require("hs._dtc.mqtt.dispatcher")
local mqtt = require("hs._dtc.mqtt")

-- Create a new wrapped client
local client = MQTTClient.new()

-- Set up state callback
client:setStateCallback(function(state)
    print(string.format("Connection state: %s", state))

    if state == "connected" then
        print("✓ Connected! Setting up subscriptions...")
        print("")

        -- Example 1: Subscribe with inline callback
        -- This receives messages from home/living-room/temperature
        client:subscribe("home/living-room/temperature", mqtt.QoS.AtLeastOnce, function(topic, message, retained)
            print(string.format("[Living Room] Temperature: %s°C %s",
                message,
                retained and "(retained)" or ""))
        end)

        -- Example 2: Subscribe with different QoS and callback
        -- This receives messages from home/bedroom/temperature
        client:subscribe("home/bedroom/temperature", mqtt.QoS.AtLeastOnce, function(topic, message, retained)
            print(string.format("[Bedroom] Temperature: %s°C", message))
        end)

        -- Example 3: Wildcard subscription - single level
        -- Matches: home/+/humidity
        -- Will match: home/kitchen/humidity, home/bathroom/humidity
        -- Won't match: home/kitchen/sensor/humidity (too many levels)
        client:subscribe("home/+/humidity", mqtt.QoS.AtMostOnce, function(topic, message)
            local room = topic[1]
            print(string.format("[%s] Humidity: %s%%", room:gsub("^%l", string.upper), message))
        end)

        -- Example 4: Wildcard subscription - multi level
        -- Matches: sensors/# (everything under sensors/)
        -- This is MORE SPECIFIC than the next one, so it takes precedence
        client:subscribe("sensors/outdoor/#", mqtt.QoS.AtMostOnce, function(topic, message)
            print(string.format("[Outdoor Sensor] %s = %s", topic[1], message))
        end)

        -- Example 5: Broader wildcard subscription
        -- Matches: sensors/# (everything under sensors/)
        -- Since this is registered AFTER sensors/outdoor/#, outdoor messages go there first
        client:subscribe("sensors/#", mqtt.QoS.AtMostOnce, function(topic, message)
            print(string.format("[Indoor Sensor] %s = %s", topic[1], message))
        end)

        -- Example 6: Catch-all subscription
        -- This will only receive messages that didn't match any previous subscription
        client:subscribe("#", mqtt.QoS.AtMostOnce, function(topic, message)
            print(string.format("[Other] %s: %s", topic[0], message))
        end)

        print("")
        print("Subscriptions active. Publishing test messages...")
        print("")

        -- Publish some test messages after a short delay
        hs.timer.doAfter(1, function()
            client:publish("home/living-room/temperature", "22.5", mqtt.QoS.AtLeastOnce, false)
            client:publish("home/bedroom/temperature", "20.1", mqtt.QoS.AtLeastOnce, false)
            client:publish("home/kitchen/humidity", "65", mqtt.QoS.AtMostOnce, false)
            client:publish("home/bathroom/humidity", "72", mqtt.QoS.AtMostOnce, false)

            -- These demonstrate the subscription order priority
            client:publish("sensors/outdoor/temp", "15.2", mqtt.QoS.AtMostOnce, false)
            client:publish("sensors/outdoor/wind", "12 km/h", mqtt.QoS.AtMostOnce, false)
            client:publish("sensors/indoor/co2", "450 ppm", mqtt.QoS.AtMostOnce, false)

            -- This will match the catch-all
            client:publish("system/status", "online", mqtt.QoS.AtMostOnce, false)

            print("")
            print("Test messages published!")
        end)
    end
end)

-- Connect to broker
print("Connecting to MQTT broker...")
client:connect({
    host = "localhost",
    port = 1883,
    keepalive = 60,
    clean = true,
    clientId = "hammerspoon_wrapper_demo",

    -- Last will
    willTopic = "presence/hammerspoon/status",
    willMessage = "offline",
    willRetain = true,

    -- Online message
    onlineTopic = "presence/hammerspoon/status",
    onlineMessage = "online"
})

-- Return the client so it doesn't get garbage collected
return client
