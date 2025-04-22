local core = require('openmw.core')
local types = require('openmw.types')
local world = require('openmw.world')
local storage = require('openmw.storage')

local configGlobal = require('scripts.BardicOverhaul.config.global')
local MIDI = require('scripts.BardicOverhaul.util.midi')

local actorData = {}
local playingCount = 0

local playing = false

local time = 0
local parser = nil
local bpm = 0
local midiTickCurr = 0
local midiTickPrev = 0
local currentNoteIndex = 1
local currentTempoIndex = 1
local currentProgramIndex = 1
local notes = nil
local tempoChanges = nil
local programChanges = nil
local programs = nil

local function initPrograms()
    programs = {}
    for i = 0, 15 do
        programs[i] = 0
    end
end

local function detectBPM()
    world.players[1]:sendEvent("DetectBPMStart")
end

local function updateBPM(data)
end

local function getDagoth()
    local actors = world.activeActors
    dagothReverb = false
    for _, actor in ipairs(actors) do
        if actor and actor.type == types.Creature and (actor.recordId == "dagoth_ur_1" or actor.recordId == "dagoth_ur_2") then
            dagothReverb = actor.recordId == "dagoth_ur_2"
            return actor
        end
    end
    return nil
end

local function updatePlayingCount()
    playingCount = 0
    for _, actor in ipairs(world.activeActors) do
        if actorData[actor.id] then
            playingCount = playingCount + 1
        end
    end
end

local function handleStartSoundOnActor(data)
    local dagoth = getDagoth()

    local actualTime = data.desiredTime
    if realTimeOffset ~= -1 then
        actualTime = realTimeOffset % configGlobal.customMusic.customMusicLength
    elseif dagoth ~= nil then
        actualTime = 0
    end

    local startDagoth = dagoth and not actorData[dagoth.id]
    if startDagoth and data.actor.type ~= types.Player then
        data.volume = configGlobal.technical.dagothKeytarVolume
    end

    local t1 = core.getRealTime()
    core.sound.playSoundFile3d(data.soundKey, data.actor, { timeOffset = actualTime, volume = data.volume, loop = true })
    local t2 = core.getRealTime()
    actualTime = actualTime + (t1 - t2)
    if startDagoth then
        core.sound.playSoundFile3d("Sound\\keytar\\dagoth-vocals.mp3", dagoth, { timeOffset = actualTime, volume = configGlobal.technical.dagothKeytarVolume, loop = true })
        actorData[dagoth.id] = {
            soundKey = "Sound\\keytar\\dagoth-vocals.mp3",
            volume = configGlobal.technical.dagothKeytarVolume
        }
    end

    actorData[data.actor.id] = {
        soundKey = data.soundKey,
        volume = data.volume
    }

    realTimeOffset = actualTime
    gameTimeOffset = actualTime

    resetTimer = nil
    updatePlayingCount()

    data.actor:sendEvent('SendKeytarTime', { time = actualTime, realTime = core.getRealTime() })

    playing = true
    world.players[1]:sendEvent('RecheckAmbient')
end

local function handleStopSoundOnActor(data)
    core.sound.stopSoundFile3d(data.soundKey, data.actor)
    actorData[data.actor.id] = nil

    updatePlayingCount()

    local dagoth = getDagoth()
    if dagoth ~= nil and actorData[dagoth.id] and playingCount == 1 then
        core.sound.stopSoundFile3d("Sound\\keytar\\dagoth-vocals.mp3", dagoth)
        actorData[dagoth.id] = nil
        playingCount = 0
    end

    if playingCount == 0 then
        if resetTimer == nil then
            resetTimer = configGlobal.technical.musicResetTime
        end
        dagothReverb = false
    end

    if not dagothReverb then
        core.sound.stopSoundFile3d("Sound\\keytar\\dagoth-reverb.mp3", world.players[1])
    end

    world.players[1]:sendEvent('RecheckAmbient')
