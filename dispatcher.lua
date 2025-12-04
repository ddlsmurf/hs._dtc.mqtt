--- === hs._dtc.mqtt.dispatcher ===
---
--- MQTT subscription dispatcher with per-topic callbacks
---
--- This module provides a wrapper around hs._dtc.mqtt that adds convenient per-topic
--- callback handling. Instead of a single global message callback, you can
--- subscribe with individual callbacks for each topic pattern.
---
--- Messages are dispatched to the first matching subscription in registration order.
---

local mqtt = require("hs._dtc.mqtt")

-- Helper function to convert MQTT topic pattern to Lua pattern
local function mqttPatternToLuaPattern(mqttTopic)
    -- Escape Lua pattern special characters except our wildcards
    local pattern = mqttTopic:gsub("([%^%$%(%)%%%.%[%]%*%-%?])", "%%%1")

    local patternBeforeWildcards = pattern

    -- Convert MQTT wildcards to Lua patterns
    pattern = pattern:gsub("%+", "([^/]+)")  -- + matches single level (no slashes)
    pattern = pattern:gsub("#", "(.*)")      -- # matches multiple levels (anything)

    -- Ensure full match
    return "^" .. pattern .. "$", patternBeforeWildcards ~= pattern
end

-- Create wrapper class
local MQTTClientWrapper = {}
MQTTClientWrapper.__index = MQTTClientWrapper

--- hs._dtc.mqtt.dispatcher.new() -> dispatcher
--- Constructor
--- Creates a new MQTT subscription dispatcher
---
--- Parameters:
---  * None
---
--- Returns:
---  * A new dispatcher object that wraps an MQTT client
---
--- Notes:
---  * The dispatcher maintains an ordered list of subscriptions with callbacks
---  * Messages are dispatched to the first matching subscription only
---  * All original hs._dtc.mqtt client methods are available
function MQTTClientWrapper.new()
    local self = setmetatable({}, MQTTClientWrapper)
    self.client = mqtt.new()
    self.subscriptions = {}  -- Ordered list: {pattern=string, luaPattern=string, hasWildcards=bool, qos=number, callback=function}

    -- Set up internal message callback to dispatch to subscriptions
    self.client:setMessageCallback(function(topic, message, retained)
        self:_dispatchMessage(topic, message, retained)
    end)

    return self
end

-- Internal message dispatcher
function MQTTClientWrapper:_dispatchMessage(topic, message, retained)
    for _, sub in ipairs(self.subscriptions) do
        local matches = { topic:match(sub.luaPattern) }
        if #matches > 0 then
            local fields = sub.hasWildcards and matches or {}
            fields[0] = topic
            local success, result = pcall(sub.callback, fields, message, retained)
            if not success then
                print(string.format("Error in MQTT callback for '%s': %s", sub.pattern, result))
            elseif result ~= "pass" then
                return  -- Stop unless callback returned "pass"
            end
        end
    end

    print(string.format("Warning: Received message on '%s' with no matching subscription or all returned pass", topic))
end

--- hs._dtc.mqtt.dispatcher:subscribe(topic[, qos], callback) -> dispatcher
--- Method
--- Subscribes to a topic with a callback function
---
--- Parameters:
---  * topic - (string) The MQTT topic pattern to subscribe to
---  * qos - (number, optional) Quality of Service level 0-2 (default: 0)
---  * callback - (function) Function to call when messages arrive on this topic
---    * The callback receives: function(topic, message, retained)
---      * topic - (string) The actual topic the message was published to
---      * message - (string) The message payload
---      * retained - (boolean) Whether this is a retained message
---    * Return "pass" from callback to continue matching to next subscription
---
--- Returns:
---  * The dispatcher object for method chaining
---
--- Notes:
---  * MQTT wildcards are supported: + for single level, # for multi-level
---  * Subscriptions are evaluated in order - first match stops dispatching
---  * Unless callback returns the string "pass", then matching continues
---  * Register more specific patterns before broader ones
---  * If qos is omitted, it defaults to 0 (AtMostOnce)
---  * Callback errors are caught and logged, but don't stop message processing
function MQTTClientWrapper:subscribe(topic, qos, callback)
    -- Handle optional qos parameter: subscribe(topic, callback)
    if type(qos) == "function" then
        callback = qos
        qos = mqtt.QoS.AtMostOnce
    end

    -- Convert MQTT pattern to Lua pattern once and cache it
    local luaPattern, hasWildcards = mqttPatternToLuaPattern(topic)

    -- Add to our subscription list (order matters!)
    table.insert(self.subscriptions, {
        pattern = topic,
        luaPattern = luaPattern,
        hasWildcards = hasWildcards,
        qos = qos,
        callback = callback
    })

    -- Subscribe on the actual client
    self.client:subscribe(topic, qos)

    return self
