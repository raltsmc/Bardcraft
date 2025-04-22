-- Simple MIDI file parser
-- Supporting note on/off events, instrument changes, and pitch information

local vfs = require('openmw.vfs')

local sampleFolder = 'sound\\BardicOverhaul\\samples\\'
local midiFolder = 'midi\\'

-- Basic bit operations since Lua 5.1 doesn't have them built-in
local bit = {}

function bit.lshift(x, by)
    return x * 2 ^ by
end

function bit.rshift(x, by)
    return math.floor(x / 2 ^ by)
end

function bit.band(a, b)
    local result = 0
    local bitval = 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then
            result = result + bitval
        end
        bitval = bitval * 2
        a = math.floor(a / 2)
        b = math.floor(b / 2)
    end
    return result
end

function bit.bor(a, b)
    local result = 0
    local bitval = 1
    while a > 0 or b > 0 do
        if a % 2 == 1 or b % 2 == 1 then
            result = result + bitval
        end
        bitval = bitval * 2
        a = math.floor(a / 2)
        b = math.floor(b / 2)
    end
    return result
end

-- MIDI Parser class
local MidiParser = {}
MidiParser.__index = MidiParser

MidiParser.instrumentProfiles = {
    [24] = {
        name = "Lute",
        loop = false,
        sustain = true,
        volume = 1.0,
    },
    [79] = {
        name = "Ocarina",
        loop = true,
        sustain = false,
        volume = 0.5,
    },
    [116] = {
        name = "Drum",
        loop = false,
        sustain = true,
        volume = 0.35,
    }
}

function MidiParser.getInstrumentProfile(id)
    return MidiParser.instrumentProfiles[id] or MidiParser.instrumentProfiles[24]
end

function MidiParser.new(filename)
    local self = setmetatable({}, MidiParser)
    self.filename = filename
    self.tracks = {}
    self.format = 0
    self.numTracks = 0
    self.division = 0
    self.events = {}
    self.tempoEvents = {}
    return self
end

-- Read variable-length quantity
function MidiParser:readVLQ(file)
    local value = 0
    local byte = file:read(1):byte()
    value = bit.band(byte, 0x7F)

    while bit.band(byte, 0x80) ~= 0 do
        byte = file:read(1):byte()
        value = bit.lshift(value, 7)
        value = bit.bor(value, bit.band(byte, 0x7F))
    end

    return value
end

-- Read a specific number of bytes from file and return as number
function MidiParser:readBytes(file, count)
    local bytes = file:read(count)
    local value = 0

    for i = 1, #bytes do
        value = bit.lshift(value, 8)
        value = value + bytes:byte(i)
    end

    return value
end

