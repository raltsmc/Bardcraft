local ui = require('openmw.ui')
local auxUi = require('openmw_aux.ui')
local I = require('openmw.interfaces')
local storage = require('openmw.storage')
local async = require('openmw.async')
local ambient = require('openmw.ambient')
local core = require('openmw.core')
local util = require('openmw.util')
local input = require('openmw.input')

local l10n = core.l10n('BardicOverhaul')

local Song = require('scripts.BardicOverhaul.util.song')

local Editor = {}

Editor.active = false
Editor.song = nil
Editor.songs = nil
Editor.state = nil
Editor.noteMap = nil

local function createPaddingTemplate(size)
    size = util.vector2(1, 1) * size
    return {
        type = ui.TYPE.Container,
        content = ui.content {
            {
                props = {
                    size = size,
                },
            },
            {
                external = { slot = true },
                props = {
                    position = size,
                    relativeSize = util.vector2(1, 1),
                },
            },
            {
                props = {
                    position = size,
                    relativePosition = util.vector2(1, 1),
                    size = size,
                },
            },
        }
    }
end

local headerTextures = {
    [1] = ui.texture {
        path = 'textures/menu_head_block_top_left_corner.dds',
    },
    [2] = ui.texture {
        path = 'textures/menu_head_block_top.dds',
    },
    [3] = ui.texture {
        path = 'textures/menu_head_block_top_right_corner.dds',
    },
    [4] = ui.texture {
        path = 'textures/menu_head_block_left.dds',
    },
    [5] = ui.texture {
        path = 'textures/menu_head_block_middle.dds',
    },
    [6] = ui.texture {
        path = 'textures/menu_head_block_right.dds',
    },
    [7] = ui.texture {
        path = 'textures/menu_head_block_bottom_left_corner.dds',
    },
    [8] = ui.texture {
        path = 'textures/menu_head_block_bottom.dds',
    },
    [9] = ui.texture {
        path = 'textures/menu_head_block_bottom_right_corner.dds',
    },
}

local function headerImage(i, tile, size)
    return {
        type = ui.TYPE.Image,
        props = {
            resource = headerTextures[i],
            size = size or util.vector2(0, 0),
            tileH = tile,
            tileV = false,
        },
        external = {
            grow = 1,
            stretch = 1,
        }
    }
end

local headerSection = {
    type = ui.TYPE.Flex,
    props = {
        horizontal = true,
    },
    external = {
        grow = 1,
        stretch = 1,
    },
    content = ui.content {
        {
            type = ui.TYPE.Flex,
            props = {
                autoSize = false,
                size = util.vector2(2, 20),
            },
            content = ui.content {
                headerImage(1, false, util.vector2(2, 2)),
                headerImage(4, false, util.vector2(2, 16)),
                headerImage(7, false, util.vector2(2, 2)),
            }
        },
        {
            type = ui.TYPE.Flex,
            props = {
                autoSize = false,
                size = util.vector2(0, 20),
            },
            content = ui.content {
                headerImage(2, true, util.vector2(0, 2)),
                headerImage(5, true, util.vector2(0, 16)),
                headerImage(8, true, util.vector2(0, 2)),
            },
            external = {
                grow = 1,
                stretch = 1,
            }
        },
        {
            type = ui.TYPE.Flex,
            props = {
                autoSize = false,
                size = util.vector2(2, 20),
            },
            content = ui.content {
                headerImage(3, false, util.vector2(2, 2)),
                headerImage(6, false, util.vector2(2, 16)),
                headerImage(9, false, util.vector2(2, 2)),
            }
        }
    }
}

local function uiButton(text, onClick)
    return {
        template = I.MWUI.templates.boxThick,
        content = ui.content {
            {
                template = I.MWUI.templates.padding,
                content = ui.content {
                    {
                        template = I.MWUI.templates.textNormal,
                        props = {
                            text = text,
                        },
                    }
                },
            },
        },
        events = {
            mouseClick = async:callback(function()
                if onClick then
                    onClick()
                end
            end),
        }
    }
