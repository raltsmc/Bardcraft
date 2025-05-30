local input = require('openmw.input')
local core = require('openmw.core')
local anim = require('openmw.animation')
local self = require('openmw.self')
local I = require('openmw.interfaces')
local camera = require('openmw.camera')
local ui = require('openmw.ui')
local auxUi = require('openmw_aux.ui')
local ambient = require('openmw.ambient')
local util = require('openmw.util')
local storage = require('openmw.storage')
local async = require('openmw.async')
local time = require('openmw_aux.time')
local types = require('openmw.types')
local nearby = require('openmw.nearby')

local l10n = core.l10n('Bardcraft')

local Performer = require('scripts.Bardcraft.performer')
local Editor = require('scripts.Bardcraft.editor')
local Song = require('scripts.Bardcraft.util.song').Song
local Data = require('scripts.Bardcraft.data')

local configPlayer = require('scripts.Bardcraft.config.player')
local configGlobal = require('scripts.Bardcraft.config.global')

local performersInfo = {}

local function populateKnownSongs()
    local bardData = storage.globalSection('Bardcraft')
    local storedSongs = bardData:getCopy('songs/preset') or {}
    local race = self.type.record(self).race
    for _, song in pairs(storedSongs) do
        local record = Data.StartingSongs[song.id]
        if record then
            local raceMatches = record == 'any' or record == race
            if raceMatches and not Performer.stats.knownSongs[song.id] then
                Performer:addKnownSong(song)
            end
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

local performOverlayNoteMap = {}
local performOverlayNoteIdToIndex = {}
local performOverlayNoteIndexToContentId = {}
local performOverlay = nil
local performOverlayNotesWrapper = nil
local performOverlayNoteFlashTimes = {}
local performOverlayNoteSuccess = {}
local performOverlayNoteFadeTimes = {}
local performOverlayNoteFadeAlphaStart = {}
local performOverlayTargetOpacity = 0.4
local performOverlayFadeInTimer = 0
local performOverlayFadeInDuration = 0.3
local performOverlayScaleX = 8 -- Every 8 ticks is 1 pixel
local performOverlayScaleY = 0
local performOverlayTick = 0
local performOverlayNoteBounds = {129, 0}
local performOverlayRepopulateTimeWindow = 2 -- seconds; only render notes within this time window to avoid crazy lag
local performOverlayRepopulateTime = performOverlayRepopulateTimeWindow 
local performOverlayNoteLayouts = {}
local performOverlayLastShakeFactor = 0

local performOverlayToggle = true

local tpFadeOverlay = ui.create {
    layer = 'Notification',
    type = ui.TYPE.Image,
    props = {
        resource = ui.texture { path = 'white' },
        relativeSize = util.vector2(1, 1),
        color = Editor.uiColors.BLACK,
        alpha = 0,
    },
}
local tpFadeInTimer = nil
local tpFadeOutTimer = nil

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

local performInstrument = nil
local lastCameraMode = nil
local resetAnimNextTick = false
local setVfxNextFrame = false
local nearbyPlaying = false
local nearbyPlayingTimer = 0

local function getPracticeNoteMap()
    if not practiceSong then return {} end
    local baseNoteMap = practiceSong:noteEventsToNoteMap(practiceSong.notes)
    local noteMap = {}
    performOverlayNoteBounds = {129, 0}
    for i, data in pairs(baseNoteMap) do
        if data.part == performancePart then
            table.insert(noteMap, {
                note = data.note,
                time = data.time,
                duration = data.duration,
                index = data.id,
            })
            performOverlayNoteBounds[1] = math.min(performOverlayNoteBounds[1], data.note)
            performOverlayNoteBounds[2] = math.max(performOverlayNoteBounds[2], data.note)
        end
    end
    table.sort(noteMap, function(a, b) return a.time < b.time end)
    performOverlayScaleY = 128 / ((performOverlayNoteBounds[2] - performOverlayNoteBounds[1]) + 2)
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