end

--- hs._dtc.mqtt.dispatcher:unsubscribe(topic) -> dispatcher
--- Method
--- Unsubscribes from a topic and removes its callback
---
--- Parameters:
---  * topic - (string) The topic pattern to unsubscribe from
---
--- Returns:
---  * The dispatcher object for method chaining
---
--- Notes:
---  * Removes the subscription from both the dispatcher and the underlying client
---  * Must match the exact topic string used in subscribe()
function MQTTClientWrapper:unsubscribe(topic)
    -- Remove from our subscription list
    for i = #self.subscriptions, 1, -1 do
        if self.subscriptions[i].pattern == topic then
            table.remove(self.subscriptions, i)
        end
    end

    -- Unsubscribe on the actual client
    self.client:unsubscribe(topic)

    return self
end

--- hs._dtc.mqtt.dispatcher:connect(options) -> dispatcher
--- Method
--- Connects to an MQTT broker (pass-through to underlying client)
---
--- Parameters:
---  * options - A table of connection options (see hs._dtc.mqtt:connect())
---
--- Returns:
---  * The dispatcher object for method chaining
---
--- Notes:
---  * See hs._dtc.mqtt:connect() for full list of connection options
function MQTTClientWrapper:connect(options)
    self.client:connect(options)
    return self
end

--- hs._dtc.mqtt.dispatcher:disconnect() -> dispatcher
--- Method
--- Disconnects from the MQTT broker (pass-through to underlying client)
---
--- Parameters:
---  * None
---
--- Returns:
---  * The dispatcher object for method chaining
function MQTTClientWrapper:disconnect()
    self.client:disconnect()
    return self
end

--- hs._dtc.mqtt.dispatcher:publish(topic, message[, qos[, retain]]) -> msgid
--- Method
--- Publishes a message to a topic (pass-through to underlying client)
---
--- Parameters:
---  * topic - (string) The topic to publish to
---  * message - (string) The message payload
---  * qos - (number, optional) Quality of Service level 0-2 (default: 0)
---  * retain - (boolean, optional) Retain flag (default: false)
---
--- Returns:
---  * Message ID (0 for QoS 0, non-zero for QoS 1 or 2)
function MQTTClientWrapper:publish(topic, message, qos, retain)
    return self.client:publish(topic, message, qos, retain)
end

--- hs._dtc.mqtt.dispatcher:setStateCallback(fn) -> dispatcher
--- Method
--- Sets the connection state callback (pass-through to underlying client)
---
--- Parameters:
---  * fn - A function to call when connection state changes
---    * The callback receives: function(state)
---      * state - (string) One of: "starting", "connecting", "connected", "error", "closing", "closed"
---
--- Returns:
---  * The dispatcher object for method chaining
function MQTTClientWrapper:setStateCallback(fn)
    self.client:setStateCallback(fn)
    return self
end

--- hs._dtc.mqtt.dispatcher:state() -> string
--- Method
--- Returns the current connection state (pass-through to underlying client)
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string representing the current state
function MQTTClientWrapper:state()
    return self.client:state()
end

-- Return wrapper constructor
return MQTTClientWrapper
