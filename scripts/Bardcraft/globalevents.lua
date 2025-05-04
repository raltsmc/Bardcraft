local world = require('openmw.world')
local types = require('openmw.types')
local storage = require('openmw.storage')
local vfs = require('openmw.vfs')
local markup = require('openmw.markup')

local MIDI = require('scripts.Bardcraft.util.midi')
local Song = require('scripts.Bardcraft.util.song').Song

local function parseAll()
    local metadataPath = 'midi/metadata.yaml'
    local exists = vfs.fileExists(metadataPath)
    local metadata = exists and markup.loadYaml(metadataPath) or {
        midiData = {}
    }
    if not exists then
        print("WARNING: metadata.yaml missing")
    end

    local bardData = storage.globalSection('Bardcraft')
    --bardData:set('songs/preset', nil) -- Clear the old data
    local storedSongs = bardData:getCopy('songs/preset') or {}

    local midiSongs = {}
    for fileName in vfs.pathsWithPrefix(MIDI.MidiParser.midiFolder) do
        if fileName:sub(-4) == ".mid" then
            fileName = string.match(fileName, "([^/]+)$")

            local alreadyParsed = false
            for _, song in pairs(storedSongs) do
                if song.sourceFile == fileName then
                    alreadyParsed = true
                    break
                end
            end

            if not alreadyParsed then
                local parser = MIDI.parseMidiFile(fileName)
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
    if metadata and metadata.sheetMusicMappings then
        bardData:set('sheetmusic', metadata.sheetMusicMappings)
    end
end

return {
    engineHandlers = {
        --onInit = parseAll,
    },
    eventHandlers = {
        BC_ThrowItem = function(data)
            local item = world.createObject(data.item, data.count or 1)
            item:moveInto(types.Actor.inventory(data.actor))
        end,
        BC_ConsumeItem = function(data)
            data.item:remove()
        end,
        BC_ParseMidis = function()
            parseAll()
        end,
    }
}