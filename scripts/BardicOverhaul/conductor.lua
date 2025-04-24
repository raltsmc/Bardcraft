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
local timeSig = {4, 4}
local ticksPerBar = 0
local introNotes = 0.5
local midiTickCurr = 0
local midiTickPrev = 0
local currentNoteIndex = 1
local currentTempoIndex = 1
local currentTimeSigIndex = 1
local currentProgramIndex = 1
local notes = nil
local tempoChanges = nil
local timeSigChanges = nil
local programChanges = nil
local programs = nil

local function initPrograms()
    programs = {}
    for i = 0, 15 do
        programs[i] = 0
    end
end

local function resyncActor(actor, instrumentName)
    actor:sendEvent('BO_Perform', { time = time, realTime = core.getRealTime(), instrument = instrumentName, bpm = bpm, timeSig = timeSig })
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
    timeSig[1], timeSig[2] = parser:getInitialTimeSignature()
    ticksPerBar = (parser.division * 4 * timeSig[1]) / timeSig[2]
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
    actors[4] = world.activeActors[4]
    resyncActor(actors[1], 'Lute')
    resyncActor(actors[3], 'Drum')
    resyncActor(actors[4], 'Ocarina')
    resyncActor(actors[2], 'BassFlute')
    parser:printEverything()
end

local instrumentProfiles = {}

local function doNoteEvent(type, noteName, velocity, instrument)
    if not instrumentProfiles[instrument] then
        instrumentProfiles[instrument] = parser.getInstrumentProfile(instrument)
    end
    local profile = instrumentProfiles[instrument]
    velocity = velocity * 2 * profile.volume / 127
    local actor = actors[1]
    if profile.name == "Ocarina" then actor = actors[4]
    elseif profile.name == "Drum" then actor = actors[3]
    elseif profile.name == "BassFlute" then actor = actors[2] end
    local fileName = parser.noteNumberToFile(noteName, instrument or 0)
    if type == 'noteOn' then
        core.sound.playSoundFile3d(fileName .. ".wav", actor, { timeOffset = 0, volume = velocity, loop = false })--instrumentProfiles[instrument].loop })
        actor:sendEvent('BO_ConductorEvent', { type = 'NoteEvent', note = noteName })
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

    while currentTimeSigIndex < #timeSigChanges do
        local nextTimeSigEvent = timeSigChanges[currentTimeSigIndex + 1]
        if midiTickCurr >= nextTimeSigEvent.time then
            currentTimeSigIndex = currentTimeSigIndex + 1
            timeSig[1], timeSig[2] = nextTimeSigEvent.numerator, nextTimeSigEvent.denominator
            ticksPerBar = (parser.division * 4 * timeSig[1]) / timeSig[2]
            print("new time sig: " .. timeSig[1] .. "/" .. timeSig[2])
        else
            break
        end
    end

    midiTickPrev = midiTickCurr
    midiTickCurr = midiTickCurr + parser:secondsToTicks(dt, bpm)

    -- Check if it's a new bar, and if so alert all actors
    local barProgress = (midiTickCurr - introNotes * parser.division) % ticksPerBar
    if barProgress < (midiTickPrev - introNotes * parser.division) % ticksPerBar then
        --print("New bar: " .. math.floor(midiTickCurr / ticksPerBar))
        for _, actor in ipairs(actors) do
            actor:sendEvent('BO_ConductorEvent', { type = 'NewBar', bar = math.floor(midiTickCurr / ticksPerBar) })
        end
    end

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
            local transposeAmt = parser.getInstrumentProfile(programs[note.channel]).transpose and transpose or 0
            doNoteEvent(note.type, note.note + transposeAmt, note.velocity, programs[note.channel])
        end

        currentNoteIndex = currentNoteIndex + 1
    end
    if currentNoteIndex > #notes then
        start()
        midiTickCurr = introNotes * parser.division
        midiTickPrev = introNotes * parser.division
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
        timeSigChanges = parser:getTimeSignatureEvents()
        programChanges = parser:getInstruments()
        initPrograms()
    end
end

return {
    engineHandlers = {
        onUpdate = update,
        onLoad = init,
        onInit = init,
    },
    eventHandlers = {
        BO_StartPerformance = function(data)
            if not playing then
                init()
                start()
            end
        end,
    }
}