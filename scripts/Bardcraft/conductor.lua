local core = require('openmw.core')
local world = require('openmw.world')
local types = require('openmw.types')
local storage = require('openmw.storage')

local configGlobal = require('scripts.Bardcraft.config.global')
local Song = require('scripts.Bardcraft.util.song').Song
local Cell = require('scripts.Bardcraft.cell')
local Feedback = require('scripts.Bardcraft.feedback')

local l10n = core.l10n('Bardcraft')

local playing = false
local song = nil
local performers = {}
local partToPerformer = {}

local performance = {
    noteEvents = {},
    quality = 0,
    density = 0,
    complexity = 0,
    time = 0,
}
local performanceEvalTimer = 0
local performanceEvalInterval = 1.0 -- seconds

local performanceRandomEventInterval = { 3.0, 5.0 }
local performanceRandomEventTimer = performanceRandomEventInterval[1]

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

local function start(data)
    if not song then return end
    print("Starting performance (" .. song.title .. ")")
    playing = true
    resyncAllActors()

    partToPerformer = {}
    for _, performerData in ipairs(performers) do
        partToPerformer[performerData.part.index] = performerData.actor
    end

    song.loopCount = 1
    performance.noteEvents = {}
    performance.quality = 0
    performance.density = 0
    performance.complexity = 0
    performance.time = 0
    performance.type = data.type
    performance.streetName = data.streetName
    performance.streetType = data.streetType
    performance.cell = world.players[1].cell
    performance.startGameTime = core.getGameTime()
    performanceEvalTimer = 0
    performanceRandomEventTimer = performanceRandomEventInterval[1]
end

local logAwait = nil

