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
local async = require('openmw.async')
local time = require('openmw_aux.time')
local calendar = require('openmw_aux.calendar')

local l10n = core.l10n('Bardcraft')

local Performer = require('scripts.Bardcraft.performer')
local Editor = require('scripts.Bardcraft.editor')
local Song = require('scripts.Bardcraft.util.song').Song
local Feedback = require('scripts.Bardcraft.feedback')

local performersInfo = {}

local function populateKnownSongs()
    -- Check the stored preset songs; if any are set to startUnlocked but are missing from knownSongs, add them
    local bardData = storage.globalSection('Bardcraft')
    local storedSongs = bardData:getCopy('songs/preset') or {}
    for _, song in pairs(storedSongs) do
        if song.startUnlocked and not Performer.stats.knownSongs[song.id] then
            Performer:addKnownSong(song)
        end
    end
end

local currentCell = nil
local bannedVenueTrespassTimer = nil
local bannedVenueTrespassDuration = 30 -- seconds

local function unbanFromVenue(cellName)
    if Performer.stats.bannedVenues[cellName] then
        Performer.stats.bannedVenues[cellName] = nil
        performersInfo[self.id] = Performer.stats
        Editor.performersInfo = performersInfo
    end
end

local function banFromVenue(cellName, startTime, days)
    if Performer.stats.bannedVenues[cellName] then
        print('Already banned from ' .. cellName)
        return Performer.stats.bannedVenues[cellName]
    end
    local startDay = math.ceil(startTime / time.day)
    local endDay = startDay + days
    local endTime = endDay * time.day
    local currentTime = core.getGameTime()
    if currentTime >= startTime and currentTime < endTime then
        Performer.stats.bannedVenues[cellName] = endTime
        currentCell = nil
        performersInfo[self.id] = Performer.stats
        Editor.performersInfo = performersInfo
        return endTime
    end
    return nil
end

local performancePart = nil
local queuedMilestone = nil
local practiceSong = nil

local practiceOverlayNoteMap = {}
local practiceOverlayNoteIdToIndex = {}
local practiceOverlayNoteIndexToContentId = {}
local practiceOverlay = nil
local practiceOverlayNotesWrapper = nil
local practiceOverlayNoteFlashTimes = {}
local practiceOverlayNoteSuccess = {}
local practiceOverlayNoteFadeTimes = {}
local practiceOverlayNoteFadeAlphaStart = {}

local practiceOverlayTargetOpacity = 0.4
local practiceOverlayFadeInTimer = 0
local practiceOverlayFadeInDuration = 0.3
local practiceOverlayScaleX = 8 -- Every 8 ticks is 1 pixel
local practiceOverlayScaleY = 0
local practiceOverlayTick = 0
local practiceOverlayNoteBounds = {129, 0}
local practiceOverlayRepopulateTimeWindow = 2 -- seconds; only render notes within this time window to avoid crazy lag
local practiceOverlayRepopulateTime = practiceOverlayRepopulateTimeWindow 
local practiceOverlayNoteLayouts = {}
local practiceOverlayLastShakeFactor = 0

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
    practiceOverlayScaleY = 128 / ((practiceOverlayNoteBounds[2] - practiceOverlayNoteBounds[1]) + 2)
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

local function initPracticeOverlayNotes()
    if not practiceOverlayNotesWrapper then return end

    local screenWidth = ui.screenSize().x

    practiceOverlayNoteLayouts = {}
    local i = 1
    for _, data in pairs(practiceOverlayNoteMap) do
        practiceOverlayNoteIdToIndex[data.index] = i
        local note = {
            type = ui.TYPE.Image,
            props = {
                index = data.index,
                resource = ui.texture { path = 'textures/bardcraft/ui/pianoroll-note.dds' },
                size = util.vector2(data.duration * practiceOverlayScaleX - practiceOverlayScaleX, practiceOverlayScaleY * 4),
                tileH = true,
                tileV = false,
                baseY = math.floor((practiceOverlayNoteBounds[2] - data.note) * practiceOverlayScaleY) * 2,
                position = util.vector2(data.time * practiceOverlayScaleX + screenWidth / 2, math.floor((practiceOverlayNoteBounds[2] - data.note) * practiceOverlayScaleY) * 2),
                alpha = 0.2,
            },
        }
        table.insert(practiceOverlayNoteLayouts, note)
        i = i + 1
    end
