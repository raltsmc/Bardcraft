local self = require('openmw.self')
local anim = require('openmw.animation')

local Performer = require('scripts.BardicOverhaul.performer')

return {
    engineHandlers = {
        onLoad = function()
            anim.removeAllVfx(self)
        end,
    },
    eventHandlers = {
        BO_Perform = function(data)
            Performer.handlePerformEvent(data)
        end
    }
}