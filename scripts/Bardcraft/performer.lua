local P = {}

local types = require("openmw.types")
local core = require("openmw.core")
local omwself = require("openmw.self")
local anim = require("openmw.animation")
local I = require("openmw.interfaces")
local nearby = require("openmw.nearby")
local util = require("openmw.util")

local configGlobal = require('scripts.Bardcraft.config.global')
local instrumentData = require('scripts.Bardcraft.instruments').Instruments
local animData = require('scripts.Bardcraft.instruments').AnimData
local Song = require('scripts.Bardcraft.util.song').Song

--[[========
Performer Stats
============]]

P.knownSongs = {}
P.performanceSkill = {
    level = 1,
    xp = 0,
}
P.reputation = 0

function P:onSave()
    local saveData = {
        BC_PerformanceStat = self.performanceSkill,
        BC_KnownSongs = self.knownSongs,
        BC_Reputation = self.reputation,
    }
    return saveData
end

function P:sendPerformerInfo()
    local player = nearby.players[1]
    if player then
        player:sendEvent('BC_PerformerInfo', { actor = omwself, knownSongs = self.knownSongs, performanceSkill = self.performanceSkill })
    end
end

function P:onLoad(data)
    if not data then return end
    if data.BC_PerformanceStat then
        self.performanceSkill = data.BC_PerformanceStat
    end
    if data.BC_KnownSongs then
        self.knownSongs = data.BC_KnownSongs
    end
    if data.BC_Reputation then
        self.reputation = data.BC_Reputation
    end
    self:sendPerformerInfo()
end

function P:getPerformanceXPRequired()
    return (self.performanceSkill.level + 1) * 10
end

function P:getPerformanceProgress()
    return self.performanceSkill.xp / self:getPerformanceXPRequired()
end

function P:addPerformanceXP(xp)
    if self.performanceSkill.level >= 100 then return 0 end
    self.performanceSkill.xp = self.performanceSkill.xp + xp
    local leveledUp = false
    local milestone = nil
    local levelGain = 0
    while self:getPerformanceProgress() >= 1 do
        leveledUp = true
        levelGain = levelGain + 1
        self.performanceSkill.xp = self.performanceSkill.xp - self:getPerformanceXPRequired()
        self.performanceSkill.level = self.performanceSkill.level + 1
        if self.performanceSkill.level % 10 == 0 then
            milestone = self.performanceSkill.level
        end
    end
    if omwself.type == types.Player then
        omwself:sendEvent('BC_GainPerformanceXP', { leveledUp = leveledUp, milestone = milestone })
        --print("New skill level: " .. self.performanceSkill.level .. " (" .. self.performanceSkill.xp .. "/" .. self:getPerformanceXPRequired() .. ")")
    end
    if leveledUp then
        self:sendPerformerInfo()
    end
    return levelGain
end

function P:modReputation(mod)
    self.reputation = self.reputation + mod
    self:sendPerformerInfo()
end

function P:addKnownSong(song, confidences)
    if not self.knownSongs[song.id] then
        self.knownSongs[song.id] = {
            partConfidences = {},
        }
    end
    for _, part in ipairs(song.parts) do
        self.knownSongs[song.id].partConfidences[part.index] = (confidences and confidences[part.index]) or 0
    end
    self:sendPerformerInfo()
end

function P:teachSong(song)
    if not self.knownSongs[song.id] then
        self.knownSongs[song.id] = {
            partConfidences = {},
        }
        for _, part in ipairs(song.parts) do
            self.knownSongs[song.id].partConfidences[part.index] = 0
        end
        self:sendPerformerInfo()
        return true
    end
    return false
end

function P:modSongConfidence(songId, part, mod)
    if not self.knownSongs[songId] then
        self.knownSongs[songId] = {
            partConfidences = {},
        }
    end
    local confidence = self.knownSongs[songId].partConfidences[part] or 0
    if confidence ~= confidence then confidence = 0 end
    if mod ~= mod then mod = 0 end
    confidence = util.clamp(confidence + mod, 0, 1)
    self.knownSongs[songId].partConfidences[part] = confidence
    self:sendPerformerInfo()
end

--[[========
Performance Data
============]]

P.bpm = 0
P.musicTime = -1
P.currentSong = nil
P.currentPart = nil
P.playing = false
P.performanceType = nil

P.wasMoving = false
P.idleTimer = nil
P.instrument = nil

P.lastNoteTime = nil
P.noteIntervals = {}
P.currentDensity = 0
P.currentConfidence = 0
P.maxConfidence = 0
P.maxHistory = 24

P.xpGain = 0
P.levelGain = 0

P.maxConfidenceGrowth = 0
P.overallNoteEvents = {}

local xpMult = {
    [Song.PerformanceType.Tavern] = 1.5,
    [Song.PerformanceType.Street] = 0.2,
    [Song.PerformanceType.Practice] = 0.8,
}

local easyDensity = 1.0
local hardDensity = 6.0

