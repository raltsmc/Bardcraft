local self = require('openmw.self')
local anim = require('openmw.animation')

local Performer = require('scripts.Bardcraft.performer')

return {
    engineHandlers = {
        onSave = function()
            return Performer:onSave()
        end,
        onLoad = function(data)
            Performer:onLoad(data)
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