local function initPerformOverlayNotes()
    if not performOverlayNotesWrapper then return end

    local screenWidth = ui.screenSize().x

    performOverlayNoteLayouts = {}
    local i = 1
    for _, data in pairs(performOverlayNoteMap) do
        performOverlayNoteIdToIndex[data.index] = i
        local note = {
            type = ui.TYPE.Image,
            props = {
                index = data.index,
                resource = ui.texture { path = 'textures/bardcraft/ui/pianoroll-note.dds' },
                size = util.vector2(data.duration * performOverlayScaleX - performOverlayScaleX, performOverlayScaleY * 4),
                tileH = true,
                tileV = false,
                baseY = math.floor((performOverlayNoteBounds[2] - data.note) * performOverlayScaleY) * 2,
                position = util.vector2(data.time * performOverlayScaleX + screenWidth / 2, math.floor((performOverlayNoteBounds[2] - data.note) * performOverlayScaleY) * 2),
                alpha = 0.2,
            },
        }
        table.insert(performOverlayNoteLayouts, note)
        i = i + 1
    end
end

local function populatePerformOverlayNotes()
    local windowXOffset = performOverlayTick * performOverlayScaleX - performOverlayScaleX
    local windowXSize = ui.screenSize().x + practiceSong:secondsToTicks(performOverlayRepopulateTimeWindow) * performOverlayScaleX
    local content = ui.content {}
    performOverlayNoteIndexToContentId = {}

    local count = 0
    for i, note in pairs(performOverlayNoteLayouts) do
        local notePos = note.props.position.x
        local noteSize = note.props.size.x

        if notePos >= windowXOffset + windowXSize then
            break
        end
        if notePos + noteSize >= windowXOffset then
            content:add(note)
            count = count + 1
            performOverlayNoteIndexToContentId[i] = count
        end
    end

    performOverlayNotesWrapper.layout.content[1].content = content
    performOverlayNotesWrapper:update()
end

