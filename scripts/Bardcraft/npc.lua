local self = require('openmw.self')
local AI = require('openmw.interfaces').AI
local nearby = require('openmw.nearby')
local util = require('openmw.util')

local Performer = require('scripts.Bardcraft.performer')
local Data = require('scripts.Bardcraft.data')

local fleeTimer = 0

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
        onUpdate = function(dt)
            if Performer.playing and self.type.getStance(self) ~= self.type.STANCE.Nothing then
                core.sendGlobalEvent('BO_StopPerformance')
            end

            fleeTimer = math.min(fleeTimer + dt, 1)
            if fleeTimer < 1 then return end
            fleeTimer = 0

            if self.type.record(self).class ~= 'r_bc_bard' or self.type.isDead(self) or not self.type.isInActorsProcessingRange(self) then
                return
            end

            local currPackage = AI.getActivePackage()
            if not currPackage or currPackage.type ~= 'Combat' then
                self.type.stats.dynamic.health(self).current = util.clamp(self.type.stats.dynamic.health(self).current + 0.1, 0, self.type.stats.dynamic.health(self).base)
            end

            if AI.isFleeing() then
                for _, actor in pairs(nearby.actors) do
                    actor:sendEvent('BC_FleeingBard', { actor = self })
                end
            end
        end,
    },
    eventHandlers = {
        BO_ConductorEvent = function(data)
            Performer.handleConductorEvent(data)
        end,
    }
}