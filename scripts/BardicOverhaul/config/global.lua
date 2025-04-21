local async = require('openmw.async')
local storage = require('openmw.storage')

local options = storage.globalSection('Settings/BardicOverhaul/3_Options')
local configGlobal = {}

local function updateConfig()
	configGlobal.options = options:asTable()
end

updateConfig()
options:subscribe(async:callback(updateConfig))

return configGlobal