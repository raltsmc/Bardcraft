local self = require('openmw.self')
local anim = require('openmw.animation')

local Performer = require('scripts.Bardcraft.performer')

return {
    engineHandlers = {
        onLoad = function()
            anim.removeAllVfx(self)
        end,
        onUpdate = function(dt)
            Performer.handleMovement(dt)
            if Performer.playing then
                self.enableAI(self, false)
            end
        end,
    },
    eventHandlers = {
        BO_ConductorEvent = function(data)
            Performer.handleConductorEvent(data)
        end,
    }
}