local core = require('openmw.core')
local world = require('openmw.world')
local types = require('openmw.types')

local configGlobal = require('scripts.Bardcraft.config.global')
local Song = require('scripts.Bardcraft.util.song').Song
local Cell = require('scripts.Bardcraft.cell')

local actorData = {}
local playingCount = 0

local playing = false
local song = nil
local performers = {}
local partToPerformer = {}

local function resyncActor(performer)
    local part = performer.part
    local instrumentName = Song.getInstrumentProfile(part.instrument).name
    performer.actor:sendEvent('BO_ConductorEvent', { type = 'PerformStart', time = song:ticksToSeconds(song.playbackTickCurr), realTime = core.getRealTime(), instrument = instrumentName, song = song, part = part })
end

local function resyncAllActors()
    for _, performerData in ipairs(performers) do
        resyncActor(performerData)
    end
end

local function start()
    if not song then return end
    print("Starting performance (" .. song.title .. ")")
    playing = true
    resyncAllActors()

    for _, performerData in ipairs(performers) do
        partToPerformer[performerData.part.index] = performerData.actor
    end

    song.loopCount = 0
end

local function stop()
    if song then
        song:resetPlayback()
    end
    playing = false
    for _, performerData in ipairs(performers) do
        performerData.actor:sendEvent('BO_ConductorEvent', { type = 'PerformStop' })
    end
end

local function tickPerformance(dt)
    if not playing or not song then return end

    local loopStart = song.loopBars[1] * song.resolution * (song.timeSig[1] / song.timeSig[2]) * 4
    if song.playbackTickCurr == loopStart then
        resyncAllActors()
    end

    if not song:tickPlayback(dt,
    function(filePath, velocity, instrument, note, part, id)
        local profile = Song.getInstrumentProfile(instrument)
        velocity = velocity * 2 * profile.volume / 127
        local actor = partToPerformer[part]
        if not actor then return end
        if actor.type == types.Player then velocity = velocity / 2 end
        actor:sendEvent('BO_ConductorEvent', { type = 'NoteEvent', time = song:ticksToSeconds(song.playbackTickCurr), note = note, id = id, filePath = filePath, velocity = velocity })
    end,
    function(filePath, instrument, note, part, id)
        local profile = Song.getInstrumentProfile(instrument)
        local actor = partToPerformer[part]
        if not actor then return end
        actor:sendEvent('BO_ConductorEvent', { type = 'NoteEndEvent', note = note, id = id, filePath = filePath, stopSound = not profile.sustain })
    end) then
        stop()
        return
    end

    -- Check if it's a new bar, and if so alert all actors
    local ticksPerBar = song.resolution * (song.timeSig[1] / song.timeSig[2]) * 4
    local introTicks = song.loopBars[1] * ticksPerBar
    local barProgress = (song.playbackTickCurr - introTicks) % ticksPerBar
    if barProgress < (song.playbackTickPrev - introTicks) % ticksPerBar then
        for _, performerData in ipairs(performers) do
            performerData.actor:sendEvent('BO_ConductorEvent', { type = 'NewBar', bar = math.floor(song.playbackTickCurr / ticksPerBar) })
        end
    end
end


local function update(dt)
    tickPerformance(dt)
end

return {
    engineHandlers = {
        onUpdate = update,
    },
    eventHandlers = {
        BO_StartPerformance = function(data)
            if not playing then
                if not data.performers or #data.performers == 0 then return end
                local hasPublican = Cell.cellHasPublican(world.players[1].cell)
                song = data.song
                setmetatable(song, Song)

                local perfList = data.performers
                local activeActors = world.activeActors
                for i, performer in ipairs(data.performers) do
                    for _, actor in ipairs(activeActors) do
                        if actor.id == performer.actorId then
                            perfList[i].actor = actor
                            break
                        end
                    end
                    perfList[i].part = song:getPart(performer.part)
                end
                performers = perfList
                song:resetPlayback()
                start()
            else
                stop()
            end
        end,
    }
}