local util = require('openmw.util')
local vfs = require('openmw.vfs')

local MIDI = {}

MIDI.sampleFolder = 'sound\\BardicOverhaul\\samples'
MIDI.midiFolder = 'midi\\'

function MIDI.instrumentName(n)
    if n == 24 then
        return 'Lute'
    end
    return nil
end

function MIDI.pitchToNoteName(pitch)
    local noteNames = {
        'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'
    }
    local noteIndex = pitch % 12 + 1
    local octave = math.floor(pitch / 12) - 1
    local noteName = noteNames[noteIndex]
    return string.format('%s%d', noteName, octave)
end

function MIDI.pitchToFileName(pitch, instrument)
    local noteName = MIDI.pitchToNoteName(pitch)
    local instrumentName = MIDI.instrumentName(instrument)
    if instrumentName then
        return string.format('%s\\%s_%s.wav', MIDI.sampleFolder, instrumentName, noteName)
    else
        return nil
    end
end

local function readByte(f)
    return string.byte(f:read(1))
end

local function readUInt16(f)
    local b1, b2 = readByte(f), readByte(f)
    return b1 * 256 + b2
end

local function readUInt32(f)
    local b1, b2, b3, b4 = readByte(f), readByte(f), readByte(f), readByte(f)
    return b1 * 0x1000000 + b2 * 0x10000 + b3 * 0x100 + b4
end

local function readVLQ(f)
    local value = 0
    while true do
        local b = readByte(f)
        value = value * 128 + (b % 128)
        if b < 128 then break end
    end
    return value
end

-- Parses a track chunk into events
local function parseTrack(f, trackEnd)
    local events = {}
    local time = 0
    local lastStatus = nil
  
    while f:seek("cur", 0) < trackEnd do
      local delta = readVLQ(f)
      time = time + delta
  
      local status = readByte(f)
      if status < 0x80 then
        -- Running status: reuse previous status
        f:seek("cur", -1)
        status = lastStatus
      else
        lastStatus = status
      end
  
      local eventType = status & 0xF0
      local channel = status & 0x0F
  
      if eventType == 0x90 then
        local note = readByte(f)
        local velocity = readByte(f)
        table.insert(events, { time = time, type = "note_on", channel = channel, note = note, velocity = velocity })
      elseif eventType == 0x80 then
        local note = readByte(f)
        local velocity = readByte(f)
        table.insert(events, { time = time, type = "note_off", channel = channel, note = note, velocity = velocity })
      elseif eventType == 0xC0 then
        local program = readByte(f)
        table.insert(events, { time = time, type = "program_change", channel = channel, program = program })
      else
        -- Skip unsupported or meta events (simplified)
        local data1 = readByte(f)
        if eventType ~= status then
          -- Not a channel event: assume it's a meta or SysEx
          if status == 0xFF then
            local metaType = readByte(f)
            local len = readVLQ(f)
            f:seek("cur", len)
          elseif status == 0xF0 or status == 0xF7 then
            local len = readVLQ(f)
            f:seek("cur", len)
          else
            -- Unknown event, bail (better safe than sorry)
            break
          end
        else
          -- Channel event with 2 data bytes
          local data2 = readByte(f)
          -- We could store this, but skipping for now
        end
      end
    end
  
    return events
  end
  
  function MIDI.parseMidiFile(path)
    local f = vfs.open(MIDI.midiFolder .. path)
    if not f then return nil, "Cannot open file" end
  
    -- Read header chunk
    local header = f:read(4)
    if header ~= "MThd" then return nil, "Invalid MIDI header" end
  
    local headerLen = readUInt32(f)
    local format = readUInt16(f)
    local numTracks = readUInt16(f)
    local division = readUInt16(f)
  
    local midi = {
      format = format,
      division = division,
      tracks = {}
    }
  
    -- Skip any remaining header bytes
    if headerLen > 6 then f:seek("cur", headerLen - 6) end
  
    -- Read tracks
    for i = 1, numTracks do
      local chunkType = f:read(4)
      if chunkType ~= "MTrk" then return nil, "Expected MTrk" end
  
      local length = readUInt32(f)
      local trackEnd = f:seek("cur", 0) + length
      table.insert(midi.tracks, parseTrack(f, trackEnd))
      f:seek("set", trackEnd)
    end
  
    f:close()
    return midi
  end