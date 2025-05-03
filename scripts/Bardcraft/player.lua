local input = require('openmw.input')
local core = require('openmw.core')
local anim = require('openmw.animation')
local self = require('openmw.self')
local I = require('openmw.interfaces')
local camera = require('openmw.camera')
local ui = require('openmw.ui')
local auxUi = require('openmw_aux.ui')
local ambient = require('openmw.ambient')
local nearby = require('openmw.nearby')
local util = require('openmw.util')
local storage = require('openmw.storage')

local l10n = core.l10n('Bardcraft')

local Performer = require('scripts.Bardcraft.performer')
local Editor = require('scripts.Bardcraft.editor')
local Song = require('scripts.Bardcraft.util.song').Song

local function populateKnownSongs()
    -- Check the stored preset songs; if any are set to startUnlocked but are missing from knownSongs, add them
    local bardData = storage.playerSection('Bardcraft')
    local storedSongs = bardData:getCopy('songs/preset') or {}
    for _, song in pairs(storedSongs) do
        if song.startUnlocked and not Performer.knownSongs[song.id] then
            Performer:addKnownSong(song)
        end
    end

    print("Known songs:")
    for songName, _ in pairs(Performer.knownSongs) do
        print(songName)
    end
end

local performersInfo = {}

local performancePart = 1
local queuedMilestone = nil
local practiceSong = nil

local practiceOverlayNoteMap = {}
local practiceOverlayNoteIdToIndex = {}
local practiceOverlay = nil
local practiceOverlayNotesWrapper = nil
local practiceOverlayNoteFlashTimes = {}
local practiceOverlayNoteSuccess = {}
local practiceOverlayNoteFadeTimes = {}
local practiceOverlayNoteFadeAlphaStart = {}

local practiceOverlayTargetOpacity = 0.8
local practiceOverlayFadeInTimer = 0
local practiceOverlayFadeInDuration = 0.3
local practiceOverlayScaleX = 8 -- Every 8 ticks is 1 pixel
local practiceOverlayScaleY = 0
local practiceOverlayWidthTicks = 0
local practiceOverlayTick = 0
local practiceOverlayNoteBounds = {129, 0}

local hurtOverlay = ui.create {
    layer = 'Notification',
    type = ui.TYPE.Image,
    props = {
        resource = ui.texture { path = 'textures/bardcraft/overlay_hurt.dds' },
        relativeSize = util.vector2(1, 1),
        alpha = 0,
    },
}
local hurtAlpha = 0

local function getPracticeNoteMap()
    if not practiceSong then return {} end
    local baseNoteMap = practiceSong:noteEventsToNoteMap(practiceSong.notes)
    local noteMap = {}
    practiceOverlayNoteBounds = {129, 0}
    for i, data in pairs(baseNoteMap) do
        if data.part == performancePart then
            table.insert(noteMap, {
                note = data.note,
                time = data.time,
                duration = data.duration,
                index = data.id,
            })
            practiceOverlayNoteBounds[1] = math.min(practiceOverlayNoteBounds[1], data.note)
            practiceOverlayNoteBounds[2] = math.max(practiceOverlayNoteBounds[2], data.note)
        end
    end
    table.sort(noteMap, function(a, b) return a.time < b.time end)
    practiceOverlayScaleY = 128 / ((practiceOverlayNoteBounds[2] - practiceOverlayNoteBounds[1]) + 1)
    return noteMap
end

local function lerp(t, a, b)
    return a + (b - a) * t
end

local function lerpColor(t, a, b)
    return util.color.rgb(
        lerp(t, a.r, b.r),
        lerp(t, a.g, b.g),
        lerp(t, a.b, b.b)
    )
end

local function populatePracticeOverlayNotes()
    if not practiceOverlayNotesWrapper then return end

    local content = practiceOverlayNotesWrapper.layout.content

    local i = 1
    for _, data in pairs(practiceOverlayNoteMap) do
        practiceOverlayNoteIdToIndex[data.index] = i
        i = i + 1
        local note = {
            type = ui.TYPE.Image,
            props = {
                resource = ui.texture { path = 'textures/bardcraft/ui/pianoroll-note.dds' },
                size = util.vector2(data.duration * practiceOverlayScaleX - practiceOverlayScaleX, practiceOverlayScaleY * 4),
                tileH = true,
                tileV = false,
                position = util.vector2(data.time * practiceOverlayScaleX + (practiceOverlayWidthTicks * 0.5 * practiceOverlayScaleX), math.floor((practiceOverlayNoteBounds[2] - data.note) * practiceOverlayScaleY) * 2),
                alpha = 0.2,
            },
        }
        content:add(note)
    end
    practiceOverlayNotesWrapper:update()
    practiceOverlayNoteFlashTimes = {}
    practiceOverlayNoteFadeTimes = {}
    practiceOverlayNoteFadeAlphaStart = {}
end