local function getBpmConstant()
    local animFps = 24
    local animFramesPerBeat = 20
    local animBpm = animFps * 60 / animFramesPerBeat
    return P.bpm / animBpm
end

local function getAnimStartPoint(timeOffset)
    if timeOffset == -1 then
        return 0
    end
    local songBeatLength = 1 / (P.bpm / 60)
    local songTime = timeOffset % (songBeatLength * 16) -- in seconds
    local animTime = songTime / (songBeatLength * 16) -- from 0 to 1
    return animTime
end

function P.startAnim(animKey)
    local priority = {
        [anim.BONE_GROUP.LeftArm] = anim.PRIORITY.Hit,
        [anim.BONE_GROUP.RightArm] = anim.PRIORITY.Hit,
        [anim.BONE_GROUP.Torso] = anim.PRIORITY.Hit,
        [anim.BONE_GROUP.LowerBody] = anim.PRIORITY.WeaponLowerBody
    }

    I.AnimationController.playBlendedAnimation(animKey, {
        loops = 100000000,
        priority = priority,
        startPoint = getAnimStartPoint(P.musicTime) % 1,
        speed = getBpmConstant(),
    })
end

function P.resyncAnim(animKey)
    if anim.isPlaying(omwself, animKey) then
        anim.cancel(omwself, animKey)
        P.startAnim(animKey)
    end
end

function P.handleMovement(dt, idleAnim)
    if not P.playing then return false end
    if idleAnim == nil then
        idleAnim = 'idle'
    end
    local lowerBodyAnim = anim.getActiveGroup(omwself, anim.BONE_GROUP.LowerBody)
    local isMoving = lowerBodyAnim and (lowerBodyAnim:find('walk') or lowerBodyAnim:find('run') or lowerBodyAnim:find('sneak') or lowerBodyAnim:find('turn'))
    if P.wasMoving and not isMoving then
        I.AnimationController.playBlendedAnimation(idleAnim, { 
            loops = 1000000000,
            priority = {
                [anim.BONE_GROUP.LeftArm] = 0,
                [anim.BONE_GROUP.RightArm] = 0,
                [anim.BONE_GROUP.Torso] = 0,
                [anim.BONE_GROUP.LowerBody] = anim.PRIORITY.Scripted
            },
            blendMask = anim.BLEND_MASK.LowerBody
        })
        P.idleTimer = 0.25
    elseif P.idleTimer and P.idleTimer > 0 then
        P.idleTimer = P.idleTimer - dt
        if P.idleTimer <= 0 then
            anim.cancel(omwself, idleAnim)
            P.idleTimer = nil
        end
    end

    P.wasMoving = isMoving
end

function P.resetVfx()
    if instrumentData[P.instrument] then
        anim.removeVfx(omwself, 'BO_Instrument')
        anim.addVfx(omwself, instrumentData[P.instrument].path, {
            boneName = instrumentData[P.instrument].boneName,
            vfxId = 'BO_Instrument',
            loop = true,
            useAmbientLight = false
        })
    end
end

function P.resetAnim()
    if instrumentData[P.instrument] then
        anim.cancel(omwself, instrumentData[P.instrument].anim)
        P.startAnim(instrumentData[P.instrument].anim)
    end
end

function P.handlePerformEvent(data)
    local song = data.song
    P.musicTime = data.time + (core.getRealTime() - data.realTime)
    P.bpm = song.tempo * song.tempoMod
    P.performanceType = data.perfType

    -- Check if time sig is compound and if so, adjust BPM so animation matches
    if song.timeSig[1] % 3 == 0 and song.timeSig[1] > 3 then
        P.bpm = P.bpm * 4 / 3
    end

    local iData = instrumentData[data.instrument]
    if not iData then return end
    P.instrument = data.instrument
    P.resetVfx()
    P.resetAnim()
    omwself.enableAI(omwself, false)

    local songInfo = P.knownSongs[song.id]
    if not songInfo then
        P:addKnownSong(song)
    end

    P.maxConfidence = P.knownSongs[song.id].partConfidences[data.part.index] or 0
    if P.maxConfidence ~= P.maxConfidence then
        P.maxConfidence = 0 -- NaN check
    end
    P.maxConfidenceGrowth = (1 - math.pow(P.maxConfidence, 1/3)) * 0.8 -- Fast growth at low confidence, slow growth at high confidence

    if not P.playing then
        P.currentConfidence = P.maxConfidence
        P.currentDensity = 0
        P.noteIntervals = {}
        P.overallNoteEvents = {}
        P.lastNoteTime = nil
        P.xpGain = 0
        P.levelGain = 0
    end

    P.playing = true
    P.currentSong = song
    P.currentPart = data.part
end

