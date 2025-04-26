local input = require('openmw.input')
local core = require('openmw.core')
local anim = require('openmw.animation')
local self = require('openmw.self')
local I = require('openmw.interfaces')
local camera = require('openmw.camera')

local Performer = require('scripts.BardicOverhaul.performer')
local Editor = require('scripts.BardicOverhaul.editor')
local Song = require('scripts.BardicOverhaul.util.song')

return {
    engineHandlers = {
        onInit = function()
            Editor:init()
        end,
        onLoad = function()
            anim.removeAllVfx(self)
            Editor:init()
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
            if e.symbol == 'k' and Editor.song then
                core.sendGlobalEvent('BO_StartPerformance', { song = Editor.song })
            elseif e.symbol == ';' then
                Editor:onToggle()
            elseif Editor.active and e.code == input.KEY.Space then
                Editor:togglePlayback()
            end
        end,
        onMouseWheel = function(v)
            Editor:onMouseWheel(v)
        end,
        onFrame = function()
            Editor:onFrame(self)
        end,
    },
    eventHandlers = {
        BO_Perform = function(data)
            Performer.handlePerformEvent(data)
        end,
        BO_ConductorEvent = function(data)
            Performer.handleConductorEvent(data)
        end,
        UiModeChanged = function(data)
            if data.newMode == nil then
                Editor:onUINil()
            end
        end,
    }
}