local function createPracticeOverlay()
    local alreadyShowing = false
    local alpha = 0
    if practiceOverlay then
        alreadyShowing = true
        alpha = practiceOverlay.layout.props.alpha
        auxUi.deepDestroy(practiceOverlay)
    end
    practiceOverlayNoteMap = getPracticeNoteMap()

    practiceOverlayNotesWrapper = ui.create {
        type = ui.TYPE.Container,
        props = {
            relativeSize = util.vector2(1, 1),
        },
        content = ui.content{},
    }

    practiceOverlay = ui.create {
        layer = 'HUD',
        type = ui.TYPE.Image,
        props = {
            --relativeSize = util.vector2(1, 0),
            resource = ui.texture { path = 'textures/bardcraft/ui/practice-overlay.dds' },
            relativeSize = util.vector2(1, 0),
            size = util.vector2(0, 264),
            tileH = true,
            tileV = false,
            alpha = alpha,
        },
        content = ui.content {
            practiceOverlayNotesWrapper,
            {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture { path = 'textures/bardcraft/ui/practice-overlay-line.dds' },
                    anchor = util.vector2(0.5, 0.5),
                    relativePosition = util.vector2(0.5, 0.5),
                    size = util.vector2(8, 256),
                    color = Editor.uiColors.DEFAULT_LIGHT,
                },
            }
        },
    }
    if not alreadyShowing then
        practiceOverlayFadeInTimer = practiceOverlayFadeInDuration
    end

    practiceOverlayScaleX = 6 * (practiceSong.tempo * practiceSong.tempoMod / 120)
    practiceOverlayWidthTicks = ui.screenSize().x / practiceOverlayScaleX
    practiceOverlayTick = 1
    populatePracticeOverlayNotes()
end

local function destroyPracticeOverlay()
    if practiceOverlay then
        auxUi.deepDestroy(practiceOverlay)
        practiceOverlay = nil
    end
end

local function updatePracticeOverlay()
    if not practiceOverlay or not practiceOverlayNotesWrapper then return end
    practiceOverlayNotesWrapper.layout.props.position = util.vector2(-practiceOverlayTick * practiceOverlayScaleX, 0)
    practiceOverlayNotesWrapper:update()
    practiceOverlay:update()
end

local function doHurt(amount)
    hurtAlpha = 0.25
    self.type.stats.dynamic.health(self).current = math.max(self.type.stats.dynamic.health(self).current - amount, 1)
    ambient.playSoundFile('sound\\fx\\body hit.wav')
end

local function doBread()
    doHurt(1)
    ui.showMessage('A patron threw their bread at you.\n1 Bread acquired.')
    core.sendGlobalEvent('BC_ThrowItem', { actor = self, item = 'ingred_bread_01', count = 1 })
end

local function doDrink()
    doHurt(5)
    ui.showMessage('A patron threw their drink at you. You managed to catch it!\n1 Mazte acquired.')
    core.sendGlobalEvent('BC_ThrowItem', { actor = self, item = 'Potion_Local_Brew_01', count = 1 })
end