end

local function populatePracticeOverlayNotes()
    local windowXOffset = practiceOverlayTick * practiceOverlayScaleX - practiceOverlayScaleX
    local windowXSize = ui.screenSize().x + practiceSong:secondsToTicks(practiceOverlayRepopulateTimeWindow) * practiceOverlayScaleX
    local content = ui.content {}
    practiceOverlayNoteIndexToContentId = {}

    local count = 0
    for i, note in pairs(practiceOverlayNoteLayouts) do
        local notePos = note.props.position.x
        local noteSize = note.props.size.x

        if notePos >= windowXOffset + windowXSize then
            break
        end
        if notePos + noteSize >= windowXOffset then
            content:add(note)
            count = count + 1
            practiceOverlayNoteIndexToContentId[i] = count
        end
    end

    practiceOverlayNotesWrapper.layout.content[1].content = content
    practiceOverlayNotesWrapper:update()
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
        content = ui.content{
            {
                type = ui.TYPE.Container,
                props = {
                    relativeSize = util.vector2(1, 1),
                },
                content = ui.content {},
            },
            {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture { path = 'textures/bardcraft/ui/practice-overlay-line.dds' },
                    position = util.vector2(practiceSong:barToTick(practiceSong.loopBars[2]) * practiceOverlayScaleX + ui.screenSize().x / 2, 0),
                    size = util.vector2(8, 256),
                    color = Editor.uiColors.CYAN,
                },
            }
        },
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
            },
        },
    }
    if not alreadyShowing then
        practiceOverlayFadeInTimer = practiceOverlayFadeInDuration
    end

    practiceOverlayScaleX = 6 * (practiceSong.tempo * practiceSong.tempoMod / 120)
    practiceOverlayTick = 1
    initPracticeOverlayNotes()
    populatePracticeOverlayNotes()
    practiceOverlayNoteFlashTimes = {}
    practiceOverlayNoteFadeTimes = {}
    practiceOverlayNoteFadeAlphaStart = {}
    practiceOverlayNoteSuccess = {}
    practiceOverlayRepopulateTime = practiceOverlayRepopulateTimeWindow 
    practiceOverlayLastShakeFactor = -1
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
    if practiceOverlayRepopulateTime > 0 then
        practiceOverlayRepopulateTime = math.max(practiceOverlayRepopulateTime - core.getRealFrameDuration(), 0)
    else
        practiceOverlayRepopulateTime = practiceOverlayRepopulateTimeWindow
        populatePracticeOverlayNotes()
    end
    practiceOverlayNotesWrapper:update()
    practiceOverlay:update()
end

local function doHurt(amount)
    hurtAlpha = 0.25
    self.type.stats.dynamic.health(self).current = self.type.stats.dynamic.health(self).current - amount
    ambient.playSoundFile('sound\\fx\\body hit.wav')
end

local function playSwoosh()
    ambient.playSoundFile('sound\\fx\\swoosh ' .. math.random(1, 3) .. '.wav')
end

local function getSongBySourceFile(sourceFile)
    -- Search songs/preset
    local bardData = storage.globalSection('Bardcraft')
    local storedSongs = bardData:get('songs/preset') or {}
    for _, song in pairs(storedSongs) do
        if song.sourceFile == sourceFile then
            return song
        end
    end
    return nil
end