-- Parse a MIDI file
function MidiParser:parse()
    if not vfs.fileExists(self.filename) then
        return false, "File does not exist: " .. self.filename
    end

    local file = vfs.open(self.filename)
    if not file then
        return false, "Could not open file: " .. self.filename
    end

    -- Read header chunk
    local headerChunk = file:read(4)
    if headerChunk ~= "MThd" then
        file:close()
        return false, "Not a valid MIDI file (header not found)"
    end

    -- Read header length
    local headerLength = self:readBytes(file, 4)
    if headerLength ~= 6 then
        file:close()
        return false, "Invalid header length"
    end

    -- Read format type
    self.format = self:readBytes(file, 2)

    -- Read number of tracks
    self.numTracks = self:readBytes(file, 2)

    -- Read time division
    self.division = self:readBytes(file, 2)

    -- Process each track
    for trackNum = 1, self.numTracks do
        local track = {}
        track.events = {}

        -- Check for track header
        local trackHeader = file:read(4)
        if trackHeader ~= "MTrk" then
            file:close()
            return false, "Invalid track header in track " .. trackNum
        end

        -- Read track length
        local trackLength = self:readBytes(file, 4)
        local trackEnd = file:seek("cur") + trackLength

        -- Process events in track
        local absoluteTime = 0
        local runningStatus = 0

        while file:seek("cur") < trackEnd do
            local event = {}

            -- Read delta time
            local deltaTime = self:readVLQ(file)
            absoluteTime = absoluteTime + deltaTime
            event.time = absoluteTime

            -- Read event type
            local statusByte = file:read(1):byte()

            -- Check for running status
            if statusByte < 0x80 then
                -- This is actually data, not a status byte
                file:seek("cur", -1)
                statusByte = runningStatus
            else
                runningStatus = statusByte
            end

            -- Get event type and channel
            local eventType = bit.rshift(statusByte, 4)
            local channel = bit.band(statusByte, 0x0F)

            event.channel = channel

            -- Process different event types
            if eventType == 0x8 then
                -- Note Off
                event.type = "noteOff"
                event.note = file:read(1):byte()
                event.velocity = file:read(1):byte()
                table.insert(track.events, event)
            elseif eventType == 0x9 then
                -- Note On
                event.type = "noteOn"
                event.note = file:read(1):byte()
                event.velocity = file:read(1):byte()

                -- Note On with velocity 0 is actually a Note Off
                if event.velocity == 0 then
                    event.type = "noteOff"
                end

                table.insert(track.events, event)
            elseif eventType == 0xC then
                -- Program Change (instrument)
                event.type = "programChange"
                event.program = file:read(1):byte()
                table.insert(track.events, event)
            elseif eventType == 0xF then
                -- Meta Event or System Exclusive
                if statusByte == 0xFF then
                    -- Meta Event
                    local metaType = file:read(1):byte()
                    local metaLength = self:readVLQ(file)

                    if metaType == 0x2F then
                        -- End of Track
                        file:seek("cur", metaLength)
                        break
                    elseif metaType == 0x51 then
                        -- Tempo Change Event
                        if metaLength == 3 then
                            -- Tempo is stored as 3 bytes representing microseconds per quarter note
                            local tempoByte1 = file:read(1):byte()
                            local tempoByte2 = file:read(1):byte()
                            local tempoByte3 = file:read(1):byte()

                            local microsecondsPerQuarter = (tempoByte1 * 65536) + (tempoByte2 * 256) + tempoByte3
                            local bpm = 60000000 / microsecondsPerQuarter

                            local tempoEvent = {
                                type = "setTempo",
                                time = absoluteTime,
                                track = trackNum,
                                microsecondsPerQuarter = microsecondsPerQuarter,
                                bpm = bpm
                            }

                            table.insert(self.tempoEvents, tempoEvent)
                        else
                            -- Skip malformed tempo event
                            file:seek("cur", metaLength)
                        end
                    else
                        -- Skip other meta events
                        file:seek("cur", metaLength)
                    end
                elseif statusByte == 0xF0 or statusByte == 0xF7 then
                    -- SysEx Event - skip
                    local length = self:readVLQ(file)
                    file:seek("cur", length)
                end
            else
                -- Skip other events with 2 data bytes
                file:seek("cur", 2)
            end
        end

        table.insert(self.tracks, track)
    end

    table.sort(self.tempoEvents, function(a, b) return a.time < b.time end)

    file:close()
    return true
end

-- Get all notes from the MIDI file
function MidiParser:getNotes()
    local notes = {}

    for trackNum, track in ipairs(self.tracks) do
        for _, event in ipairs(track.events) do
            if event.type == "noteOn" or event.type == "noteOff" then
                table.insert(notes, {
                    type = event.type,
                    time = event.time,
                    track = trackNum,
                    channel = event.channel,
                    note = event.note,
                    velocity = event.velocity
                })
            end
        end
    end

    -- Sort notes by time
    table.sort(notes, function(a, b)
        if a.time == b.time then
            return (a.type == "noteOff" and b.type == "noteOn")
        end
        return a.time < b.time
    end)

    return notes
end

-- Get all program changes (instrument changes)
function MidiParser:getInstruments()
    local instruments = {}

    for trackNum, track in ipairs(self.tracks) do
        for _, event in ipairs(track.events) do
            if event.type == "programChange" then
                table.insert(instruments, {
                    time = event.time,
                    track = trackNum,
                    channel = event.channel,
                    program = event.program
                })
            end
        end
    end

    -- Sort instrument changes by time
    table.sort(instruments, function(a, b) return a.time < b.time end)

    return instruments