end

local wrapperElement = nil
local screenSize = nil
local blockedKeySound = nil
local pianoRollScrollX = 0
local pianoRollScrollY = 0
local pianoRollFocused = false
local pianoRollWrapper = nil
local pianoRollEditorWrapper = nil
local pianoRoll = nil

local playback = false
local playbackTimer = 0
local toStop = {}

local function playAmbientWithDuration(fileName, duration, args)
    if ambient.isSoundFilePlaying(fileName) then
        ambient.stopSoundFile(fileName)
    end
    ambient.playSoundFile(fileName, args)
    table.insert(toStop, { stopAt = playbackTimer + duration, fileName = fileName })
end

local function updatePianoRoll()
    if not Editor.song then return end
    if not pianoRollWrapper then return end
    --[[local songManager = wrapperElement.layout.content[1].content[2].content.mainContent.content[2]
    local pianoRoll = songManager.content[3].content.pianoRoll]]
    pianoRollScrollY = util.clamp(pianoRollScrollY, -16 * 128, 0)
    pianoRollWrapper.layout.props.position = util.vector2(0, pianoRollScrollY)
    pianoRollEditorWrapper.layout.props.position = util.vector2(pianoRollScrollX, 0)
    pianoRollWrapper:update()
end

--[[local ZoomLevels = {
    [1] = 1.0,
    [2] = 2.0,
    [3] = 4.0,
}]]

-- This is a necessary optimization so that we don't have to render an image for each beat line (insanely taxing on performance)
local uiWholeNoteWidth = 256

local function getBeatWidth(denominator)
    return uiWholeNoteWidth / denominator
end

local uiTextures = {
    pianoRollKeys = ui.texture {
        path = 'textures/BardicOverhaul/ui/pianoroll-h.dds',
        offset = util.vector2(0, 0),
        size = util.vector2(96, 192),
    },
    pianoRollRows = ui.texture {
        path = 'textures/BardicOverhaul/ui/pianoroll-h.dds',
        offset = util.vector2(96, 0),
        size = util.vector2(4, 192),
    },
    pianoRollBeatLines = {}
}

for i = 0, 7 do
    local denom = math.pow(2, i)
    local yOffset = math.log(denom) / math.log(2)
    uiTextures.pianoRollBeatLines[denom] = ui.texture {
        path = 'textures/BardicOverhaul/ui/pianoroll-v.dds',
        offset = util.vector2(0, yOffset),
        size = util.vector2(getBeatWidth(denom), 1),
    }
end

