local input = require('openmw.input')
local core = require('openmw.core')
local anim = require('openmw.animation')
local self = require('openmw.self')
local I = require('openmw.interfaces')
local camera = require('openmw.camera')
local ui = require('openmw.ui')
local ambient = require('openmw.ambient')

local l10n = core.l10n('Bardcraft')

local Performer = require('scripts.Bardcraft.performer')
local Editor = require('scripts.Bardcraft.editor')
local Song = require('scripts.Bardcraft.util.song')

local performance = {
    level = 0,
    xp = 0,
}

local function onPerformanceMilestone()
    local level = performance.level
    local message
    if level < 100 then
        message = l10n('UI_LvlUp_Performance_' .. level / 10)
    else
        local roll = math.random() * 100
        if roll < 80 then
            message = l10n('UI_LvlUp_Performance_10')
        elseif roll < 99 then
            message = l10n('UI_LvlUp_Performance_10_Rare' .. math.random(1, 5))
        else
            message = l10n('UI_LvlUp_Performance_10_UltraRare')
        end
    end
    ui.showMessage(message)
    ambient.playSoundFile('sound\\Bardcraft\\lvl_up1.wav')
end

local function getPerformanceXPRequired()
    return (performance.level + 1) * 0.25
end

local function getPerformanceProgress()
    return performance.xp / getPerformanceXPRequired()
end

local function addPerformanceXP(xp)
    if performance.level >= 100 then return end
    performance.xp = performance.xp + xp
    print("New performance XP: " .. performance.xp)
    local leveledUp = false
    while getPerformanceProgress() >= 1 do
        leveledUp = true
        performance.xp = performance.xp - getPerformanceXPRequired()
        performance.level = performance.level + 1
        if performance.level % 10 == 0 then
            onPerformanceMilestone()
        end
    end
    if leveledUp then
        ui.showMessage(l10n('UI_LvlUp_Performance'):gsub('%%{level}', performance.level))
        ambient.playSoundFile('Sound\\Fx\\inter\\levelUP.wav')
    end
end

return {
    engineHandlers = {
        onInit = function()
            Editor:init()
        end,
        onLoad = function(data)
            if data and data.BO_PerformanceStat then
                performance = data.BO_PerformanceStat
            end
            anim.removeAllVfx(self)
            Editor:init()
        end,
        onSave = function()
            return { BO_PerformanceStat = performance}
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
                Editor:onToggle()
            elseif e.symbol == 'n' then
                addPerformanceXP(10) -- debug
            elseif Editor.active and e.code == input.KEY.Space then
                Editor:togglePlayback(input.isCtrlPressed())
            end
        end,
        onMouseWheel = function(v, h)
            Editor:onMouseWheel(v, h)
        end,
        onFrame = function()
            Editor:onFrame(self)
        end,
    },
    eventHandlers = {
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