end

-- Get tempo information
function MidiParser:getTempoEvents()
    return self.tempoEvents
end

-- Get the initial tempo (or default 120 BPM if none specified)
function MidiParser:getInitialTempo()
    if #self.tempoEvents > 0 then
        return self.tempoEvents[1].bpm
    else
        return 120 -- Default standard MIDI tempo is 120 BPM
    end
end

-- Convert ticks to seconds at a given tempo
function MidiParser:ticksToSeconds(ticks, bpm)
    -- Calculate microseconds per tick
    local microsecondsPerQuarterNote = 60000000 / bpm
    local microsecondsPerTick = microsecondsPerQuarterNote / self.division

    -- Convert to seconds
    return (ticks * microsecondsPerTick) / 1000000
end

-- Convert seconds to ticks at a given tempo
function MidiParser:secondsToTicks(seconds, bpm)
    -- Calculate ticks per microsecond
    local microsecondsPerQuarterNote = 60000000 / bpm
    local ticksPerMicrosecond = self.division / microsecondsPerQuarterNote

    -- Convert seconds to ticks
    return seconds * 1000000 * ticksPerMicrosecond
end

-- Get BPM at a specific tick position, considering tempo changes
function MidiParser:getTempoAtTime(tickPosition)
    if #self.tempoEvents == 0 then
        return 120 -- Default 120 BPM if no tempo events
    end

    -- Find the latest tempo change before or at the current position
    local currentTempo = self.tempoEvents[1].bpm -- Start with first tempo

    for _, tempoEvent in ipairs(self.tempoEvents) do
        if tempoEvent.time <= tickPosition then
            currentTempo = tempoEvent.bpm
        else
            break -- Stop when we reach future tempo events
        end
    end

    return currentTempo
end

-- Convert a MIDI note number to note name (C4, D#5, etc.)
function MidiParser.noteNumberToName(noteNumber)
    local noteNames = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
    local octave = math.floor(noteNumber / 12)
    local noteName = noteNames[(noteNumber % 12) + 1]
    return noteName .. octave
end

function MidiParser.noteNumberToFile(noteNumber, instrument)
    local noteName = MidiParser.noteNumberToName(noteNumber)
    local instrumentName = MidiParser.getInstrumentProfile(instrument).name
    local filePath = sampleFolder .. instrumentName .. "\\" .. instrumentName .. '_' .. noteName
    return filePath
end

-- Usage example
function parseMidiFile(filename)
    filename = midiFolder .. filename
    local parser = MidiParser.new(filename)
    local success, errorMsg = parser:parse()

    if not success then
        print("Error parsing MIDI file: " .. errorMsg)
        return
    end

    print("MIDI Format: " .. parser.format)
    print("Number of tracks: " .. parser.numTracks)
    print("Time division: " .. parser.division .. " ticks per quarter note")

    -- Display tempo information
    local tempoEvents = parser:getTempoEvents()
    if #tempoEvents > 0 then
        print("\nTempo Events:")
        for i, tempo in ipairs(tempoEvents) do
            print(string.format("Time: %d ticks, BPM: %.2f", tempo.time, tempo.bpm))
        end
        print("Initial Tempo: " .. parser:getInitialTempo() .. " BPM")
    else
        print("\nNo tempo events found. Using default 120 BPM.")
    end

    print("\nNotes:")
    local notes = parser:getNotes()
    for i, note in ipairs(notes) do
        if i <= 20 then -- Show only first 20 notes
            local noteName = MidiParser.noteNumberToName(note.note)
            print(string.format("Time: %d, Track: %d, Channel: %d, %s: %s (vel: %d)",
                note.time, note.track, note.channel, note.type, noteName, note.velocity))
        end
    end

    print("\nInstrument Changes:")
    local instruments = parser:getInstruments()
    for _, instrument in ipairs(instruments) do
        print(string.format("Time: %d, Track: %d, Channel: %d, Program: %d",
            instrument.time, instrument.track, instrument.channel, instrument.program))
    end

    return parser
end

-- Return the module
return {
    MidiParser = MidiParser,
    parseMidiFile = parseMidiFile
}