local uiTemplates = {
    wrapper = {
        layer = 'Windows',
        template = I.MWUI.templates.boxTransparentThick,
        content = ui.content {
            {
                type = ui.TYPE.Flex,
                props = {
                    autoSize = false,
                    size = util.vector2(0, 0),
                },
                content = ui.content {
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            horizontal = true,
                            autoSize = false,
                            relativeSize = util.vector2(1, 0),
                            size = util.vector2(0, 20)
                        },
                        content = ui.content { 
                            headerSection, 
                            {
                                template = I.MWUI.templates.textNormal,
                                props = {
                                    text = '   ' .. l10n("UI_Title") .. '   ',
                                }
                            },
                            headerSection,
                        },
                    },
                    {
                        template = I.MWUI.templates.bordersThick,
                        external = {
                            grow = 1,
                            stretch = 1,
                        },
                        content = ui.content {
                            {
                                type = ui.TYPE.Flex,
                                name = 'mainContent',
                                props = {
                                    autoSize = false,
                                    relativeSize = util.vector2(1, 1),
                                },
                                content = ui.content {
                                    {
                                        template = I.MWUI.templates.borders,
                                        props = {
                                            size = util.vector2(0, 32),
                                            relativeSize = util.vector2(1, 0),
                                        },
                                        content = ui.content {
                                            {
                                                type = ui.TYPE.Flex,
                                                props = {
                                                    horizontal = true,
                                                    autoSize = false,
                                                    size = util.vector2(0, 32),
                                                    relativeSize = util.vector2(1, 0),
                                                },
                                                external = {
                                                    grow = 1,
                                                    stretch = 1,
                                                },
                                                content = ui.content {
                                                    uiButton("Song Manager"),
                                                    uiButton("Performance"),
                                                }
                                            },
                                        },
                                    },
                                }
                            },
                        }
                    },
                }
            }
        },
        props = {
            anchor = util.vector2(0.5, 0.5),
            relativePosition = util.vector2(0.5, 0.5),
        }
    },
    songManager = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            autoSize = false,
            relativeSize = util.vector2(1, 1),
        },
        content = ui.content {
            {
                template = I.MWUI.templates.borders,
                props = {
                    size = util.vector2(ui.screenSize().x * 5 / 32, 0),
                    relativeSize = util.vector2(0, 1),
                },
                content = ui.content {
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            autoSize = false,
                            relativeSize = util.vector2(1, 1),
                            size = util.vector2(0, -32),
                            grow = 1,
                            stretch = 1
                        },
                        content = ui.content {},
                    },
                },
            },
            {
                template = I.MWUI.templates.borders,
                props = {
                    size = util.vector2(ui.screenSize().x * 5 / 32, 0),
                    relativeSize = util.vector2(0, 1),
                },
                content = ui.content {
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            autoSize = false,
                            relativeSize = util.vector2(1, 1),
                            grow = 1,
                            stretch = 1
                        },
                        content = ui.content {},
                    },
                },
            },
            {
                template = I.MWUI.templates.borders,
                props = {
                    relativeSize = util.vector2(1, 1),
                },
                content = ui.content {
                    -- {
                    --     type = ui.TYPE.Flex,
                    --     name = 'pianoRoll',
                    --     props = {
                    --         horizontal = true,
                    --         autoSize = true
                    --     },
                    --     content = ui.content {},
                    -- },
                },
                events = {
                    focusGain = async:callback(function()
                        pianoRollFocused = true
                    end),
                    focusLoss = async:callback(function()
                        pianoRollFocused = false
                    end),
                }
            }
        }
    },
    labeledTextEdit = function(label, default, callback)
        return {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                autoSize = false,
                size = util.vector2(0, 32),
                relativeSize = util.vector2(1, 0),
                arrange = ui.ALIGNMENT.Center,
            },
            content = ui.content {
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = label,
                        textAlignV = ui.ALIGNMENT.Center,
                    },
                },
                {
                    template = createPaddingTemplate(4),
                },
                {
                    template = I.MWUI.templates.borders,
                    props = {
                        size = util.vector2(0, 32),
                        relativeSize = util.vector2(1, 0),
                    },
                    content = ui.content {
                        {
                            template = I.MWUI.templates.textEditLine,
                            props = {
                                text = default,
                                textAlignV = ui.ALIGNMENT.Center,
                                relativeSize = util.vector2(1, 1),
                            },
                            external = {
                                grow = 1,
                                stretch = 1,
                            },
                            events = {
                                textChanged = async:callback(function(text, self)
                                    if callback then
                                        callback(text, self)
                                    end
                                end),
                            }
                        }
                    }
                },
            }
        }
    end,
    pianoRollKeyboard = function(timeSig)
        local bar = {
            type = ui.TYPE.Widget,
            props = {
                size = util.vector2(96, 16 * 128),
            },
            content = ui.content {},
            events = {
                mouseMove = async:callback(function(e)
                    if e.button == 1 then
                        local noteIndex = math.floor((128 - (e.offset.y / 16)))
                        local octave = math.floor(noteIndex / 12) - 1
                        local noteNames = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
                        local noteName = noteNames[(noteIndex % 12) + 1]
                        local fileName = 'sound\\BardicOverhaul\\samples\\Lute\\Lute_' .. noteName .. octave .. '.wav'
                        if blockedKeySound ~= fileName then
                            ambient.playSoundFile(fileName)
                            blockedKeySound = fileName
                        end
                    end
                end),
                mousePress = async:callback(function(e)
                    if e.button == 1 then
                        local noteIndex = math.floor((128 - (e.offset.y / 16)))
                        local octave = math.floor(noteIndex / 12) - 1
                        local noteNames = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
                        local noteName = noteNames[(noteIndex % 12) + 1]
                        local fileName = 'sound\\BardicOverhaul\\samples\\Lute\\Lute_' .. noteName .. octave .. '.wav'
                        ambient.playSoundFile(fileName)
                        blockedKeySound = fileName
                    end
                end)
            }
        }
        bar.content:add({
            type = ui.TYPE.Image,
            props = {
                resource = uiTextures.pianoRollKeys,
                size = util.vector2(96, 16 * 128),
                tileH = false,
                tileV = true,
            },
        })
        bar.content:add({
            type = ui.TYPE.Flex,
            props = {
                autoSize = false,
                relativeSize = util.vector2(1, 1),
                relativePosition = util.vector2(0, 0),
                horizontal = false,
            },
            content = ui.content {}
        })
        local noteNames = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
        for i = 127, 0, -1 do
            local octave = math.floor(i / 12) - 1
            local noteName = noteNames[(i % 12) + 1]
            local isBlackKey = noteName:find("b") ~= nil
            bar.content[2].content:add({
                type = ui.TYPE.Widget,
                props = {
                    autoSize = false,
                    size = util.vector2(96, 16),
                },
                content = ui.content {
                    {
                        template = I.MWUI.templates.textNormal,
                        props = {
                            text = noteName .. octave,
                            textColor = isBlackKey and util.color.rgb(1, 1, 1) or util.color.rgb(0, 0, 0),
                            anchor = util.vector2(0, 0.5),
                            relativePosition = util.vector2(0, 0.5),
                        },
                    },
                }
            })
        end
        return bar
    end,
    pianoRollEditor = function()
        if not Editor.song then return {} end
        local timeSig = Editor.song.timeSig
        local barWidth = getBeatWidth(timeSig[2]) * timeSig[1] -- Width of a single bar based on time signature
        local totalWidth = barWidth * Editor.song.lengthBars -- Total width based on number of bars
        local editor = {
            type = ui.TYPE.Widget,
            props = {
                size = util.vector2(totalWidth, 16 * 128),
            },
            content = ui.content {
                {
                    type = ui.TYPE.Flex,
                    props = {
                        autoSize = false,
                        size = util.vector2(totalWidth, 16 * 128),
                    },
                    content = ui.content {},
                },
            },
            events = {
                mouseMove = async:callback(function(e)
                    if input.isMouseButtonPressed(2) then
                        local dx = input.getMouseMoveX()
                        local dy = input.getMouseMoveY()
                        if pianoRollFocused then
                            pianoRollScrollX = pianoRollScrollX + dx
                            pianoRollScrollY = pianoRollScrollY + dy
                            updatePianoRoll()
                        end
                    end
                end),
            }
        }

        editor.content[1].content:add({
            type = ui.TYPE.Image,
            props = {
                resource = uiTextures.pianoRollRows,
                size = util.vector2(util.clamp(totalWidth, 0, screenSize.x), 16 * 128),
                tileH = true,
                tileV = true,
                alpha = 0.06,
            },
        })

        for i = 1, Editor.song.lengthBars do
            -- Create a vertical line for each bar
            editor.content:add({
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture { path = 'white' },
                    size = util.vector2(1, 16 * 128),
                    tileH = false,
                    tileV = true,
                    alpha = 1,
                    position = util.vector2(i * barWidth, 0),
                },
            })
        end
        -- Add beat lines based on time signature
        local beatLines = uiTextures.pianoRollBeatLines[timeSig[2]]
        print(timeSig[2])
        if beatLines then
            editor.content:add({
                type = ui.TYPE.Image,
                props = {
                    resource = beatLines,
                    size = util.vector2(util.clamp(totalWidth, 0, screenSize.x), 16 * 128),
                    tileH = true,
                    tileV = true,
                    alpha = 0.3,
                },
            })
        end

        -- Add cyan lines for loop start and end bar
        local loopBars = Editor.song.loopBars
        if loopBars and #loopBars == 2 then
            local startBar = loopBars[1] * barWidth
            local endBar = loopBars[2] * barWidth
            editor.content:add({
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture { path = 'white' },
                    size = util.vector2(2, 16 * 128),
                    tileH = false,
                    tileV = true,
                    alpha = 0.5,
                    color = util.color.rgb(0, 1, 1),
                    position = util.vector2(startBar, 0),
                },
            })
            editor.content:add({
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture { path = 'white' },
                    size = util.vector2(2, 16 * 128),
                    tileH = false,
                    tileV = true,
                    alpha = 0.5,
                    color = util.color.rgb(0, 1, 1),
                    position = util.vector2(endBar, 0),
                },
            })
        end

        -- Add red line for end bar
        local endBar = Editor.song.lengthBars
        if endBar and endBar > 0 then
            local endBarX = endBar * barWidth
            editor.content:add({
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture { path = 'white' },
                    size = util.vector2(2, 16 * 128),
                    tileH = false,
                    tileV = true,
                    alpha = 0.5,
                    color = util.color.rgb(1, 0, 0),
                    position = util.vector2(endBarX, 0),
                },
            })
        end

        return editor
    end,
}

