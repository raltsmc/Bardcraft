local input = require('openmw.input')
local core = require('openmw.core')
local anim = require('openmw.animation')
local self = require('openmw.self')
local I = require('openmw.interfaces')
local camera = require('openmw.camera')

local Performer = require('scripts.BardicOverhaul.performer')



return {
    engineHandlers = {
        onLoad = function()
            anim.removeAllVfx(self)
        end,
        onUpdate = function(dt)
            -- Uncomment this once first-person animations are working
            --[[if Performer.playing then
                local reset = false
                if camera.getQueuedMode() == camera.MODE.FirstPerson then
                    camera.setMode(camera.MODE.FirstPerson, true)
                    reset = true
                elseif camera.getQueuedMode() == camera.MODE.ThirdPerson then
                    camera.setMode(camera.MODE.ThirdPerson, true)
                    reset = true
                end
                if reset then
                    print('resetting anim')
                    Performer.resetVfx()
                    Performer.resetAnim()
                end
            end]]
            Performer.handleMovement(dt)
        end,
        onKeyPress = function(e)
            if e.symbol == 'k' then
                core.sendGlobalEvent('Bardic_StartPerformance')
            end
        end,
    },
    eventHandlers = {
        BO_Perform = function(data)
            Performer.handlePerformEvent(data)
        end
    }
}