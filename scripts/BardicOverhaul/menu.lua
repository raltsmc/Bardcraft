local storage = require('openmw.storage')
local vfs = require('openmw.vfs')

local MIDI = require('scripts.BardicOverhaul.util.midi')
local Song = require('scripts.BardicOverhaul.util.song')

local function parseAll()
    local midiSongs = {}
    for fileName in vfs.pathsWithPrefix(MIDI.MidiParser.midiFolder) do
        if fileName:sub(-4) == ".mid" then
            fileName = string.match(fileName, "([^/]+)$")
            local parser = MIDI.parseMidiFile(fileName)
            if parser then
                local song = Song.fromMidiParser(parser)
                midiSongs[fileName] = song
            end
        end
    end
    local bardData = storage.playerSection('BardicOverhaul')
    bardData:set('songs/preset', {})
    bardData:set('songs/custom', {})
    local storedSongs = bardData:getCopy('songs/preset') or {}
    for _, song in pairs(midiSongs) do
        table.insert(storedSongs, song)
    end
    bardData:set('songs/preset', storedSongs)
end

return {
    engineHandlers = {
        onInit = parseAll,
        onLoad = parseAll,
    }
}