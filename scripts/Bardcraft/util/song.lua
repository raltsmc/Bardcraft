local drumChannelMappings = {
    [35] = 46,
    [36] = 47,
    [37] = 49,
    [38] = 48,
    [39] = 41,
    [40] = 51,
    [41] = 46,
    [42] = 38,
    [43] = 48,
    [44] = 37,
    [45] = 48,
    [46] = 37,
    [47] = 46,
    [48] = 47,
    [49] = 45,
    [50] = 48,
    [51] = 45,
    [52] = 44,
    [57] = 44,
}

local instrumentProfiles = {
    [24] = {
        name = "Lute",
        loop = false,
        sustain = true,
        transpose = true,
        volume = 1.0,
    },
    [73] = {
        name = "BassFlute",
        loop = true,
        sustain = false,
        transpose = true,
        volume = 1,
    },
    [79] = {
        name = "Ocarina",
        loop = true,
        sustain = false,
        transpose = true,
        volume = 1,
    },
    [116] = {
        name = "Drum",
        loop = false,
        sustain = true,
        transpose = false,
        volume = 1,
    },
    [0] = {
        name = "None",
        loop = false,
        sustain = false,
        transpose = false,
        volume = 1,
    },
}

local instrumentMappings = {
    { instr = 24, low = 0, high = 15 }, -- Piano and Chromatic Percussion maps to Lute
    { instr = 79, low = 16, high = 23 }, -- Organ maps to Ocarina
    { instr = 24, low = 24, high = 39 }, -- Guitar and Bass maps to Lute
    { instr = 73, low = 40, high = 45 }, -- Strings maps to BassFlute
    { instr = 24, low = 46, high = 46 }, -- Harp maps to Lute
    { instr = 116, low = 47, high = 47 }, -- Timpani maps to Drum
    { instr = 73, low = 48, high = 51 }, -- Low Ensemble maps to BassFlute
    { instr = 79, low = 52, high = 54 }, -- High Ensemble maps to Ocarina
    { instr = 24, low = 55, high = 55 }, -- Orchestra Hit maps to Lute
    { instr = 79, low = 56, high = 56 }, -- Trumpet maps to Ocarina
    { instr = 73, low = 57, high = 58 }, -- Trombone and Tuba maps to BassFlute
    { instr = 79, low = 59, high = 63 }, -- Rest of Brass maps to Ocarina
    { instr = 79, low = 64, high = 65 }, -- Soprano and Alto Sax maps to Ocarina
    { instr = 73, low = 66, high = 67 }, -- Tenor and Bari Sax maps to BassFlute
    { instr = 79, low = 68, high = 68 }, -- Oboe maps to Ocarina
    { instr = 73, low = 69, high = 70 }, -- English Horn and Bassoon maps to BassFlute
    { instr = 79, low = 71, high = 72 }, -- Clarinet and Piccolo maps to Ocarina
    { instr = 73, low = 73, high = 73 }, -- Flute maps to BassFlute
    { instr = 79, low = 74, high = 74 }, -- Recorder maps to Ocarina
    { instr = 73, low = 75, high = 77 }, -- Pan Flute, Blown Bottle and Shakuhachi maps to BassFlute
    { instr = 79, low = 78, high = 79 }, -- Whistle and Ocarina maps to Ocarina
    { instr = 24, low = 80, high = 87 }, -- Synth Lead maps to Lute
    { instr = 73, low = 88, high = 95 }, -- Synth Pad maps to BassFlute
    { instr = 0, low = 96, high = 103 }, -- Synth Effects maps to nothing (ignore them)
    { instr = 24, low = 104, high = 111 }, -- Ethnic maps to Lute
    { instr = 116, low = 112, high = 119 }, -- Percussive maps to Drum
    { instr = 0, low = 120, high = 127 }, -- Sound Effects maps to nothing (ignore them)
}

local function getInstrumentMapping(instrument)
    instrument = instrument or 0
    if instrumentProfiles[instrument] then
        return instrument
    end
    -- Use binary search
    local low, high = 1, #instrumentMappings
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local mapping = instrumentMappings[mid]
        if instrument < mapping.low then
            high = mid - 1
        elseif instrument > mapping.high then
            low = mid + 1
        else
            return mapping.instr
        end
    end
    return 0
end

local function mapDrumNote(note)
    local mappedNote = drumChannelMappings[note]
    if mappedNote then
        return mappedNote
    end
    return 46
end

local Part = {}
Part.__index = Part

function Part.new(instrument, title)
    local self = setmetatable({}, Part)
    self.instrument = instrument or 0
    self.title = title or instrumentProfiles[getInstrumentMapping(instrument)].name
    return self
end

local Song = {}
Song.__index = Song

Song.playbackTickPrev = 0
Song.playbackTickCurr = 0
Song.playbackNoteIndex = 1