function P.handleStopEvent(data)
    anim.removeVfx(omwself, 'BO_Instrument')
    anim.cancel(omwself, instrumentData[P.instrument].anim)
    if animData[P.instrument] then
        for a, _ in pairs(animData[P.instrument]) do 
            anim.cancel(omwself, a)
        end
    end
    P.playing = false
    P.instrument = nil
    omwself.enableAI(omwself, true)

    local successCount = 0
    for _, success in ipairs(P.overallNoteEvents) do
        if success then
            successCount = successCount + 1
        end
    end
    local successRate = math.pow(successCount / #P.overallNoteEvents, 2)
    local diff = successRate - P.maxConfidence
    local maxGrowth = util.clamp(P.maxConfidenceGrowth * data.completion, 0, P.maxConfidenceGrowth)
    local oldConfidence = P.maxConfidence
    local mod = util.clamp(diff, -maxGrowth, maxGrowth)
    P:modSongConfidence(P.currentSong.id, P.currentPart.index, mod)
    if omwself.type == types.Player then
        omwself:sendEvent('BC_GainConfidence', { songTitle = P.currentSong.title, partTitle = P.currentPart.title, oldConfidence = oldConfidence, newConfidence = P.knownSongs[P.currentSong.id].partConfidences[P.currentPart.index] })
    end
    if omwself.type == types.Player then
        core.sendGlobalEvent('BC_PlayerPerfSkillLog', { xpGain = P.xpGain, levelGain = P.levelGain, level = P.performanceSkill.level, xpCurr = P.performanceSkill.xp, xpReq = P:getPerformanceXPRequired() })
    end
    
    P.currentSong = nil
    P.currentPart = nil
end

function P.getNoteAccuracy()
    local density = P.currentDensity

    local difficultyFactor = util.clamp((density - easyDensity) / (hardDensity - easyDensity), 0, 1)
    local accuracy = math.pow(P.performanceSkill.level / 100, 1/2) * 1.1 - (difficultyFactor * 0.5) + (math.pow(P.currentConfidence, 1/2) * 0.5)

    return util.clamp(accuracy, 0, 1)
end

function P.playNote(note, velocity)
    local success = true
    local pitch = 1.0
    local volume = velocity
    if math.random() > P.getNoteAccuracy() then
        pitch = 1.0 + (math.random() * 0.2 - 0.1) -- Random pitch shift between -10% and +10%
        volume = volume * 0.5 + math.random() * (volume)
        success = false
    end
    local noteName = Song.noteNumberToName(note)
    local filePath = 'sound\\Bardcraft\\samples\\' .. P.instrument .. '\\' .. P.instrument .. '_' .. noteName .. '.wav'
    core.sound.playSoundFile3d(filePath, omwself, { volume = volume, pitch = pitch })
    return success
end

function P.stopNote(note)
    local noteName = Song.noteNumberToName(note)
    local filePath = 'sound\\Bardcraft\\samples\\' .. P.instrument .. '\\' .. P.instrument .. '_' .. noteName .. '.wav'
    core.sound.stopSoundFile3d(filePath, omwself)
end

function P.handleNoteEvent(data)
    if omwself.type.isDead(omwself) then return false end
    if P.lastNoteTime then
        local interval = data.time - P.lastNoteTime
        local weight = 1
        if interval < 0.05 then
            weight = 0.1
        end
        table.insert(P.noteIntervals, { interval = interval, weight = weight })
        if #P.noteIntervals > P.maxHistory then
            table.remove(P.noteIntervals, 1)
        end

        -- Calculate moving average density (notes per second)
        local totalInterval = 0
        local totalWeight = 0
        for _, v in ipairs(P.noteIntervals) do
            totalInterval = totalInterval + v.interval * v.weight
            totalWeight = totalWeight + v.weight
        end
        local avgInterval = totalInterval / totalWeight
        P.currentDensity = 1 / avgInterval
    end
    P.lastNoteTime = data.time
    local success = P.playNote(data.note, data.velocity)
    if success then
        local gain = (P.maxConfidence - P.currentConfidence) / P.maxConfidence * 0.04
        P.currentConfidence = math.min(P.currentConfidence + gain, P.maxConfidence)
        local xp = 1 * xpMult[P.performanceType]
        P.levelGain = P.levelGain + P:addPerformanceXP(xp)
        P.xpGain = P.xpGain + xp
    else
        local loss = P.currentConfidence / P.maxConfidence * 0.04
        P.currentConfidence = math.max(P.currentConfidence - loss, 0)
    end
    table.insert(P.overallNoteEvents, success)
    core.sendGlobalEvent('BC_PerformerNoteHandled', { success = success, part = P.currentPart })
    return success
end

function P.handleConductorEvent(data)
    local success
    if data.type == 'PerformStart' then
        P.handlePerformEvent(data)
    elseif data.type == 'PerformStop' and P.playing then
        P.handleStopEvent(data)
    else
        if data.type == 'NoteEvent' then
            success = P.handleNoteEvent(data)
        elseif data.type == 'NoteEndEvent' and data.stopSound then
            P.stopNote(data.note)
        end
        if P.instrument and instrumentData[P.instrument] and instrumentData[P.instrument].eventHandler then
            data.time = core.getRealTime()
            instrumentData[P.instrument].eventHandler(data)
        end
    end
    return success
end

function P:onFrame()
end

return P