local function createPerformOverlay()
    local alreadyShowing = false
    local alpha = 0
    if performOverlay then
        alreadyShowing = true
        alpha = performOverlay.layout.props.alpha
        auxUi.deepDestroy(performOverlay)
    end
    performOverlayNoteMap = getPracticeNoteMap()

    performOverlayNotesWrapper = ui.create {
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
                    position = util.vector2(practiceSong:barToTick(practiceSong.loopBars[2]) * performOverlayScaleX + ui.screenSize().x / 2, 0),
                    size = util.vector2(8, 256),
                    color = Editor.uiColors.CYAN,
                },
            }
        },
    }

    performOverlay = ui.create {
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
            visible = performOverlayToggle,
        },
        content = ui.content {
            performOverlayNotesWrapper,
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
        performOverlayFadeInTimer = performOverlayFadeInDuration
    end

    performOverlayScaleX = 6 * (practiceSong.tempo * practiceSong.tempoMod / 120)
    performOverlayTick = 1
    initPerformOverlayNotes()
    populatePerformOverlayNotes()
    performOverlayNoteFlashTimes = {}
    performOverlayNoteFadeTimes = {}
    performOverlayNoteFadeAlphaStart = {}
    performOverlayNoteSuccess = {}
    performOverlayRepopulateTime = performOverlayRepopulateTimeWindow 
    performOverlayLastShakeFactor = -1
end

local function togglePerformOverlay()
    if performOverlay then
        performOverlayToggle = not performOverlayToggle
        performOverlay.layout.props.visible = performOverlayToggle
        if not performOverlayToggle then
            performOverlayFadeInTimer = 0
            performOverlay.layout.props.alpha = 0
        else
            performOverlayFadeInTimer = performOverlayFadeInDuration
            performOverlay.layout.props.alpha = 0.4
        end
    end
end

local function destroyPerformOverlay()
    if performOverlay then
        auxUi.deepDestroy(performOverlay)
        performOverlay = nil
    end
end

local function updatePerformOverlay()
    if not performOverlay or not performOverlayNotesWrapper then return end
    performOverlayNotesWrapper.layout.props.position = util.vector2(-performOverlayTick * performOverlayScaleX, 0)
    if performOverlayRepopulateTime > 0 then
        performOverlayRepopulateTime = math.max(performOverlayRepopulateTime - core.getRealFrameDuration(), 0)
    else
        performOverlayRepopulateTime = performOverlayRepopulateTimeWindow
        populatePerformOverlayNotes()
    end
    performOverlayNotesWrapper:update()
    performOverlay:update()
end

local function doHurt(amount)
    hurtAlpha = 0.25
    self.type.stats.dynamic.health(self).current = self.type.stats.dynamic.health(self).current - amount
    ambient.playSoundFile('sound\\fx\\body hit.wav')
end

local function playSwoosh()
    ambient.playSoundFile('sound\\fx\\swoosh ' .. math.random(1, 3) .. '.wav')
end

local function startTrespassTimer()
    bannedVenueTrespassTimer = 0
    ui.showMessage(l10n('UI_Msg_Warn_Trespass'))
end

local function setPerformerInfo()
    performersInfo[self.id] = Performer.stats
    Editor.performersInfo = performersInfo
end

local function verifyPerformInstrument()
    if performInstrument then
        local inventory = self.type.inventory(self)
        if not inventory:find(performInstrument.id) then
            performInstrument = nil
            core.sendGlobalEvent('BO_StopPerformance')
        end
    end
end

local function confirmModal(onYes, onNo)
    if Performer.playing then
        Editor:playerConfirmModal(self, onYes, onNo)
    end
end

local function onStanceChange(stance)
    if not Performer.playing then return end
    confirmModal(function()
        core.sendGlobalEvent('BO_StopPerformance')
        self.type.setStance(self, stance)
    end,
    function()
        self.type.setStance(self, self.type.STANCE.Nothing)
    end)
    self.type.setStance(self, self.type.STANCE.Nothing)
end

input.registerTriggerHandler('ToggleWeapon', async:callback(function()
    if not core.isWorldPaused() then
        onStanceChange(self.type.STANCE.Weapon)
    end
end))

input.registerTriggerHandler('ToggleSpell', async:callback(function()
    if not core.isWorldPaused() then
        onStanceChange(self.type.STANCE.Spell)
    end
end))

input.registerActionHandler('Use', async:callback(function(e)
    if e and not core.isWorldPaused() then
        onStanceChange(self.type.STANCE.Weapon)
    end
end))

local previewHoldStart = nil
local previewHoldStartMode = nil

input.registerActionHandler('TogglePOV', async:callback(function(e)
    if Performer.playing and not core.isWorldPaused() then
        if e then
            previewHoldStart = core.getRealTime()
            previewHoldStartMode = camera.getMode()
        end
        if not e then
            if camera.getMode() == camera.MODE.Preview and previewHoldStart and core.getRealTime() - previewHoldStart > 0.25 then
                camera.setMode(previewHoldStartMode, true)
                if previewHoldStartMode ~= camera.MODE.Preview then
                    resetAnimNextTick = true
                end
                previewHoldStart = nil
                previewHoldStartMode = nil
                return false
            end

            if camera.getMode() ~= camera.MODE.FirstPerson then
                camera.setMode(camera.MODE.FirstPerson, true)
                resetAnimNextTick = true
            else
                camera.setMode(camera.MODE.ThirdPerson, true)
                resetAnimNextTick = true
            end
            previewHoldStart = nil
        end
        return false
    end
end))

local function silenceAmbientMusic()
    if configPlayer.options.bSilenceAmbientMusic == true then
        ambient.streamMusic("sound\\Bardcraft\\silence.opus", { fadeOut = 0.5 })
    end
end

local function unsilenceAmbientMusic()
    if configPlayer.options.bSilenceAmbientMusic == true then
        ambient.stopMusic()
        self:sendEvent('DM_ForceRestart')
    end
end

local function getRandomSong(pool)
    -- Keep trying until we find a song that the player doesn't know, or we run out of choices
    local availableChoices = {}

    -- Create a copy of the choices array to safely modify it
    for _, sourceFile in ipairs(pool) do
        table.insert(availableChoices, sourceFile)
    end

    -- Try to find a song the player doesn't know yet
    while #availableChoices > 0 do
        local index = math.random(1, #availableChoices)
        local sourceFile = availableChoices[index]
        local candidateSong = Performer.getSongBySourceFile(sourceFile)
        
        if candidateSong and not Performer.stats.knownSongs[candidateSong.id] then
            -- Found a song the player doesn't know
            return candidateSong
        end
        
        -- Remove this choice regardless of whether we found a usable song
        table.remove(availableChoices, index)
    end

    -- If no unknown songs were found, pick a random valid song
    if #pool > 0 then
        local shuffledChoices = {}
        for _, sourceFile in ipairs(pool) do
            table.insert(shuffledChoices, sourceFile)
        end
        -- Shuffle the choices
        for i = #shuffledChoices, 2, -1 do
            local j = math.random(1, i)
            shuffledChoices[i], shuffledChoices[j] = shuffledChoices[j], shuffledChoices[i]
        end
        -- Pick the first valid song from the shuffled list
        for _, sourceFile in ipairs(shuffledChoices) do
            local song = Performer.getSongBySourceFile(sourceFile)
            if song then return song end
        end
    end
end

local function precacheSongSamples(data)
    setmetatable(data.song, Song)
    local samples = {}
    for _, event in ipairs(data.song.notes) do
        if event.type == 'noteOn' and data.playedParts[event.part] then
            local part = data.song:getPartByIndex(event.part)
            if part then
                local instrument = part.instrument
                local profile = Song.getInstrumentProfile(instrument)
                local noteName = Song.noteNumberToName(event.note)
                local filePath = 'sound\\Bardcraft\\samples\\' .. profile.name .. '\\' .. profile.name .. '_' .. noteName .. '.wav'
                samples[filePath] = true
            end
        end
    end
    for filePath, _ in pairs(samples) do
        ambient.playSoundFile(filePath, { volume = 0.0 })
    end
end

return {
    engineHandlers = {
        onInit = function()
            Editor:init()
            populateKnownSongs()
            setPerformerInfo()
        end,
        onLoad = function(data)
            core.sendGlobalEvent('BC_ParseMidis')
            if not data then return end
            Performer:onLoad(data)
            populateKnownSongs()
            anim.removeAllVfx(self)
            Editor:init()

            if data.BC_PerformersInfo then
                performersInfo = data.BC_PerformersInfo
            end
            setPerformerInfo()
        end,
        onSave = function()
            local data = Performer:onSave()
            data.BC_PerformersInfo = performersInfo
            return data
        end,
        onActive = function()
            Performer:setSheatheVfx()
            core.sendGlobalEvent('BC_RecheckTroupe', { player = self, })
        end,
        onUpdate = function(dt)
            if Performer.playing then
                if resetAnimNextTick then
                    resetAnimNextTick = false
                    Performer.resetAnim()
                    Performer.resetVfx()
                end
                local queuedMode = camera.getQueuedMode()
                if queuedMode == camera.MODE.FirstPerson or queuedMode == camera.MODE.Preview then
                    camera.setMode(queuedMode, true)
                    resetAnimNextTick = true
                else
                    camera.setMode(camera.getMode(), false)
                end
            end
            Performer:onUpdate(dt)
            if self.cell then
                if not currentCell or currentCell ~= self.cell then
                    currentCell = self.cell

                    core.sendGlobalEvent('BC_RecheckCell', { player = self, })

                    local banEndTime = Performer.stats.bannedVenues[currentCell.name]
                    if banEndTime and core.getGameTime() < banEndTime then
                        -- Player is in a banned venue
                        startTrespassTimer()
                    else
                        -- Player is not in a banned venue
                        unbanFromVenue(currentCell.name)
                        bannedVenueTrespassTimer = nil
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

            if nearbyPlayingTimer > 0 then
                nearbyPlayingTimer = math.max(nearbyPlayingTimer - dt, 0)
                if nearbyPlayingTimer <= 0 then
                    nearbyPlaying = false
                    if not Performer.playing then
                        unsilenceAmbientMusic()
                    end
                end
            else
                nearbyPlaying = false
            end
        end,
        onKeyPress = function(e)
            if e.code == configPlayer.keybinds.kOpenInterface then
                if input.isAltPressed() then
                    togglePerformOverlay()
                elseif not Performer.playing then
                    setPerformerInfo()
                    Editor:onToggle()
                else
                    confirmModal(function()
                        core.sendGlobalEvent('BO_StopPerformance')
                    end)
                end
            elseif Editor.active and e.code == input.KEY.Space then
                Editor:togglePlayback(input.isCtrlPressed())
            end
        end,
        onConsoleCommand = function(mode, command)
            -- Parse into tokens
            local tokens = {}
            for token in command:gmatch('%S+') do
                table.insert(tokens, token)
            end
            if string.lower(tokens[1]) == 'luabclevel' then
                if not tonumber(tokens[2]) then return end
                Performer.stats.performanceSkill.level = util.clamp(tonumber(tokens[2]), 1, 100)
                Performer.stats.performanceSkill.xp = 0
                Performer.stats.performanceSkill.req = Performer:getPerformanceXPRequired()
                ui.showMessage('DEBUG: Set Bardcraft level to ' .. Performer.stats.performanceSkill.level)
            elseif string.lower(tokens[1]) == 'luabcreset' then
                Performer:resetAllStats()

                if tokens[2] and string.lower(tokens[2]) == '--all' then
                    -- Send reset event to all troupe members
                    for _, actor in pairs(nearby.actors) do
                        if actor.type == types.NPC and Editor.troupeMembers[actor.id] then
                            actor:sendEvent('BC_ResetPerformer')
                        end
                    end
                end

                populateKnownSongs()
                ui.showMessage('DEBUG: Reset Bardcraft stats')
            elseif string.lower(tokens[1]) == 'luabcteachall' then
                Performer:teachAllSongs()
                ui.showMessage('DEBUG: Taught all songs')
            end
        end,
        onMouseWheel = function(v, h)
            Editor:onMouseWheel(v, h)
        end,
        onFrame = function(dt)
            if setVfxNextFrame then
                setVfxNextFrame = false
                Performer:setSheatheVfx()
            end
            local camMode = camera.getMode()
            if camMode ~= lastCameraMode then
                lastCameraMode = camMode
                setVfxNextFrame = true
            end
            Editor:onFrame()
            Performer:onFrame()
            if performOverlay and practiceSong then
                performOverlayTick = practiceSong:secondsToTicks(Performer.musicTime)
                if performOverlayFadeInTimer > 0 then
                    performOverlayFadeInTimer = performOverlayFadeInTimer - core.getRealFrameDuration()
                    if performOverlayFadeInTimer <= 0 then
                        performOverlayFadeInTimer = 0
                    end
                end

                for id, time in pairs(performOverlayNoteFlashTimes) do
                    if time > 0 then
                        performOverlayNoteFlashTimes[id] = math.max(time - dt, 0)
                        local note = performOverlayNotesWrapper.layout.content[1].content[performOverlayNoteIndexToContentId[performOverlayNoteIdToIndex[id]]]
                        if note then
                            note.props.alpha = lerp((1.5 - performOverlayNoteFlashTimes[id]) / 1.5, 1, 0.4)
                            note.props.color = performOverlayNoteSuccess[id] and Editor.uiColors.DEFAULT or Editor.uiColors.DARK_RED
                        end
                        if performOverlayNoteFlashTimes[id] <= 0 then
                            performOverlayNoteFlashTimes[id] = nil
                        end
                    end
                end

                for id, time in pairs(performOverlayNoteFadeTimes) do
                    if time > 0 then
                        performOverlayNoteFadeTimes[id] = math.max(time - dt, 0)
                        local note = performOverlayNotesWrapper.layout.content[1].content[performOverlayNoteIndexToContentId[performOverlayNoteIdToIndex[id]]]
                        if note then
                            note.props.alpha = lerp((0.5 - performOverlayNoteFadeTimes[id]) / 0.5, performOverlayNoteFadeAlphaStart[id], 0)
                            local startColor = performOverlayNoteSuccess[id] and Editor.uiColors.DEFAULT or Editor.uiColors.DARK_RED
                            local endColor = performOverlayNoteSuccess[id] and Editor.uiColors.GRAY or Editor.uiColors.DARK_RED_DESAT
                            note.props.color = lerpColor((0.5 - performOverlayNoteFadeTimes[id]) / 0.5, startColor, endColor)
                        end
                        if performOverlayNoteFadeTimes[id] <= 0 then
                            performOverlayNoteFadeTimes[id] = nil
                            performOverlayNoteFadeAlphaStart[id] = nil
                            performOverlayNoteSuccess[id] = nil
                        end
                    end
                end

                local currentShakeFactor = Performer.currentConfidence < 0.75 and (0.75 - Performer.currentConfidence) / 0.75 or 0
                -- Smooth shake factor
                if performOverlayLastShakeFactor == -1 then
                    performOverlayLastShakeFactor = currentShakeFactor
                end
                local shakeFactor = performOverlayLastShakeFactor * 0.99 + currentShakeFactor * 0.01
                performOverlayLastShakeFactor = shakeFactor

                for _, note in pairs(performOverlayNotesWrapper.layout.content[1].content) do
                    if note and note.props then
                        if not performOverlayNoteSuccess[note.props.index] then
                            note.props.position = util.vector2(note.props.position.x, note.props.baseY + shakeFactor * 5 * math.sin((core.getRealTime()) * 25 + note.props.index))
                        else
                            note.props.position = util.vector2(note.props.position.x, note.props.baseY)
                        end
                    end
                end

                local opacity = lerp((performOverlayFadeInDuration - performOverlayFadeInTimer) / performOverlayFadeInDuration, 0, performOverlayTargetOpacity)
                performOverlay.layout.props.alpha = opacity
                updatePerformOverlay()
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

            if tpFadeInTimer then
                tpFadeInTimer = math.min(tpFadeInTimer + core.getRealFrameDuration(), 3)
                tpFadeOverlay.layout.props.alpha = 1 - (tpFadeInTimer / 3)
                if tpFadeInTimer >= 3 then
                    tpFadeInTimer = nil
                    tpFadeOverlay.layout.props.alpha = 0
                end
                tpFadeOverlay:update()
            elseif tpFadeOutTimer then
                tpFadeOutTimer = math.min(tpFadeOutTimer + core.getRealFrameDuration(), 0.1)
                tpFadeOverlay.layout.props.alpha = tpFadeOutTimer / 0.1
                if tpFadeOutTimer >= 0.1 then
                    tpFadeOutTimer = nil
                    tpFadeOverlay.layout.props.alpha = 1
                end
                tpFadeOverlay:update()
            end
        end,
    },
    eventHandlers = {
        BO_ConductorEvent = function(data)
            if data.type == 'PerformStart' then
                --camera.setMode(camera.MODE.ThirdPerson, true)
            end
            local success = Performer.handleConductorEvent(data)
            if data.type == 'PerformStart' then
                practiceSong = data.song
                performancePart = data.part.index
                setmetatable(practiceSong, Song)
                createPerformOverlay()
                performInstrument = types.Miscellaneous.record(data.item)
                silenceAmbientMusic()
            elseif data.type == 'PerformStop' then
                destroyPerformOverlay()
                performInstrument = nil
                if not nearbyPlaying then
                    unsilenceAmbientMusic()
                end
            elseif data.type == 'NoteEvent' then
                if performOverlay and performOverlayNoteIndexToContentId[performOverlayNoteIdToIndex[data.id]] then
                    local content = performOverlayNotesWrapper.layout.content[1].content
                    local note = content[performOverlayNoteIndexToContentId[performOverlayNoteIdToIndex[data.id]]]
                    if note then
                        performOverlayNoteFlashTimes[data.id] = 1.5
                        performOverlayNoteSuccess[data.id] = success
                        --note.props.alpha = 1
                    end
                end
            elseif data.type == 'NoteEndEvent' then
                if performOverlay and performOverlayNoteIndexToContentId[performOverlayNoteIdToIndex[data.id]] then
                    local content = performOverlayNotesWrapper.layout.content[1].content
                    local note = content[performOverlayNoteIndexToContentId[performOverlayNoteIdToIndex[data.id]]]
                    if note then
                        performOverlayNoteFadeTimes[data.id] = 0.5
                        performOverlayNoteFadeAlphaStart[data.id] = note.props.alpha
                        if performOverlayNoteFlashTimes[data.id] then
                            performOverlayNoteFlashTimes[data.id] = nil
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
        BC_PracticeEfficiency = function(data)
            if configGlobal.options.bEnablePracticeEfficiency ~= true then return end
            local message = l10n('UI_Msg_PracticeEfficiency'):gsub('%%{efficiency}', string.format('%d', data.efficiency * 100))
            ui.showMessage(message)
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
                ambient.playSoundFile(data.sound)
            elseif data.type == 'Flavor' then
                ui.showMessage(data.message)
            end
        end,
        BC_SpeechcraftXP = function(data)
            local options = {
                skillGain = data.amount,
                useType = I.SkillProgression.SKILL_USE_TYPES.Speechcraft_Success,
            }
            I.SkillProgression.skillUsed('speechcraft', options)
        end,
        BC_PerformanceLog = function(data)
            data.oldRep = Performer.stats.reputation
            Performer:modReputation(data.rep)
            data.newRep = Performer.stats.reputation
            if data.kickedOut then
                data.banEndTime = banFromVenue(data.cell, data.gameTime, 1)
            end
            Editor:showPerformanceLog(data)

            if data.type == Song.PerformanceType.Tavern then
                local crowdSound
                if data.quality >= 90 and data.density > 4 then
                    crowdSound = 'clap1.wav'
                elseif data.quality >= 70 then
                    crowdSound = 'clap3.wav'
                elseif data.quality >= 50 then
                    crowdSound = 'clap-polite.wav'
                elseif data.quality < 30 then
                    crowdSound = 'boo' .. math.random(1, 4) .. '.wav'
                end

                if crowdSound then
                    ambient.playSoundFile('sound\\Bardcraft\\crowd\\' .. crowdSound)
                end
            end
            table.insert(Performer.stats.performanceLogs, data)
        end,
        BC_StartPerformanceSuccess = function(data)
            Editor:onToggle()
            self.type.setStance(self, self.type.STANCE.Nothing)
            if configPlayer.options.bPrecacheSamples then
                precacheSongSamples(data)
            end
        end,
        BC_StartPerformanceFail = function(data)
            ui.showMessage(data.reason)
        end,
        BC_FinalizeDraft = function(data)
            Performer:teachSong(data.song)
            ui.showMessage(l10n('UI_Msg_FinalizedDraft'):gsub('%%{songTitle}', data.song.title))
            ambient.playSoundFile('sound\\Bardcraft\\finalize_draft.wav')
        end,
        BC_SheatheInstrument = function(data)
            ambient.playSoundFile('sound\\Bardcraft\\equip.wav')
            Performer:setSheathedInstrument(data.recordId)
        end,
        BC_BookReadResult = function(data)
            if data.success then
                local id = data.id
                local songBook = Data.SongBooks[id]
                if not songBook then return end

                local songBookPoolSourceFiles = {}
                local seen = {}

                if songBook.pools and #songBook.pools > 0 then
                    for _, poolId in ipairs(songBook.pools) do
                        local pool = Data.SongPools[poolId]
                        if pool and #pool > 0 then
                            for _, songIdInPool in ipairs(pool) do
                                local sourceFile = Data.SongIds[songIdInPool]
                                if sourceFile and not seen[sourceFile] then
                                    table.insert(songBookPoolSourceFiles, sourceFile)
                                    seen[sourceFile] = true
                                end
                            end
                        end
                    end
                elseif songBook.songs and #songBook.songs > 0 then
                    for _, songId in ipairs(songBook.songs) do
                        local sourceFile = Data.SongIds[songId]
                        if sourceFile and not seen[sourceFile] then
                            table.insert(songBookPoolSourceFiles, sourceFile)
                            seen[sourceFile] = true
                        end
                    end
                end

                if #songBookPoolSourceFiles == 0 then return end

                local song = getRandomSong(songBookPoolSourceFiles)
                local success = false
                success = song and Performer:teachSong(song) or false

                if success then
                    ui.showMessage(l10n('UI_Msg_LearnSong_Success'):gsub('%%{songTitle}', song.title))
                    ambient.playSoundFile('Sound\\fx\\inter\\levelUP.wav')
                elseif song then
                    ui.showMessage(l10n('UI_Msg_LearnSong_Fail'):gsub('%%{songTitle}', song.title))
                end
            else
                ui.showMessage(l10n('UI_Msg_BookReadFail'))
            end
        end,
        BC_MusicBoxActivate = function(data)
            local object = data.object
            Editor:playerChoiceModal(self, l10n('UI_MusicBox'), {
                {
                    text = l10n('UI_MusicBox_TogglePlaying'),
                    callback = function()
                        local musicBox = Data.MusicBoxes[object.recordId]
                        if not musicBox then return end

                        local musicBoxPoolSourceFiles = {}
                        local seen = {}

                        if musicBox.pools and #musicBox.pools > 0 then
                            for _, poolId in ipairs(musicBox.pools) do
                                local pool = Data.SongPools[poolId]
                                if pool and #pool > 0 then
                                    for _, songIdInPool in ipairs(pool) do
                                        local sourceFile = Data.SongIds[songIdInPool]
                                        if sourceFile and not seen[sourceFile] then
                                            table.insert(musicBoxPoolSourceFiles, sourceFile)
                                            seen[sourceFile] = true
                                        end
                                    end
                                end
                            end
                        elseif musicBox.songs and #musicBox.songs > 0 then
                            -- This music box has its own list of songs
                            for _, songId in ipairs(musicBox.songs) do
                                local sourceFile = Data.SongIds[songId]
                                if sourceFile and not seen[sourceFile] then
                                    table.insert(musicBoxPoolSourceFiles, sourceFile)
                                    seen[sourceFile] = true
                                end
                            end
                        end
                        
                        if #musicBoxPoolSourceFiles == 0 then return end -- No songs found to pick from

                        local song = getRandomSong(musicBoxPoolSourceFiles)
                        
                        if song then -- Check if getRandomSong found a suitable song
                            object:sendEvent('BC_MusicBoxToggle', { actor = self, prefSong = song.sourceFile, })
                        end
                    end
                },
                {
                    text = l10n('UI_MusicBox_PickUp'),
                    callback = function()
                        object:sendEvent('BC_MusicBoxPickup', { actor = self, })
                        ambient.playSoundFile('Sound\\fx\\item\\item.wav')
                    end,
                }
            }, data.songName)
        end,
        BC_NearbyPlaying = function()
            nearbyPlayingTimer = 10
            if not nearbyPlaying then
                nearbyPlaying = true
                silenceAmbientMusic()
            end
        end,
        BC_TeachSong = function(data)
            local song = data.song
            if song then
                local success = Performer:teachSong(song)
                if success then
                    ui.showMessage(l10n('UI_Msg_LearnSong_Success'):gsub('%%{songTitle}', song.title))
                    ambient.playSoundFile('Sound\\fx\\inter\\levelUP.wav')
                end
            end
        end,
        BC_TroupeStatus = function(data)
            local members = {}
            for _, member in ipairs(data.members) do
                members[member.id] = true
            end
            Editor.troupeMembers = members
            if Editor.troupeSize ~= #data.members and Performer.playing then
                core.sendGlobalEvent('BO_StopPerformance')
                Editor.performancePartAssignments = {}
            end
            Editor.troupeSize = #data.members
        end,
        BC_TPFadeOut = function()
            tpFadeOutTimer = 0
        end,
        BC_TPFadeIn = function()
            tpFadeOutTimer = nil
            tpFadeInTimer = 0
            ambient.playSoundFile('sound\\Bardcraft\\gohome.wav')
        end,
        DM_TrackStarted = function()
            if Performer.playing or nearbyPlaying then
                silenceAmbientMusic()
            end
        end,
        UiModeChanged = function(data)
            Performer:verifySheathedInstrument()
            verifyPerformInstrument()
            if data.newMode == nil then
                Editor:onUINil()
                core.sendGlobalEvent('BC_RecheckTroupe', { player = self, })
            elseif data.newMode == 'Scroll' or data.newMode == 'Book' then
                local book = data.arg
                local id = book.recordId
                if Data.SongBooks[id] then
                    core.sendGlobalEvent('BC_BookRead', { player = self, book = book })
                end
            end
        end,
    }
}