return {
    engineHandlers = {
        onInit = function()
            Editor:init()
        end,
        onLoad = function(data)
            Performer:onLoad(data)
            populateKnownSongs()
            anim.removeAllVfx(self)
            Editor:init()

            if data.BC_PerformersInfo then
                performersInfo = data.BC_PerformersInfo
            end
        end,
        onSave = function()
            local data = Performer:onSave()
            data.BC_PerformersInfo = performersInfo
            return data
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
            if Performer.playing then
                Performer.musicTime = Performer.musicTime + dt
            end
        end,
        onKeyPress = function(e)
            if e.symbol == 'k' then
                Editor:onToggle()
            elseif e.symbol == 'n' then
                Performer:addPerformanceXP(10) -- debug
            elseif e.symbol == 'o' then
                anim.addVfx(self, "meshes/Bardcraft/tuba.nif", {
                    boneName = 'Bip01 BOInstrument',
                    vfxId = 'BO_Instrument',
                    loop = true,
                    useAmbientLight = false
                })
                Performer.startAnim('bctuba')
            elseif e.symbol == 'b' then
                doBread()
            elseif e.symbol == 'v' then
                doDrink()
            elseif Editor.active and e.code == input.KEY.Space then
                Editor:togglePlayback(input.isCtrlPressed())
            end
        end,
        onMouseWheel = function(v, h)
            Editor:onMouseWheel(v, h)
        end,
        onFrame = function(dt)
            Editor:onFrame(self)
            Performer:onFrame()
            if practiceOverlay and practiceSong then
                --practiceOverlayTick = practiceOverlayTick + practiceSong:secondsToTicks(dt)
                practiceOverlayTick = practiceSong:secondsToTicks(Performer.musicTime)
                if practiceOverlayFadeInTimer > 0 then
                    practiceOverlayFadeInTimer = practiceOverlayFadeInTimer - core.getRealFrameDuration()
                    if practiceOverlayFadeInTimer <= 0 then
                        practiceOverlayFadeInTimer = 0
                    end
                end

                for id, time in pairs(practiceOverlayNoteFlashTimes) do
                    if time > 0 then
                        practiceOverlayNoteFlashTimes[id] = math.max(time - dt, 0)
                        local note = practiceOverlayNotesWrapper.layout.content[practiceOverlayNoteIdToIndex[id]]
                        if note then
                            note.props.alpha = lerp((1.5 - practiceOverlayNoteFlashTimes[id]) / 1.5, 1, 0.4)
                            note.props.color = practiceOverlayNoteSuccess[id] and Editor.uiColors.DEFAULT or Editor.uiColors.DARK_RED
                        end
                        if practiceOverlayNoteFlashTimes[id] <= 0 then
                            practiceOverlayNoteFlashTimes[id] = nil
                        end
                    end
                end

                for id, time in pairs(practiceOverlayNoteFadeTimes) do
                    if time > 0 then
                        practiceOverlayNoteFadeTimes[id] = math.max(time - dt, 0)
                        local note = practiceOverlayNotesWrapper.layout.content[practiceOverlayNoteIdToIndex[id]]
                        if note then
                            note.props.alpha = lerp((0.5 - practiceOverlayNoteFadeTimes[id]) / 0.5, practiceOverlayNoteFadeAlphaStart[id], 0)
                            local startColor = practiceOverlayNoteSuccess[id] and Editor.uiColors.DEFAULT or Editor.uiColors.DARK_RED
                            local endColor = practiceOverlayNoteSuccess[id] and Editor.uiColors.GRAY or Editor.uiColors.DARK_RED_DESAT
                            note.props.color = lerpColor((0.5 - practiceOverlayNoteFadeTimes[id]) / 0.5, startColor, endColor)
                        end
                        if practiceOverlayNoteFadeTimes[id] <= 0 then
                            practiceOverlayNoteFadeTimes[id] = nil
                            practiceOverlayNoteFadeAlphaStart[id] = nil
                            practiceOverlayNoteSuccess[id] = nil
                        end
                    end
                end
                local opacity = lerp((practiceOverlayFadeInDuration - practiceOverlayFadeInTimer) / practiceOverlayFadeInDuration, 0, practiceOverlayTargetOpacity)
                practiceOverlay.layout.props.alpha = opacity
                updatePracticeOverlay()
            end
            if hurtAlpha > 0 then
                hurtAlpha = math.max(hurtAlpha - dt, 0)
            end
            hurtOverlay.layout.props.alpha = hurtAlpha
            hurtOverlay:update()

            if queuedMilestone and not Performer.playing then
                local message
                if queuedMilestone < 100 then
                    message = l10n('UI_LvlUp_Performance_' .. queuedMilestone / 10)
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
                queuedMilestone = nil
            end
        end,
    },
    eventHandlers = {
        BO_ConductorEvent = function(data)
            local success = Performer.handleConductorEvent(data)
            if data.type == 'PerformStart' then
                practiceSong = data.song
                setmetatable(practiceSong, Song)
                createPracticeOverlay()
            elseif data.type == 'PerformStop' then
                destroyPracticeOverlay()
            elseif data.type == 'NoteEvent' then
                if practiceOverlay and practiceOverlayNoteIdToIndex[data.id] then
                    local content = practiceOverlayNotesWrapper.layout.content
                    local note = content[practiceOverlayNoteIdToIndex[data.id]]
                    if note then
                        practiceOverlayNoteFlashTimes[data.id] = 1.5
                        practiceOverlayNoteSuccess[data.id] = success
                        --note.props.alpha = 1
                    end
                end
            elseif data.type == 'NoteEndEvent' then
                if practiceOverlay and practiceOverlayNoteIdToIndex[data.id] then
                    local content = practiceOverlayNotesWrapper.layout.content
                    local note = content[practiceOverlayNoteIdToIndex[data.id]]
                    if note then
                        practiceOverlayNoteFadeTimes[data.id] = 0.5
                        practiceOverlayNoteFadeAlphaStart[data.id] = note.props.alpha
                        if practiceOverlayNoteFlashTimes[data.id] then
                            practiceOverlayNoteFlashTimes[data.id] = nil
                        end
                    end
                end
            end
        end,
        BC_GainPerformanceXP = function(data)
            if data.leveledUp then
                ui.showMessage(l10n('UI_LvlUp_Performance'):gsub('%%{level}', Performer.performanceSkill.level))
                ambient.playSoundFile('Sound\\Fx\\inter\\levelUP.wav')
            end
            if data.milestone then
                queuedMilestone = data.milestone
            end
        end,
        BC_GainConfidence = function(data)
            ui.showMessage(l10n('UI_Msg_GainConfidence'):gsub('%%{songTitle}', data.songTitle):gsub('%%{partTitle}', data.partTitle):gsub('%%{confidence}', string.format('%.2f', data.newConfidence * 100)))
        end,
        BC_PerformerInfo = function(data)
            performersInfo[data.actor.id] = {
                knownSongs = data.knownSongs,
                performanceSkill = data.performanceSkill,
            }
            Editor.performersInfo = performersInfo
        end,
        UiModeChanged = function(data)
            if data.newMode == nil then
                Editor:onUINil()
            end
        end,
    }
}