local getSongManager

local function setMainContent(content)
    if wrapperElement then
        local mainContent = wrapperElement.layout.content[1].content[2].content.mainContent.content
        mainContent[2] = content
        wrapperElement:update()
    end
end

local function updateSongManager()
    setMainContent(getSongManager())
end

local function initPianoRoll()
    if not Editor.song then return end
    pianoRollScrollX = 0
    pianoRollScrollY = 0
end

local function redrawPianoRollEditor()
    if not Editor.song then return end
    if not pianoRollEditorWrapper then return end
    pianoRollEditorWrapper.layout.content[1] = uiTemplates.pianoRollEditor()
    pianoRollEditorWrapper:update()
end

local function parseNotes()
    if not Editor.song then return end
    -- In this function, we will go through the list of note starts and note ends, and pair them up
    Editor.noteMap = {}
    local noteEvents = Editor.song.notes
    local activeNotes = {}

    for _, event in ipairs(noteEvents) do
        if event.type == 'noteOn' and event.velocity > 0 then
            local key = event.note .. '_' .. event.instrument
            activeNotes[key] = {
                startTick = event.time,
                velocity = event.velocity,
            }
        elseif (event.type == 'noteOff') or (event.type == 'noteOn' and event.velocity == 0) then
            local key = event.note .. '_' .. event.instrument
            if activeNotes[key] then
                local duration = event.time - activeNotes[key].startTick
                if duration > 0 then
                    local noteData = {
                        note = event.note,
                        velocity = activeNotes[key].velocity,
                        instrument = event.instrument,
                        time = activeNotes[key].startTick,
                        duration = duration,
                    }
                    table.insert(Editor.noteMap, noteData)
                    activeNotes[key] = nil
                end
            end
        end
    end
    table.sort(Editor.noteMap, function(a, b)
        return a.startTick < b.startTick
    end)
