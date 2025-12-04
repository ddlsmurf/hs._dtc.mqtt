--- === hs._dtc.mqtt ===
---
--- MQTT client for Hammerspoon
---
--- This module provides MQTT pub/sub functionality with support for last will messages
--- and automatic online message publishing upon connection.

local USERDATA_TAG = "hs._dtc.mqtt"
local module = require(USERDATA_TAG .. ".internal")

-- Register documentation if available
local basePath = package.searchpath(USERDATA_TAG, package.path)
if basePath then
    basePath = basePath:match("^(.+)/init.lua$")
    if basePath and require("hs.fs").attributes(basePath .. "/docs.json") then
        require("hs.doc").registerJSONFile(basePath .. "/docs.json")
    end
end

-- Quality of Service levels
module.QoS = {
    AtMostOnce = 0,
    AtLeastOnce = 1,
    ExactlyOnce = 2
}

return module
