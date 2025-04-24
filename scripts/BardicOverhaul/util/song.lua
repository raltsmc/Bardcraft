local Song = {}
Song.__index = Song

function Song.new(title, desc, tempo, timeSig)
    local self = setmetatable({}, Song)
    self.title = title or 'New Song'
    self.desc = desc or 'No description'
    self.tempo = tempo or 120
    self.timeSig = timeSig or {4, 4}
    self.notes = {}
    self.lengthBars = 4
    self.loopBars = {0, 4}
    self.id = self.title .. '_' .. os.time() + math.random(10000)
    return self
end

function Song.fromMidiParser(parser)
    local fileName = string.match(parser.filename, "([^\\]+)%.mid$")
    local title = fileName:gsub("%f[%a].", string.upper)
    local self = Song.new(
        title,
        'Imported from MIDI file',
        parser:getInitialTempo(),
        {parser:getInitialTimeSignature()}
    )
    --self.timeSig[1], self.timeSig[2] = parser:getInitialTimeSignature()
    self.sourceFile = string.match(parser.filename, "([^\\]+)$")
    local id = 1
    for _, note in ipairs(parser:getNotes()) do
        local noteData = {
            id = id,
            type = note.type,
            note = note.note,
            velocity = note.velocity,
            track = note.track,
            instrument = parser.instruments[note.channel] or 24,
            time = note.time / parser.division, -- in quarter notes
        }
        id = id + 1
        table.insert(self.notes, noteData)
    end
    local lastNoteTime = self.notes[#self.notes].time
    local quarterNotesPerBar = self.timeSig[1] * (4 / self.timeSig[2])
    local barCount = math.ceil(lastNoteTime / quarterNotesPerBar)
    print("bar count: " .. barCount .. " (" .. self.id .. ")")
    self.lengthBars = barCount
    self.loopBars = {0, barCount}
    return self
end

function Song:setTitle(title)
    self.title = title
end
function Song:setDescription(desc)
    self.desc = desc
end
function Song:setTempo(tempo)
    self.tempo = tempo
end
function Song:setTimeSignature(timeSig)
    self.timeSig = timeSig
end
    
return Song