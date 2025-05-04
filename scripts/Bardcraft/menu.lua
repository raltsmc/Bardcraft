local core = require('openmw.core')

return {
    engineHandlers = {
        onInit = function()
            core.sendGlobalEvent('BC_ParseMidis')
        end,
        onLoad = function()
            core.sendGlobalEvent('BC_ParseMidis')
        end,
    }
}