end

local function setSong(song)
    if song then
        Editor.song = song
        parseNotes()
        initPianoRoll()
        updateSongManager()
    end
end

local function saveSong()
    local songs = storage.playerSection('BardicOverhaul'):getCopy('songs/custom') or {}
    for i, song in ipairs(songs) do
        if song.id == Editor.song.id then
            songs[i] = Editor.song
            break
        end
    end
    storage.playerSection('BardicOverhaul'):set('songs/custom', songs)
end

local function addSong()
    local song = Song.new()
    local songs = storage.playerSection('BardicOverhaul'):getCopy('songs/custom') or {}
    table.insert(songs, song)
    storage.playerSection('BardicOverhaul'):set('songs/custom', songs)
    setSong(song)
    setMainContent(getSongManager())
end

local function isPowerOfTwo(n)
	return n > 0 and math.floor(math.log(n) / math.log(2)) == math.log(n) / math.log(2)
end

local function parseTimeSignature(str)
    local numStr, denomStr = str:match("^(%d+)/(%d+)$")
    local numerator = tonumber(numStr)
    local denominator = tonumber(denomStr)

    if not numerator or not denominator then
        return nil
    end

    if numerator < 1 or denominator < 1 then
        return nil
    end

    if not isPowerOfTwo(denominator) then
        return nil
    end

    return {numerator, denominator}
