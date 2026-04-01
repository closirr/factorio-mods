
Version = 0004008 -- 0.4.8

Util = require("scripts/util") util = Util
Event = require('scripts/event')
Settings = require("scripts/settings")
Informatron = require('scripts/informatron')
Jetpack = require('scripts/jetpack')
JetpackGraphicsSound = require("scripts/jetpack-graphics-sound")
require('scripts/remote-interface')

Migrate = require('scripts/migrate')

function raise_event(event_name, event_data)
  local responses = {}
  for interface_name, interface_functions in pairs(remote.interfaces) do
      if interface_functions[event_name] then
          responses[interface_name] = remote.call(interface_name, event_name, event_data)
      end
  end
  return responses
end

local function on_configuration_changed()
  Migrate.migrations()
end
Event.addListener("on_configuration_changed", on_configuration_changed, true)