end

local function resyncActor(actor, instrumentName)
    actor:sendEvent('BO_Perform', { time = time, realTime = core.getRealTime(), instrument = instrumentName, bpm = bpm })
end

local function stop()
    playing = false
end

local actors

local function start()
    if not parser then return end
    print("Starting performance (" .. parser.filename .. ")")
    playing = true
    bpm = parser:getInitialTempo()
    print("Initial BPM: " .. bpm)
    time = 0
    midiTickCurr = 0
    midiTickPrev = 0
    currentNoteIndex = 1
    currentTempoIndex = 1
    currentProgramIndex = 1
    actors = {}
    actors[1] = world.players[1]
    actors[2] = world.activeActors[2]
    actors[3] = world.activeActors[3]
    resyncActor(actors[1], 'Lute')
    resyncActor(actors[3], 'Drum')
    resyncActor(actors[2], 'Ocarina')
end

local instrumentProfiles = {}

local function doNoteEvent(type, noteName, velocity, instrument)
    if not instrumentProfiles[instrument] then
        instrumentProfiles[instrument] = parser.getInstrumentProfile(instrument)
    end
    local profile = instrumentProfiles[instrument]
    velocity = velocity * 2 * profile.volume / 127
    local actor = actors[2]
    if instrument == 24 then actor = actors[1]
    elseif instrument == 116 then actor = actors[3] end
    local fileName = parser.noteNumberToFile(noteName, instrument or 0)
    if type == 'noteOn' then
        core.sound.playSoundFile3d(fileName .. ".wav", actor, { timeOffset = 0, volume = velocity, loop = false })--instrumentProfiles[instrument].loop })
        --print("Playing note: " .. string.match(fileName, "([^\\]+)$") .. string.format(" with volume %.3f", velocity))
    elseif type == 'noteOff' and not profile.sustain then
        core.sound.stopSoundFile3d(fileName .. ".wav", actor)
    end
end

local transpose = 0

local function tickPerformance(dt)
    if not playing or parser == nil or notes == nil then
        stop()
        return
    end

    time = time + dt

    while currentTempoIndex < #tempoChanges do
        local nextTempoEvent = tempoChanges[currentTempoIndex + 1]
        if midiTickCurr >= nextTempoEvent.time then
            currentTempoIndex = currentTempoIndex + 1
            bpm = nextTempoEvent.bpm
            --print("new bpm: " .. bpm)
        else
            break
        end
    end

    midiTickPrev = midiTickCurr
    midiTickCurr = midiTickCurr + parser:secondsToTicks(dt, bpm)

    while currentProgramIndex <= #programChanges do
        local programEvent = programChanges[currentProgramIndex]
        if programEvent.time >= midiTickCurr then
            break
        end
        if programEvent.time >= midiTickPrev then
            programs[programEvent.channel] = programEvent.program
        end

        currentProgramIndex = currentProgramIndex + 1
    end

    while currentNoteIndex <= #notes do
        local note = notes[currentNoteIndex]
        if note.time >= midiTickCurr then
            break
        end
        if note.time >= midiTickPrev then
            doNoteEvent(note.type, note.note + transpose, note.velocity, programs[note.channel])
        end

        currentNoteIndex = currentNoteIndex + 1
    end
    if currentNoteIndex > #notes then
        start()
        midiTickCurr = 48
        midiTickPrev = 48
    end
end


local function update(dt)
    tickPerformance(dt)
end

local function init()
    if not parser then
        parser = MIDI.parseMidiFile('greensleeves.mid')
        notes = parser:getNotes()
        tempoChanges = parser:getTempoEvents()
        programChanges = parser:getInstruments()
        initPrograms()
    end
end

return {
    engineHandlers = {
        onUpdate = update,
        onLoad = init,
    },
    eventHandlers = {
        Bardic_StartPerformance = function(data)
            if not playing then
                init()
                start()
            end
        end,
    }
}