end

getSongManager = function()
    local manager = auxUi.deepLayoutCopy(uiTemplates.songManager)
    local leftBox = manager.content[1].content[1].content
    Editor.songs = storage.playerSection('BardicOverhaul'):getCopy('songs/custom') or {}
    local songs = {}
    for _, song in ipairs(Editor.songs) do
        table.insert(songs, song)
    end
    table.sort(songs, function(a, b)
        return a.title < b.title
    end)
    Editor.songs = songs
    for i, song in ipairs(Editor.songs) do
        local selected = Editor.song and (song.id == Editor.song.id)
        leftBox[i] = {
            template = selected and I.MWUI.templates.bordersThick or I.MWUI.templates.borders,
            props = {
                size = util.vector2(0, 32),
                relativeSize = util.vector2(1, 0),
            },
            content = ui.content {
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = song.title,
                        textColor = selected and util.color.rgb(1, 1, 1) or util.color.rgb(0.5, 0.5, 0.5),
                        anchor = util.vector2(0.5, 0.5),
                        relativePosition = util.vector2(0.5, 0.5),
                    },
                },
            },
            events = {
                mouseClick = async:callback(function()
                    setSong(song)
                    setMainContent(getSongManager())
                end),
            }
        }
    end
    table.insert(manager.content[1].content, {
        type = ui.TYPE.Flex,
        props = {
            autoSize = false,
            size = util.vector2(0, 32),
            relativeSize = util.vector2(1, 0),
            align = ui.ALIGNMENT.Start,
            relativePosition = util.vector2(0, 1),
            anchor = util.vector2(0, 1),
            position = util.vector2(0, -32),
        },
        content = ui.content {
            {
                template = I.MWUI.templates.bordersThick,
                props = {
                    size = util.vector2(0, 32),
                    relativeSize = util.vector2(1, 0),
                },
                content = ui.content {
                    {
                        template = I.MWUI.templates.textNormal,
                        props = {
                            text = '+ New Song',
                            anchor = util.vector2(0.5, 0.5),
                            relativePosition = util.vector2(0.5, 0.5),
                        },
                    },
                },
                events = {
                    mouseClick = async:callback(function()
                        addSong()
                    end),
                }
            },
        }
    })

    if Editor.song then
        local middleBox = manager.content[2].content[1].content
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongTitle'), Editor.song.title, function(text, self)
            if not tostring(text) then
                self.props.text = Editor.song.title
                wrapperElement:update()
                return
            end
            Editor.song.title = text
            saveSong()
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongTempo'), tostring(Editor.song.tempo), function(text, self)
            if not tonumber(text) then
                self.props.text = tostring(Editor.song.tempo)
                wrapperElement:update()
                return
            end
            Editor.song.tempo = tonumber(text)
            saveSong()
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongTimeSig'), Editor.song.timeSig[1] .. '/' .. Editor.song.timeSig[2], function(text, self)
            local timeSig = parseTimeSignature(text)
            if not timeSig then
                self.props.text = Editor.song.timeSig[1] .. '/' .. Editor.song.timeSig[2]
                return
            end
            Editor.song.timeSig = timeSig
            redrawPianoRollEditor()
            saveSong()
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongLoopStart'), tostring(Editor.song.loopBars[1]), function(text, self)
            if not tonumber(text) or tonumber(text) < 0 then
                self.props.text = tostring(Editor.song.loopBars[1])
                return
            end
            Editor.song.loopBars[1] = tonumber(text)
            redrawPianoRollEditor()
            saveSong()
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongLoopEnd'), tostring(Editor.song.loopBars[2]), function(text, self)
            if not tonumber(text) or tonumber(text) > Editor.song.lengthBars then
                self.props.text = tostring(Editor.song.loopBars[2])
                return
            end
            Editor.song.loopBars[2] = tonumber(text)
            redrawPianoRollEditor()
            saveSong()
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongEnd'), tostring(Editor.song.lengthBars), function(text, self)
            if not tonumber(text) or tonumber(text) < 1 then
                self.props.text = tostring(Editor.song.lengthBars)
                return
            end
            Editor.song.lengthBars = tonumber(text)
            redrawPianoRollEditor()
            saveSong()
        end))

        pianoRollEditorWrapper = ui.create {
            type = ui.TYPE.Flex,
            props = {
            },
            content = ui.content {
                uiTemplates.pianoRollEditor(Editor.song.timeSig, 16),
            }
        }

        pianoRoll = ui.create { 
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                autoSize = true,
            },
            content = ui.content { 
                uiTemplates.pianoRollKeyboard(Editor.song.timeSig),
                pianoRollEditorWrapper,
            } 
        }

        pianoRollWrapper = ui.create{
                type = ui.TYPE.Flex,
                name = 'pianoRoll',
                props = {
                    horizontal = true,
                    autoSize = true
                },
                content = ui.content {
                    pianoRoll
                },
        }
        table.insert(manager.content[3].content, pianoRollWrapper)
    end
    return manager
