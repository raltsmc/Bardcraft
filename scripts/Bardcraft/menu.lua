local storage = require('openmw.storage')
local vfs = require('openmw.vfs')

local MIDI = require('scripts.Bardcraft.util.midi')
local Song = require('scripts.Bardcraft.util.song')

local function parseAll()
    local bardData = storage.playerSection('Bardcraft')
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
                    local song = Song.fromMidiParser(parser)
                    midiSongs[fileName] = song
                end
            end
        end
    end
    for _, song in pairs(midiSongs) do
        print(song.sourceFile or '')
        table.insert(storedSongs, song)
    end
    bardData:set('songs/preset', storedSongs)
end

return {
    engineHandlers = {
        onInit = parseAll,
        --onLoad = parseAll,
    }
}