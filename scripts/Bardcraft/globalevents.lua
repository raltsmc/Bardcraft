local world = require('openmw.world')
local types = require('openmw.types')
local storage = require('openmw.storage')
local vfs = require('openmw.vfs')
local markup = require('openmw.markup')
local I = require('openmw.interfaces')

local MIDI = require('scripts.Bardcraft.util.midi')
local Song = require('scripts.Bardcraft.util.song').Song
local Data = require('scripts.Bardcraft.data')

local function parseAllPreset()
    local metadataPath = 'midi/preset/metadata.yaml'
    local exists = vfs.fileExists(metadataPath)
    local metadata = exists and markup.loadYaml(metadataPath) or {
        midiData = {}
    }
    if not exists then
        print("WARNING: metadata.yaml missing")
    end

    local bardData = storage.globalSection('Bardcraft')
    bardData:set('songs/preset', nil) -- Clear the old data
    local storedSongs = bardData:getCopy('songs/preset') or {}

    local midiSongs = {}
    for filePath in vfs.pathsWithPrefix(MIDI.MidiParser.presetFolder) do
        if filePath:sub(-4) == ".mid" then
            local fileName = string.match(filePath, "([^/]+)$")

            local alreadyParsed = false
            for _, song in pairs(storedSongs) do
                if song.sourceFile == fileName then
                    alreadyParsed = true
                    break
                end
            end

            if not alreadyParsed then
                local parser = MIDI.parseMidiFile(filePath)
                if parser then
                    local song = Song.fromMidiParser(parser, metadata.midiData[fileName])
                    midiSongs[fileName] = song
                end
            end
        end
    end
    for _, song in pairs(midiSongs) do
        table.insert(storedSongs, song)
    end
    bardData:set('songs/preset', storedSongs)

    local feedbackPath = 'scripts/Bardcraft/feedback.yaml'
    exists = vfs.fileExists(feedbackPath)
    local feedback = exists and markup.loadYaml(feedbackPath) or {}
    if not exists then
        print("WARNING: feedback.yaml missing")
    elseif feedback then
        bardData:set('feedback', feedback)
    end

    local venuesPath = 'scripts/Bardcraft/venues.yaml'
    exists = vfs.fileExists(venuesPath)
    local venues = exists and markup.loadYaml(venuesPath) or {}
    if not exists then
        print("WARNING: venues.yaml missing")
    elseif venues then
        bardData:set('venues', venues)
    end
end

local mwscriptQueue = {}

I.ItemUsage.addHandlerForType(types.Miscellaneous, function(item, actor)
    if actor.type ~= types.Player then return true end
    local record = item.type.record(item)
    for instr, _ in pairs(Data.SheathableInstruments) do
        for recordId, _ in pairs(Data.InstrumentItems[instr]) do
            if record.id == recordId then
                actor:sendEvent('BC_SheatheInstrument', { record = {
                    id = record.id,
                    model = record.model,
                } })
                return true
            end
        end
    end
    return true
end)

return {
    engineHandlers = {
        --onInit = parseAll,
        onUpdate = function()
            if #mwscriptQueue > 0 then
                for _, data in ipairs(mwscriptQueue) do
                    local item = data.object
                    local mwscript = world.mwscript.getLocalScript(item)
                    if mwscript then
                        mwscript.variables.hasbeenplayed = data.hasBeenPlayed or 0
                        mwscript.variables.songid = data.songId or 0
                    end
                end
                mwscriptQueue = {}
            end
        end
    },
    eventHandlers = {
        BC_GiveItem = function(data)
            local item = world.createObject(data.item, data.count or 1)
            item:moveInto(types.Actor.inventory(data.actor))
        end,
        BC_ConsumeItem = function(data)
            data.item:remove(data.count)
        end,
        BC_ParseMidis = function()
            parseAllPreset()
        end,
        BC_Trespass = function(data)
            I.Crimes.commitCrime(data.player, {
                type = types.Player.OFFENSE_TYPE.Trespassing,
            })
        end,
        BC_BookRead = function(data)
            local book = data.book
            if book then
                local mwscript = world.mwscript.getLocalScript(book)
                if not mwscript or mwscript.recordId ~= '_bcsheetmusic' then 
                    data.player:sendEvent('BC_BookReadResult', { id = book.recordId, success = true })
                    return 
                end
                if not mwscript.variables.hasbeenread or mwscript.variables.hasbeenread == 0 then
                    mwscript.variables.hasbeenread = 1
                    data.player:sendEvent('BC_BookReadResult', { id = book.recordId, success = true })
                else
                    data.player:sendEvent('BC_BookReadResult', { success = false })
                end
            end
        end,
        BC_ReplaceMusicBox = function(data)
            local object = data.object
            if data.object.type ~= types.Miscellaneous then return end
            if data.object.count < 1 then return end
            if not object.cell then return end

            local mwscript = world.mwscript.getLocalScript(object)
            local hasBeenPlayed = mwscript.variables.hasbeenplayed or 0
            local songId = mwscript.variables.songid or 0

            local activatorId = object.recordId .. '_a'
            local activator = world.createObject(activatorId, 1)
            activator:teleport(object.cell, object.position, object.rotation)
            activator:sendEvent('BC_MusicBoxInit', { hasBeenPlayed = hasBeenPlayed, songId = songId })
            object:remove()
        end,
        BC_MusicBoxPickup = function(data)
            local object = data.object
            if object.type ~= types.Activator then return end

            local itemId = object.recordId:sub(1, -3)
            local item = world.createObject(itemId, 1)

            table.insert(mwscriptQueue, {
                object = item,
                hasBeenPlayed = data.hasBeenPlayed or 0,
                songId = data.songId or 0,
            })

            item:moveInto(types.Actor.inventory(data.actor))
            object:remove()
        end,
    }
}