end

local STATE = {
    PERFORMANCE = 0,
    SONG = 1,
    PIANO_ROLL = 2,
}

function Editor:setState()
    if self.state == STATE.SONG then
        setMainContent(getSongManager())
    end
end

function Editor:createUI()
    self.song = nil
    self.noteMap = nil
    local wrapper = uiTemplates.wrapper
    screenSize = ui.screenSize()
    wrapper.content[1].props.size = util.vector2(screenSize.x-20, screenSize.y - 200)
    wrapperElement = ui.create(wrapper)

    if self.state == STATE.PIANO_ROLL and not self.song then
        self.state = STATE.SONG
    end
    Editor:setState()
end

function Editor:destroyUI()
    if wrapperElement then
        wrapperElement:destroy()
        wrapperElement = nil
    end
    if fakeMouseElement then
        fakeMouseElement:destroy()
        fakeMouseElement = nil
    end
end

function Editor:onToggle()
    if self.active then
        self:destroyUI()
        self.active = false
        I.UI.removeMode(I.UI.MODE.Interface)
    else
        self:createUI()
        self.active = true
        I.UI.setMode(I.UI.MODE.Interface, {windows = {}})
    end
end

function Editor:onUINil()
    if self.active then
        self:destroyUI()
        self.active = false
        I.UI.removeMode(I.UI.MODE.Interface)
    end
end

function Editor:onFrame()
end

function Editor:onMouseWheel(vertical)
    if pianoRollFocused then
        pianoRollScrollY = pianoRollScrollY + vertical * 16
        updatePianoRoll()
    end
end

function Editor:init()
    self.state = STATE.SONG
end

return Editor