local function stop()
    if song then
        song:resetPlayback()
    end
    playing = false
    for _, performerData in ipairs(performers) do
        performerData.actor:sendEvent('BO_ConductorEvent', { type = 'PerformStop', completion = song and (performance.time / song:lengthInSeconds()) or 0 })
    end

    local performanceLog = {
        type = performance.type,
        quality = performance.quality,
        density = performance.density,
        complexity = performance.complexity,
        time = performance.time,
        cell = performance.streetName or performance.cell.name,
        gameTime = performance.startGameTime,
    }

    local cellBlurb = l10n('UI_Blurb_' .. performanceLog.cell)
    if cellBlurb ~= ('UI_Blurb_' .. performanceLog.cell) then
        performanceLog.cellBlurb = cellBlurb
    end

    if performanceLog.type == Song.PerformanceType.Street then
        performanceLog.cell = l10n('UI_PerfLog_StreetsOf'):gsub('%%{city}', performanceLog.cell)
    end

    local player = world.players[1]
    if player then
        if performance.type == Song.PerformanceType.Tavern then
            local publican = Cell.getPublican(performance.cell)
            local context = {
                perfQuality = performance.quality,
                perfDensity = performance.density,
                race = publican and types.NPC.record(publican).race or '',
            }
            local feedbackTree = storage.globalSection('Bardcraft'):getCopy('feedback')
            if not feedbackTree then
                print('No feedback tree found')
                return
            end
            local feedback = Feedback.findMatchingNode(feedbackTree.publican, context)
            if feedback then
                local choice = l10n(feedback.choices[math.random(1, #feedback.choices)])
                local effects = feedback.effects

                performanceLog.publicanComment = choice
                performanceLog.effects = effects
            end
        end
        logAwait = performanceLog
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

local function tickJudge(dt)
    performance.time = performance.time + dt
    if performanceEvalTimer > performanceEvalInterval then
        performanceEvalTimer = 0
        local partDensities = {}
        local totalSuccessCount = 0
        local totalNoteCount = 0
        for _, partNoteEvents in pairs(performance.noteEvents) do
            local noteCount = #partNoteEvents
            if noteCount > 0 then
                local successCount = 0
                for _, event in ipairs(partNoteEvents) do
                    if event then successCount = successCount + 1 end
                end
                partDensities[#partDensities + 1] = noteCount / performance.time
                totalSuccessCount = totalSuccessCount + successCount
                totalNoteCount = totalNoteCount + noteCount
            end
        end
        if totalNoteCount > 0 then
            performance.quality = math.pow(totalSuccessCount / totalNoteCount, 2) * 100
            -- For density, take the highest part density; for complexity, sum them all up
            local maxDensity = 0
            local totalDensity = 0
            for _, density in ipairs(partDensities) do
                if density > maxDensity then maxDensity = density end
                totalDensity = totalDensity + density
            end
            performance.density = maxDensity
            performance.complexity = totalDensity
        end
    else
        performanceEvalTimer = performanceEvalTimer + dt
    end
end

local function doRandomEvent()
    local player = world.players[1]
    if not player then return end

    local function giveItem(item, count)
        local itemObj = world.createObject(item, count or 1)
        itemObj:moveInto(types.Actor.inventory(player))
    end

    if performance.quality < 20 and math.random() < (0.2 * (20 - performance.quality) / 20) then
        -- Throw a drink at the player
        local caught = math.random() < 0.3
        local item = 'Potion_Local_Brew_01'
        if caught then
            giveItem(item)
        end
        player:sendEvent('BC_RandomEvent', { type = 'ThrownItem', item = item, caught = caught })
    elseif performance.quality < 35 and math.random() < (0.3 * (35 - performance.quality) / 35) then
        -- Throw bread at the player
        local caught = math.random() < 0.5
        local item = 'ingred_bread_01'
        if caught then
            giveItem(item)
        end
        player:sendEvent('BC_RandomEvent', { type = 'ThrownItem', item = item, caught = caught })
    elseif performance.quality < 60 and math.random() < 0.4 then
        -- Play a cough sound
        local cough = math.random(1, 2)
        local soundFile = 'sound/Bardcraft/crowd/cough' .. cough .. '.wav'
        if not core.sound.isSoundFilePlaying(soundFile, player) then
            core.sound.playSoundFile3d(soundFile, player, { volume = 0.1 + 0.4 * (60 - performance.quality) / 60 })
        end
    elseif performance.quality < 40 and math.random() < 0.05 then
        -- Play a retching sound
        local soundFile = 'sound/Bardcraft/crowd/hurl.wav'
        if not core.sound.isSoundFilePlaying(soundFile, player) then
            core.sound.playSoundFile3d(soundFile, player, { volume = 0.1 + 0.4 * (40 - performance.quality) / 40 })
        end
    end
end

local lastCrowdBoo = 0
local lastCrowdClap = 0

local function doCrowdNoise()
    if performance.quality < 35 then
        local crowdNoiseNum = math.random(2, 4)
        if crowdNoiseNum <= lastCrowdBoo then
            crowdNoiseNum = crowdNoiseNum - 1
        end
        lastCrowdBoo = crowdNoiseNum
        local soundFile = 'sound/Bardcraft/crowd/boo' .. crowdNoiseNum .. '.wav'
        if not core.sound.isSoundFilePlaying(soundFile, world.players[1]) then
            core.sound.playSoundFile3d(soundFile, world.players[1], { volume = 0.1 + 0.4 * (35 - performance.quality) / 35 })
        end
    elseif performance.quality > 90 and performance.density > 4 then
        local crowdNoiseNum = math.random(2, 4)
        if crowdNoiseNum <= lastCrowdClap then
            crowdNoiseNum = crowdNoiseNum - 1
        end
        lastCrowdClap = crowdNoiseNum
        local soundFile = 'sound/Bardcraft/crowd/clap' .. crowdNoiseNum .. '.wav'
        if not core.sound.isSoundFilePlaying(soundFile, world.players[1]) then
            core.sound.playSoundFile3d(soundFile, world.players[1], { volume = 0.1 + 0.4 * (performance.quality - 80) / 20 })
        end
    end
end

local function tickRandomEvents(dt)
    if performanceRandomEventTimer <= 0 then
        performanceRandomEventTimer = math.random() * (performanceRandomEventInterval[2] - performanceRandomEventInterval[1]) + performanceRandomEventInterval[1]
        doCrowdNoise()
        if math.random() < 0.5 then
            doRandomEvent()
        end
    else
        performanceRandomEventTimer = performanceRandomEventTimer - dt
    end
end


local function update(dt)
    if playing then
        tickPerformance(dt)
        tickJudge(dt)
        tickRandomEvents(dt)
    end
end

return {
    engineHandlers = {
        onUpdate = update,
    },
    eventHandlers = {
        BO_StartPerformance = function(data)
            if not playing then
                if not data.performers or #data.performers == 0 then return end
                
                local type, streetName, streetType = Cell.canPerformHere(world.players[1].cell, data.type)
                if not type then
                    print('Cannot perform here')
                    return
                elseif type == Song.PerformanceType.Tavern then
                    print('Performing in tavern')
                elseif type == Song.PerformanceType.Street then
                    print('Performing on the street in ' .. streetName .. ' (' .. streetType .. ')')
                elseif type == Song.PerformanceType.Practice then
                    print('Practicing')
                end
                data.type = type
                data.streetName = streetName
                data.streetType = streetType

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
                start(data)
            else
                stop()
            end
        end,
        BC_PerformerNoteHandled = function(data)
            if not performance.noteEvents[data.part.index] then
                performance.noteEvents[data.part.index] = {}
            end
            table.insert(performance.noteEvents[data.part.index], data.success)
        end,
        BC_PlayerPerfSkillLog = function(data)
            if logAwait then
                logAwait.xpGain = data.xpGain
                logAwait.level = data.level
                logAwait.levelGain = data.levelGain
                logAwait.xpCurr = data.xpCurr
                logAwait.xpReq = data.xpReq
                world.players[1]:sendEvent('BC_PerformanceLog', logAwait)
                logAwait = nil
            end
        end,
    }
}