function Song.new(title, desc, tempo, timeSig)
    local self = setmetatable({}, Song)
    self.title = title or 'New Song'
    self.desc = desc or 'No description'
    self.tempo = tempo or 120
    self.timeSig = timeSig or {4, 4}
    self.notes = {}
    self.parts = {}
    self.lengthBars = 4
    self.loopBars = {0, 4}
    self.resolution = 96
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
        if note.channel == 9 then
            note.note = mapDrumNote(note.note)
        end
        local noteData = {
            id = id,
            type = note.type,
            note = note.note,
            velocity = note.velocity,
            track = note.track,
            instrument = (note.channel == 9 and 116) or getInstrumentMapping(parser.instruments[note.channel]),
            time = math.floor(note.time * self.resolution / parser.division),
        }
        id = id + 1
        table.insert(self.notes, noteData)
    end
    local lastNoteTime = self.notes[#self.notes].time / 96
    local quarterNotesPerBar = self.timeSig[1] * (4 / self.timeSig[2])
    local barCount = math.ceil(lastNoteTime / quarterNotesPerBar)
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

function Song:resetPlayback()
    self.playbackTickPrev = 0
    self.playbackTickCurr = 0
    self.playbackNoteIndex = 1
end

function Song.getInstrumentProfile(instrument)
    local profile = instrumentProfiles[instrument]
    if not profile then
        return {
            name = "Lute",
            loop = false,
            sustain = true,
            transpose = true,
            volume = 1.0,
        }
    end
    return profile
end

function Song.getInstrumentProfiles()
    return instrumentProfiles
end

function Song:secondsToTicks(seconds)
    local ticksPerSecond = (self.resolution * self.tempo) / 60
    return seconds * ticksPerSecond
end

function Song:tickToBeat(tick)
    local beatsPerQuarterNote = 4 / self.timeSig[2]
    local ticksPerQuarterNote = self.resolution
    local ticksPerBeat = ticksPerQuarterNote * beatsPerQuarterNote
    local beat = (tick - 1) / ticksPerBeat
    return beat
end

function Song.noteNumberToName(noteNumber)
    local noteNames = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
    local octave = math.floor(noteNumber / 12) - 1
    local noteName = noteNames[(noteNumber % 12) + 1]
    return noteName .. octave
end

function Song:tickPlayback(dt, noteOnHandler, noteOffHandler)
    self.playbackTickPrev = self.playbackTickCurr
    self.playbackTickCurr = self.playbackTickCurr + self:secondsToTicks(dt)
    local noteEvents = self.notes
    while self.playbackNoteIndex <= #noteEvents do
        local event = noteEvents[self.playbackNoteIndex]
        if event.time > self.playbackTickCurr then
            break
        end
        if event.time >= self.playbackTickPrev then
            local noteNumber = event.note + 1
            local noteName = self.noteNumberToName(noteNumber - 1)
            local profile = self.getInstrumentProfile(event.instrument)
            local filePath = 'sound\\Bardcraft\\samples\\' .. profile.name .. '\\' .. profile.name .. '_' .. noteName .. '.wav'
            if event.type == 'noteOn' and event.velocity > 0 then
                noteOnHandler(filePath, event.velocity, event.instrument, event.note)
            elseif not profile.sustain and (event.type == 'noteOff' or (event.type == 'noteOn' and event.velocity == 0)) then
                noteOffHandler(filePath, event.instrument)
            end
        end
        self.playbackNoteIndex = self.playbackNoteIndex + 1
    end
    local bars = self.lengthBars
    local lengthInTicks = bars * self.resolution * 4 * (self.timeSig[1] / self.timeSig[2])
    if self.playbackNoteIndex > #noteEvents or self.playbackTickCurr > lengthInTicks then
        self.playbackNoteIndex = 1
        -- Get loop start point
        local loopBars = self.loopBars
        if loopBars and #loopBars == 2 then
            local loopStart = loopBars[1] * self.resolution * 4 * (self.timeSig[1] / self.timeSig[2])
            self.playbackTickCurr = loopStart
        else
            self.playbackTickCurr = 0
        end
        self.playbackTickPrev = self.playbackTickCurr
    end
end

-- Song serialization and deserialization

function Song:encode()
	-- Table to JSON
	local function jsonEncode(tbl)
		local function escapeStr(s)
			return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
				return string.format('\\u%04x', c:byte())
			end) .. '"'
		end

		local function encode(val)
			if type(val) == "string" then return escapeStr(val)
			elseif type(val) == "number" or type(val) == "boolean" then return tostring(val)
			elseif type(val) == "table" then
				local isArray = #val > 0
				local out = {}
				if isArray then
					for _, v in ipairs(val) do table.insert(out, encode(v)) end
					return "[" .. table.concat(out, ",") .. "]"
				else
					for k, v in pairs(val) do
						table.insert(out, escapeStr(k) .. ":" .. encode(v))
					end
					return "{" .. table.concat(out, ",") .. "}"
				end
			else
				error("unsupported type in jsonEncode: " .. type(val))
			end
		end

		return encode(tbl)
	end

	-- String to Base64
	local function toBase64(data)
		local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
		return ((data:gsub('.', function(x)
			local r, b = '', x:byte()
			for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i-1) > 0 and '1' or '0') end
			return r
		end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
			if #x < 6 then return '' end
			local c = 0
			for i = 1, 6 do c = c + (x:sub(i,i) == '1' and 2^(6-i) or 0) end
			return b:sub(c+1, c+1)
		end) .. ({ '', '==', '=' })[#data % 3 + 1])
	end

    local noteStrings = {}
    for _, note in ipairs(self.notes) do
        table.insert(noteStrings, string.format('%d|%s|%d|%d|%d|%d|%d', note.id, note.type, note.note, note.velocity, note.track, note.instrument, note.time))
    end
    local notesString = table.concat(noteStrings, ',')

	local songData = {
        id = self.id,
		title = self.title,
		desc = self.desc,
		tempo = self.tempo,
		timeSig = self.timeSig,
		lengthBars = self.lengthBars,
		loopBars = self.loopBars,
		resolution = self.resolution,
		notes = notesString,
	}

	return toBase64(jsonEncode(songData))
end

function Song.decode(encoded)
	-- Base64 to string
	local function fromBase64(data)
		local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
		data = string.gsub(data, '[^'..b..'=]', '')
		return (data:gsub('.', function(x)
			if x == '=' then return '' end
			local r, f = '', (b:find(x) - 1)
			for i = 6, 1, -1 do r = r .. (f % 2^i - f % 2^(i-1) > 0 and '1' or '0') end
			return r
		end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
			if #x ~= 8 then return '' end
			local c = 0
			for i = 1, 8 do c = c + (x:sub(i,i) == '1' and 2^(8-i) or 0) end
			return string.char(c)
		end))
	end

	-- JSON to table
	local function jsonDecode(str)
		local pos = 1
		local function skip() while str:sub(pos,pos):match('%s') do pos = pos + 1 end end
		local function parse()
			skip()
			local c = str:sub(pos,pos)
			if c == '"' then
				pos = pos + 1
				local s, out = "", ""
				while true do
					local ch = str:sub(pos, pos)
					if ch == '"' then pos = pos + 1 return out
					elseif ch == '\\' then
						local esc = str:sub(pos+1, pos+1)
						local map = { ['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f', n='\n', r='\r', t='\t' }
						out = out .. (map[esc] or esc)
						pos = pos + 2
					else
						out = out .. ch
						pos = pos + 1
					end
				end
			elseif c == '{' then
				pos = pos + 1
				local obj = {}
				skip()
				if str:sub(pos,pos) == '}' then pos = pos + 1 return obj end
				while true do
					skip()
					local key = parse()
					skip()
					pos = pos + 1 -- skip :
					obj[key] = parse()
					skip()
					local nextChar = str:sub(pos,pos)
					if nextChar == '}' then pos = pos + 1 return obj
					else pos = pos + 1 end
				end
			elseif c == '[' then
				pos = pos + 1
				local arr = {}
				skip()
				if str:sub(pos,pos) == ']' then pos = pos + 1 return arr end
				while true do
					table.insert(arr, parse())
					skip()
					local nextChar = str:sub(pos,pos)
					if nextChar == ']' then pos = pos + 1 return arr
					else pos = pos + 1 end
				end
			elseif c:match('[%d%-]') then
				local start = pos
				while str:sub(pos,pos):match('[%d%+%-eE%.]') do pos = pos + 1 end
				return tonumber(str:sub(start, pos - 1))
			elseif str:sub(pos,pos+3) == "true" then pos = pos + 4 return true
			elseif str:sub(pos,pos+4) == "false" then pos = pos + 5 return false
			elseif str:sub(pos,pos+3) == "null" then pos = pos + 4 return nil
			else error("Bad JSON at " .. pos) end
		end

		return parse()
	end

	local decoded = fromBase64(encoded)
	local data = jsonDecode(decoded)

    local notes = {}
    for noteString in string.gmatch(data.notes, '([^,]+)') do
        local id, type, note, velocity, track, instrument, time = noteString:match('(%d+)|([^|]+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)')
        table.insert(notes, {
            id = tonumber(id),
            type = type,
            note = tonumber(note),
            velocity = tonumber(velocity),
            track = tonumber(track),
            instrument = tonumber(instrument),
            time = tonumber(time),
        })
    end

	local song = Song.new(data.title, data.desc, data.tempo, data.timeSig)
    song.id = data.id
	song.lengthBars = data.lengthBars
	song.loopBars = data.loopBars
	song.resolution = data.resolution
	song.notes = notes

	return song
end

return Song