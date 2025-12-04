--- === hs._dtc.mqtt.reconnector ===
---
--- Automatic reconnection wrapper for MQTT clients
---
--- This module wraps an MQTT client (either hs._dtc.mqtt or hs._dtc.mqtt.dispatcher)
--- and adds automatic reconnection with exponential backoff. It transparently
--- proxies all client methods while managing reconnection logic.
---
--- The wrapper intercepts state changes and automatically reconnects on
--- disconnection or errors with configurable retry delays.

local Reconnector = {}
Reconnector.__index = Reconnector

--- hs._dtc.mqtt.reconnector.new(client[, options]) -> reconnector
--- Constructor
--- Wraps an MQTT client with automatic reconnection capability
---
--- Parameters:
---  * clientClass - An MQTT client class (`mqtt` or `mqtt.dispatcher`)
---  * options - (table, optional) Reconnection configuration:
---    * baseDelay - (number, default: 1) Initial retry delay in seconds
---    * maxDelay - (number, default: 60) Maximum retry delay in seconds
---    * backoffMultiplier - (number, default: 2) Delay multiplier on each retry
---
--- Returns:
---  * A reconnector wrapper object that behaves like the original client
---
--- Notes:
---  * All original client methods are available through the wrapper
---  * The wrapper intercepts connect(), disconnect(), and setStateCallback()
---  * Automatically reconnects until disconnect() is called
---  * Works with both hs._dtc.mqtt and hs._dtc.mqtt.dispatcher clients
function Reconnector.new(client, options)
    options = options or {}

    local self = setmetatable({}, Reconnector)

    -- Store the underlying client
    self._client = client.new()

    -- Reconnection configuration
    self._config = {
        baseDelay = options.baseDelay or 1,
        maxDelay = options.maxDelay or 60,
        backoffMultiplier = options.backoffMultiplier or 2
    }

    -- Reconnection state
    self._state = {
        currentDelay = self._config.baseDelay,
        attempts = 0,
        timer = nil,
        connectionOpts = nil,
        userStateCallback = nil,
        intentionalDisconnect = false
    }

    return self
end

-- Internal: Schedule a reconnection attempt
function Reconnector:_scheduleReconnect()
    if self._state.intentionalDisconnect then
        return
    end

    -- Don't schedule if already scheduled
    if self._state.timer then
        return
    end

    self._state.attempts = self._state.attempts + 1
    local delay = self._state.currentDelay

    -- Create timer for delayed reconnection
    self._state.timer = hs.timer.doAfter(delay, function()
        self._state.timer = nil
        self:_doConnect()
    end)

    -- Increase delay for next retry (exponential backoff)
    self._state.currentDelay = math.min(
        self._state.currentDelay * self._config.backoffMultiplier,
        self._config.maxDelay
    )
end

-- Internal: Reset reconnection state on successful connection
function Reconnector:_resetReconnect()
    self._state.currentDelay = self._config.baseDelay
    self._state.attempts = 0

    if self._state.timer then
        self._state.timer:stop()
        self._state.timer = nil
    end
end

-- Internal: Perform connection using saved options
function Reconnector:_doConnect()
    if self._state.connectionOpts then
        self._client:connect(self._state.connectionOpts)
    end
end

-- Internal: Wrapper for state callback that handles reconnection
function Reconnector:_wrappedStateCallback(state)
    -- Call user's callback first if they set one
    if self._state.userStateCallback then
        self._state.userStateCallback(state)
    end

    -- Handle reconnection logic
    if state == "connected" then
        self:_resetReconnect()
        self._state.intentionalDisconnect = false
    elseif state == "closed" then
        -- Only handle "closed" state, not "error", since error->closed always happens
        -- This prevents scheduling multiple reconnects for the same disconnection
        if not self._state.intentionalDisconnect then
            self:_scheduleReconnect()
        end
    end
end

--- hs._dtc.mqtt.reconnector:connect(options) -> reconnector
--- Method
--- Connects to MQTT broker (overrides client connect)
---
--- Parameters:
---  * options - Connection options table (see hs._dtc.mqtt:connect())
---
--- Returns:
---  * The reconnector object for method chaining
---
--- Notes:
---  * Stores connection options for automatic reconnection
---  * Resets reconnection state
function Reconnector:connect(options)
    -- Store connection options for reconnection
    self._state.connectionOpts = options
    self._state.intentionalDisconnect = false

    -- Install our wrapped state callback if we haven't already
    if not self._state.callbackInstalled then
        self._client:setStateCallback(function(state)
            self:_wrappedStateCallback(state)
        end)
        self._state.callbackInstalled = true
    end

    -- Perform the connection
    self._client:connect(options)

    return self
end

--- hs._dtc.mqtt.reconnector:disconnect() -> reconnector
--- Method
--- Disconnects from MQTT broker without auto-reconnect
---
--- Parameters:
---  * None
---
--- Returns:
---  * The reconnector object for method chaining
---
--- Notes:
---  * Marks disconnect as intentional to prevent auto-reconnect
---  * Cancels any pending reconnection timers
function Reconnector:disconnect()
    self._state.intentionalDisconnect = true

    -- Cancel pending reconnection
    if self._state.timer then
        self._state.timer:stop()
        self._state.timer = nil
    end

    self._client:disconnect()
    return self
end

--- hs._dtc.mqtt.reconnector:setStateCallback(fn) -> reconnector
--- Method
--- Sets the user's state callback (overrides client setStateCallback)
---
--- Parameters:
---  * fn - User's state callback function or nil
---
--- Returns:
---  * The reconnector object for method chaining
---
--- Notes:
---  * The wrapper will call your callback and then handle reconnection
---  * Setting to nil removes your callback but keeps reconnection active
function Reconnector:setStateCallback(fn)
    -- Store user's callback, we'll call it from our wrapper
    self._state.userStateCallback = fn
    return self
end

--- hs._dtc.mqtt.reconnector:reconnectStatus() -> table
--- Method
--- Get current reconnection status
---
--- Parameters:
---  * None
---
--- Returns:
---  * A table with reconnection status:
---    * attempts - (number) Number of reconnection attempts since last connect
---    * nextDelay - (number) Seconds to wait before next reconnection attempt
function Reconnector:reconnectStatus()
    return {
        attempts = self._state.attempts,
        nextDelay = self._state.currentDelay
    }
end

-- Metatable magic: Proxy all other methods to underlying client
setmetatable(Reconnector, {
    __index = function(t, k)
        return function(self, ...)
            -- If the method exists on the Reconnector, it's already handled above
            -- Otherwise, proxy to the underlying client
            local method = self._client[k]
            if type(method) == "function" then
                return method(self._client, ...)
            else
                return method
            end
        end
    end
})

return Reconnector
