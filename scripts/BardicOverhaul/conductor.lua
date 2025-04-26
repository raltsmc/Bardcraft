local core = require('openmw.core')
local world = require('openmw.world')

local configGlobal = require('scripts.BardicOverhaul.config.global')
local Song = require('scripts.BardicOverhaul.util.song')

local actorData = {}
local playingCount = 0

local playing = false
local song = nil
local actors = {}
local actorInstruments = {
    [1] = 'Lute',
    [2] = 'BassFlute',
    [3] = 'Drum',
    [4] = 'Ocarina'
}
local actorInstrumentsReverse = {
    Lute = 1,
    BassFlute = 2,
    Drum = 3,
    Ocarina = 4
}

local function resyncActor(actor, instrumentName)
    actor:sendEvent('BO_Perform', { time = 0, realTime = core.getRealTime(), instrument = instrumentName, bpm = song.tempo, timeSig = song.timeSig })
end

local function start()
    if not song then return end
    print("Starting performance (" .. song.title .. ")")
    playing = true
    actors = {}
    actors[1] = world.players[1]
    actors[2] = world.activeActors[2]
    actors[3] = world.activeActors[3]
    actors[4] = world.activeActors[4]
    for i, actor in ipairs(actors) do
        resyncActor(actor, actorInstruments[i])
    end
end

local function tickPerformance(dt)
    if not playing or not song then return end

    local loopStart = song.loopBars[1] * song.resolution * (song.timeSig[1] / song.timeSig[2]) * 4
    if song.playbackTickCurr == loopStart then
        for i, actor in ipairs(actors) do
            resyncActor(actor, actorInstruments[i])
        end
    end

    song:tickPlayback(dt,
    function(filePath, velocity, instrument, note)
        local profile = Song.getInstrumentProfile(instrument)
        velocity = velocity * 2 * profile.volume / 127
        local actor = actors[actorInstrumentsReverse[profile.name]]
        if not actor then return end
        core.sound.playSoundFile3d(filePath, actor, { timeOffset = 0, volume = velocity, loop = false })
        actor:sendEvent('BO_ConductorEvent', { type = 'NoteEvent', note = note })
    end,
    function(filePath, instrument)
        local profile = Song.getInstrumentProfile(instrument)
        local actor = actors[actorInstrumentsReverse[profile.name]]
        if not actor then return end
        core.sound.stopSoundFile3d(filePath, actor)
    end)

    -- Check if it's a new bar, and if so alert all actors
    local ticksPerBar = song.resolution * (song.timeSig[1] / song.timeSig[2]) * 4
    local introTicks = song.loopBars[1] * ticksPerBar
    local barProgress = (song.playbackTickCurr - introTicks) % ticksPerBar
    if barProgress < (song.playbackTickPrev - introTicks) % ticksPerBar then
        for _, actor in ipairs(actors) do
            actor:sendEvent('BO_ConductorEvent', { type = 'NewBar', bar = math.floor(song.playbackTickCurr / ticksPerBar) })
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
                song = data.song
                setmetatable(song, Song)
                song:resetPlayback()
                start()
            else
                if song then
                    song:resetPlayback()
                end
                playing = false
            end
        end,
        BO_EditorPause = function()
            world.pause('BO_Editor')
        end,
        BO_EditorUnpause = function()
            world.unpause('BO_Editor')
        end,
    }
}