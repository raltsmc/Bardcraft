local self = require('openmw.self')
local anim = require('openmw.animation')

local Performer = require('scripts.Bardcraft.performer')
local Data = require('scripts.Bardcraft.data')

return {
    engineHandlers = {
        onSave = function()
            return Performer:onSave()
        end,
        onLoad = function(data)
            Performer:onLoad(data)
        end,
        onActive = function()
            local bardInfo = Data.BardNpcs[self.recordId]
            local startingLevel = bardInfo and bardInfo.startingLevel
            if not startingLevel then return end

            if Performer.stats.performanceSkill.level < startingLevel then
                Performer:setPerformanceLevel(startingLevel)
            end
        end,
    },
    eventHandlers = {
        BO_ConductorEvent = function(data)
            Performer.handleConductorEvent(data)
        end,
    }
}