local function startTrespassTimer()
    bannedVenueTrespassTimer = 0
    ui.showMessage(l10n('UI_Msg_Warn_Trespass'))
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
            Performer:onUpdate(dt)
            if self.cell then
                if not currentCell or currentCell ~= self.cell then
                    currentCell = self.cell

                    local banEndTime = Performer.stats.bannedVenues[currentCell.name]
                    if banEndTime and core.getGameTime() < banEndTime then
                        -- Player is in a banned venue
                        startTrespassTimer()
                    else
                        -- Player is not in a banned venue
                        unbanFromVenue(currentCell.name)
                    end
                end
            end
            if bannedVenueTrespassTimer then
                bannedVenueTrespassTimer = math.min(bannedVenueTrespassTimer + dt, bannedVenueTrespassDuration)
                if bannedVenueTrespassTimer >= bannedVenueTrespassDuration then
                    core.sendGlobalEvent('BC_Trespass', { player = self, })
                    bannedVenueTrespassTimer = 0
                end
            end
        end,
        onKeyPress = function(e)
            if e.symbol == 'b' then
                Editor:onToggle()
            elseif e.symbol == 'n' then
                Performer:addPerformanceXP(1000) -- debug
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
                        local note = practiceOverlayNotesWrapper.layout.content[1].content[practiceOverlayNoteIndexToContentId[practiceOverlayNoteIdToIndex[id]]]
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
                        local note = practiceOverlayNotesWrapper.layout.content[1].content[practiceOverlayNoteIndexToContentId[practiceOverlayNoteIdToIndex[id]]]
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

                local currentShakeFactor = Performer.currentConfidence < 0.75 and (0.75 - Performer.currentConfidence) / 0.75 or 0
                -- Smooth shake factor
                if practiceOverlayLastShakeFactor == -1 then
                    practiceOverlayLastShakeFactor = currentShakeFactor
                end
                local shakeFactor = practiceOverlayLastShakeFactor * 0.99 + currentShakeFactor * 0.01
                practiceOverlayLastShakeFactor = shakeFactor

                for _, note in pairs(practiceOverlayNotesWrapper.layout.content[1].content) do
                    if note and note.props then
                        if not practiceOverlayNoteSuccess[note.props.index] then
                            note.props.position = util.vector2(note.props.position.x, note.props.baseY + shakeFactor * 5 * math.sin((core.getRealTime()) * 25 + note.props.index))
                        else
                            note.props.position = util.vector2(note.props.position.x, note.props.baseY)
                        end
                    end
                end

                local opacity = lerp((practiceOverlayFadeInDuration - practiceOverlayFadeInTimer) / practiceOverlayFadeInDuration, 0, practiceOverlayTargetOpacity)
                practiceOverlay.layout.props.alpha = opacity
                updatePracticeOverlay()
            end
            if hurtAlpha > 0 then
                hurtAlpha = math.max(hurtAlpha - core.getRealFrameDuration(), 0)
                hurtOverlay.layout.props.alpha = hurtAlpha
                hurtOverlay:update()
            end
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
            if data.type == 'PerformStart' then
                camera.setMode(camera.MODE.ThirdPerson, true)
            end
            local success = Performer.handleConductorEvent(data)
            if data.type == 'PerformStart' then
                practiceSong = data.song
                performancePart = data.part.index
                setmetatable(practiceSong, Song)
                createPracticeOverlay()
            elseif data.type == 'PerformStop' then
                destroyPracticeOverlay()
            elseif data.type == 'NoteEvent' then
                if practiceOverlay and practiceOverlayNoteIndexToContentId[practiceOverlayNoteIdToIndex[data.id]] then
                    local content = practiceOverlayNotesWrapper.layout.content[1].content
                    local note = content[practiceOverlayNoteIndexToContentId[practiceOverlayNoteIdToIndex[data.id]]]
                    if note then
                        practiceOverlayNoteFlashTimes[data.id] = 1.5
                        practiceOverlayNoteSuccess[data.id] = success
                        --note.props.alpha = 1
                    end
                end
            elseif data.type == 'NoteEndEvent' then
                if practiceOverlay and practiceOverlayNoteIndexToContentId[practiceOverlayNoteIdToIndex[data.id]] then
                    local content = practiceOverlayNotesWrapper.layout.content[1].content
                    local note = content[practiceOverlayNoteIndexToContentId[practiceOverlayNoteIdToIndex[data.id]]]
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
                ui.showMessage(l10n('UI_LvlUp_Performance'):gsub('%%{level}', Performer.stats.performanceSkill.level))
                ambient.playSoundFile('Sound\\Fx\\inter\\levelUP.wav')
            end
            if data.milestone then
                queuedMilestone = data.milestone
            end
        end,
        BC_GainConfidence = function(data)
            local message
            if data.newConfidence > data.oldConfidence then
                message = l10n('UI_Msg_Confidence_Up')
            elseif data.newConfidence < data.oldConfidence then
                message = l10n('UI_Msg_Confidence_Down')
            else
                message = l10n('UI_Msg_Confidence_NoChange')
            end
            ui.showMessage(message:gsub('%%{songTitle}', data.songTitle):gsub('%%{partTitle}', data.partTitle):gsub('%%{confidence}', string.format('%.2f', data.newConfidence * 100)))
        end,
        BC_PerformerInfo = function(data)
            performersInfo[data.actor.id] = data.stats
            Editor.performersInfo = performersInfo
        end,
        BC_PerformanceEvent = function(data)
            if data.type == 'ThrownItem' then
                ui.showMessage(data.message)
                if data.damage > 0 then
                    doHurt(data.damage)
                else
                    playSwoosh()
                end
            elseif data.type == 'Gold' then
                local message = data.message:gsub('%%{amount}', data.amount)
                ui.showMessage(message)
                ambient.playSoundFile('sound\\Fx\\item\\money.wav')
            end
        end,
        BC_PerformanceLog = function(data)
            data.oldRep = Performer.stats.reputation
            Performer:modReputation(data.rep)
            data.newRep = Performer.stats.reputation
            if data.kickedOut then
                data.banEndTime = banFromVenue(data.cell, data.gameTime, 1)
            end
            Editor:showPerformanceLog(data)
        end,
        BC_StartPerformanceSuccess = function()
            Editor:onToggle()
        end,
        BC_StartPerformanceFail = function(data)
            ui.showMessage(data.reason)
        end,
        UiModeChanged = function(data)
            if data.newMode == nil then
                Editor:onUINil()
            elseif data.newMode == 'Scroll' then
                local book = data.arg
                local id = book.recordId
                local suffix = id:match("_(%w+)$")
                local prefix = id:sub(1, -#suffix - 2)
                if prefix ~= '_rlts_bc_sheetmusic' then return end

                local bardData = storage.globalSection('Bardcraft')
                local mappings = bardData:get('sheetmusic') or {}
                local choices = mappings[suffix]
                if not choices or #choices == 0 then return end
                
                -- Keep trying until we find a song that the player doesn't know, or we run out of choices
                local song = nil
                local success = false
                local availableChoices = {}

                -- Create a copy of the choices array to safely modify it
                for _, sourceFile in ipairs(choices) do
                    table.insert(availableChoices, sourceFile)
                end

                -- Try to find a song the player doesn't know yet
                while #availableChoices > 0 and not song do
                    local index = math.random(1, #availableChoices)
                    local sourceFile = availableChoices[index]
                    local candidateSong = getSongBySourceFile(sourceFile)
                    
                    if candidateSong and not Performer.stats.knownSongs[candidateSong.id] then
                        -- Found a song the player doesn't know
                        song = candidateSong
                    end
                    
                    -- Remove this choice regardless of whether we found a usable song
                    table.remove(availableChoices, index)
                end

                -- If no unknown songs were found, just pick the first valid song
                if not song and #choices > 0 then
                    for _, sourceFile in ipairs(choices) do
                        song = getSongBySourceFile(sourceFile)
                        if song then break end
                    end
                end

                success = song and Performer:teachSong(song) or false

                if success then
                    ui.showMessage(l10n('UI_Msg_LearnSong_Success'):gsub('%%{songTitle}', song.title))
                    ambient.playSoundFile('Sound\\fx\\inter\\levelUP.wav')
                elseif song then
                    ui.showMessage(l10n('UI_Msg_LearnSong_Fail'):gsub('%%{songTitle}', song.title))
                end

                core.sendGlobalEvent('BC_ConsumeItem', { item = book })
            end
        end,
    }
}