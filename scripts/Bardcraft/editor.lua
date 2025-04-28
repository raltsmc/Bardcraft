local ui = require('openmw.ui')
local auxUi = require('openmw_aux.ui')
local I = require('openmw.interfaces')
local storage = require('openmw.storage')
local async = require('openmw.async')
local ambient = require('openmw.ambient')
local core = require('openmw.core')
local util = require('openmw.util')
local input = require('openmw.input')

local l10n = core.l10n('Bardcraft')

local luaxp = require('scripts.Bardcraft.util.luaxp')
local Song = require('scripts.Bardcraft.util.song')

local Editor = {}

Editor.STATE = {
    PERFORMANCE = 0,
    PRACTICE = 1,
    SONG = 2,
}

Editor.active = false
Editor.song = nil
Editor.songs = nil
Editor.state = nil
Editor.noteMap = nil
Editor.resolutionSnap = 0.25
Editor.noteIdCounter = 0

Editor.windowXOff = 20
Editor.windowYOff = 200
Editor.windowCaptionHeight = 20
Editor.windowTabsHeight = 32
Editor.windowLeftBoxXMult = 4 / 32
Editor.windowMiddleBoxXMult = 4 / 32

local uiColors = {
    DEFAULT = util.color.rgb(202 / 255, 165 / 255, 96 / 255),
    DEFAULT_LIGHT = util.color.rgb(223 / 255, 201 / 255, 159 / 255),
    WHITE = util.color.rgb(1, 1, 1),
    BLACK = util.color.rgb(0, 0, 0),
    CYAN = util.color.rgb(0, 1, 1),
    YELLOW = util.color.rgb(1, 1, 0),
    RED = util.color.rgb(1, 0, 0),
}

Editor.noteColor = uiColors.DEFAULT
Editor.backgroundColor = uiColors.WHITE
Editor.keyboardColor = uiColors.WHITE
Editor.keyboardWhiteTextColor = uiColors.BLACK
Editor.keyboardBlackTextColor = uiColors.WHITE
Editor.beatLineColor = uiColors.DEFAULT_LIGHT
Editor.barLineColor = uiColors.DEFAULT_LIGHT
Editor.loopStartLineColor = uiColors.CYAN
Editor.loopEndLineColor = uiColors.CYAN
Editor.playbackLineColor = uiColors.YELLOW

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
                size = util.vector2(2, Editor.windowCaptionHeight),
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
                size = util.vector2(0, Editor.windowCaptionHeight),
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
                size = util.vector2(2, Editor.windowCaptionHeight),
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
local pianoRollScrollXMax = 0
local pianoRollScrollYMax = 0
local pianoRollScrollLastPopulateX = 0
local pianoRollScrollPopulateWindowSize = 400
local pianoRollFocused = false
local pianoRollWrapper = nil
local pianoRollKeyboardWrapper = nil
local pianoRollEditorWrapper = nil
local pianoRollEditorMarkersWrapper = nil
local pianoRoll = nil

local textFocused = false

local DragType = {
    NONE = 0,
    RESIZE_LEFT = 1,
    RESIZE_RIGHT = 2,
    MOVE = 3,
}
local pianoRollActiveNote = nil
local pianoRollDragStart = nil
local pianoRollDragType = DragType.NONE

local playback = false

local function playNoteSound(note)
    local noteNames = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
    local octave = math.floor(note / 12) - 1
    local noteName = noteNames[(note % 12) + 1]
    local fileName = 'sound\\Bardcraft\\samples\\Lute\\Lute_' .. noteName .. octave .. '.wav'
    ambient.playSoundFile(fileName)
end

--[[local ZoomLevels = {
    [1] = 1.0,
    [2] = 2.0,
    [3] = 4.0,
}]]

-- This is a necessary optimization so that we don't have to render an image for each beat line (insanely taxing on performance)
local uiWholeNoteWidth = 256

local function calcBeatWidth(denominator)
    return uiWholeNoteWidth / denominator
end

local function calcBarWidth()
    if not Editor.song then return 0 end
    return calcBeatWidth(Editor.song.timeSig[2]) * Editor.song.timeSig[1]
end

local function calcOctaveHeight()
    return 16 * 12
end

local function calcOuterWindowWidth()
    if not screenSize then return 0 end
    local availableWidth = screenSize.x - Editor.windowXOff -- Subtract padding or margins
    return math.max(availableWidth, 0)
end

local function calcOuterWindowHeight()
    if not screenSize then return 0 end
    local availableHeight = screenSize.y - Editor.windowYOff -- Subtract padding or margins
    return math.max(availableHeight, 0)
end

local function calcPianoRollWrapperSize()
    if not screenSize then return util.vector2(0, 0) end
    local windowWidth = calcOuterWindowWidth()
    local windowHeight = calcOuterWindowHeight()
    local width = windowWidth - ((screenSize.x * Editor.windowLeftBoxXMult) + (screenSize.x * Editor.windowMiddleBoxXMult)) - 8
    local height = windowHeight - (Editor.windowCaptionHeight + Editor.windowTabsHeight) - 8
    return util.vector2(width, height)
end

local function calcPianoRollEditorWrapperSize()
    local wrapperSize = calcPianoRollWrapperSize()
    return util.vector2(wrapperSize.x - 96, wrapperSize.y)
end

local function calcPianoRollEditorWidth()
    if not Editor.song then return 0 end
    return Editor.song.lengthBars * calcBarWidth()
end

local function calcPianoRollEditorHeight()
    return calcOctaveHeight() * 128 / 12
end

local function editorOffsetToRealOffset(offset)
    return offset - util.vector2(pianoRollScrollX, pianoRollScrollY)
end

local function realOffsetToNote(offset)
    -- Will return pitch and tick
    local noteIndex = math.floor((128 - (offset.y / 16)))
    local beat = offset.x / calcBeatWidth(Editor.song.timeSig[2])
    local tick = math.floor(beat * (4 / Editor.song.timeSig[2]) * Editor.song.resolution) + 1
    return noteIndex, tick
end

local notesLayout = {}
local noteNames = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
for i = 127, 0, -1 do
    local octave = math.floor(i / 12) - 1
    local noteName = noteNames[(i % 12) + 1]
    local isBlackKey = noteName:find("b") ~= nil
    local noteY = (128 - i) * 16
    table.insert(notesLayout, {
        type = ui.TYPE.Widget,
        props = {
            autoSize = false,
            size = util.vector2(96, 16),
            position = util.vector2(0, noteY),
        },
        content = ui.content {
            {
                template = I.MWUI.templates.textNormal,
                props = {
                    text = noteName .. octave,
                    textColor = isBlackKey and Editor.keyboardBlackTextColor or Editor.keyboardWhiteTextColor,
                    anchor = util.vector2(0, 0.5),
                    relativePosition = util.vector2(0, 0.5),
                },
            },
        }
    })
end

local function updatePianoRollKeyboardLabels()
    local highestNote = 128 - math.floor(-pianoRollScrollY / 16)
    local lowestNote = math.floor(util.clamp(highestNote - (calcPianoRollEditorWrapperSize().y / 16), 1, 128))
    local notesToShow = {table.unpack(notesLayout, (129 - highestNote), (129 - lowestNote))}
    pianoRollKeyboardWrapper.layout.content[1].content[2].content = ui.content(notesToShow)
    pianoRollKeyboardWrapper.layout.content[1].content[2].props.position = util.vector2(0, 16 * (128 - highestNote))
    pianoRollKeyboardWrapper:update()
end

local function updatePianoRoll()
    if not Editor.song then return end
    if not pianoRollWrapper or not pianoRollEditorWrapper or not pianoRollEditorWrapper.layout or not pianoRollEditorMarkersWrapper or not pianoRollEditorMarkersWrapper.layout then return end
    local editorOverlay = pianoRollEditorWrapper.layout.content[1].content.pianoRollOverlay
    local editorMarkers = pianoRollEditorMarkersWrapper.layout.content.pianoRollMarkers
    local editorNotes = pianoRollEditorWrapper.layout.content[1].content.pianoRollNotes
    local barWidth = calcBarWidth()
    local octaveHeight = calcOctaveHeight()
    pianoRollKeyboardWrapper.layout.content[1].props.position = util.vector2(0, pianoRollScrollY)
    updatePianoRollKeyboardLabels()
    
    editorOverlay.props.position = util.vector2(pianoRollScrollX % barWidth - barWidth, pianoRollScrollY % octaveHeight - octaveHeight)
    editorMarkers.props.position = util.vector2(pianoRollScrollX, 0)
    editorNotes.props.position = util.vector2(pianoRollScrollX, pianoRollScrollY)
    pianoRollEditorMarkersWrapper:update()
    pianoRollEditorWrapper:update()
end

local uiTextures = {
    pianoRollKeys = ui.texture {
        path = 'textures/Bardcraft/ui/pianoroll-h.dds',
        offset = util.vector2(0, 0),
        size = util.vector2(62, 192),
    },
    pianoRollRows = ui.texture {
        path = 'textures/Bardcraft/ui/pianoroll-h.dds',
        offset = util.vector2(96, 0),
        size = util.vector2(4, 192),
    },
    pianoRollBeatLines = {},
    pianoRollNote = ui.texture {
        path = 'textures/Bardcraft/ui/pianoroll-note.dds',
    }
}

for i = 0, 7 do
    local denom = math.pow(2, i)
    local yOffset = math.log(denom) / math.log(2)
    uiTextures.pianoRollBeatLines[denom] = ui.texture {
        path = 'textures/Bardcraft/ui/pianoroll-v.dds',
        offset = util.vector2(0, yOffset),
        size = util.vector2(calcBeatWidth(denom), 1),
    }
end

local addNote, removeNote, initNotes, saveNotes
local addSong, saveSong, setSong
local noteEventsToNoteMap, noteMapToNoteEvents

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
                            size = util.vector2(0, Editor.windowCaptionHeight)
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
                                            size = util.vector2(0, Editor.windowTabsHeight),
                                            relativeSize = util.vector2(1, 0),
                                        },
                                        content = ui.content {
                                            {
                                                type = ui.TYPE.Flex,
                                                props = {
                                                    horizontal = true,
                                                    autoSize = false,
                                                    size = util.vector2(0, Editor.windowTabsHeight),
                                                    relativeSize = util.vector2(1, 0),
                                                },
                                                external = {
                                                    grow = 1,
                                                    stretch = 1,
                                                },
                                                content = ui.content {
                                                    uiButton("Song Manager", function()
                                                        Editor:setState(Editor.STATE.SONG)
                                                    end),
                                                    uiButton("Performance", function()
                                                        Editor:setState(Editor.STATE.PERFORMANCE)
                                                    end),
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
        },
        events = {
            keyPress = async:callback(function(e)
            end),
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
                    size = util.vector2(ui.screenSize().x * Editor.windowLeftBoxXMult, 0),
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
                    size = util.vector2(ui.screenSize().x * Editor.windowMiddleBoxXMult, 0),
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
                                focusGain = async:callback(function()
                                    textFocused = true
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
                size = util.vector2(96, calcPianoRollEditorHeight()),
                position = util.vector2(0, pianoRollScrollY)
            },
            content = ui.content {},
            events = {
                mouseMove = async:callback(function(e)
                    if e.button == 1 then
                        local noteIndex = math.floor((128 - (e.offset.y / 16)))
                        local octave = math.floor(noteIndex / 12) - 1
                        local noteNames = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
                        local noteName = noteNames[(noteIndex % 12) + 1]
                        local fileName = 'sound\\Bardcraft\\samples\\Lute\\Lute_' .. noteName .. octave .. '.wav'
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
                        local fileName = 'sound\\Bardcraft\\samples\\Lute\\Lute_' .. noteName .. octave .. '.wav'
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
                size = util.vector2(96, calcPianoRollEditorHeight()),
                color = Editor.keyboardColor,
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
        return bar
    end,
    pianoRollEditor = function()
        if not Editor.song then return {} end
        local timeSig = Editor.song.timeSig
        local barWidth = calcBarWidth() -- Width of a single bar based on time signature
        local totalWidth = barWidth * Editor.song.lengthBars -- Total width based on number of bars
        local editor = {
            type = ui.TYPE.Widget,
            props = {
                size = util.vector2(totalWidth, calcPianoRollEditorHeight()),
            },
            content = ui.content {
                -- {
                --     type = ui.TYPE.Flex,
                --     props = {
                --         autoSize = false,
                --         size = util.vector2(totalWidth, calcPianoRollEditorHeight()),
                --     },
                --     content = ui.content {},
                -- },
            },
        }

        local wrapperSize = calcPianoRollEditorWrapperSize()

        local editorOverlay = {
            type = ui.TYPE.Widget,
            name = 'pianoRollOverlay',
            props = {
                size = util.vector2(wrapperSize.x + calcBarWidth(), wrapperSize.y + calcOctaveHeight()), -- Add padding for when we loop the overlay
                position = util.vector2(pianoRollScrollX % barWidth - barWidth, pianoRollScrollY % calcOctaveHeight() - calcOctaveHeight())
            },
            content = ui.content {},
        }
        
        editorOverlay.content:add({
            type = ui.TYPE.Image,
            name = 'bgrRows',
            props = {
                resource = uiTextures.pianoRollRows,
                relativeSize = util.vector2(1, 1),
                tileH = true,
                tileV = true,
                color = Editor.backgroundColor,
                alpha = 0.06,
            },
        })

        for i = 1, Editor.song.lengthBars + 1 do
            -- Create a vertical line for each bar
            editorOverlay.content:add({
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture { path = 'white' },
                    size = util.vector2(1, 0),
                    relativeSize = util.vector2(0, 1),
                    tileH = false,
                    tileV = true,
                    alpha = 1,
                    color = Editor.barLineColor,
                    position = util.vector2(i * barWidth, 0),
                },
            })
        end
        editorOverlay.content:add({
            type = ui.TYPE.Image,
            name = 'bgrBars',
            props = {
                resource = uiTextures.pianoRollBeatLines[timeSig[2]],
                relativeSize = util.vector2(1, 1),
                tileH = true,
                tileV = true,
                color = Editor.beatLineColor,
                alpha = 0.3,
            },
        })

        local editorMarkers = {
            type = ui.TYPE.Widget,
            name = 'pianoRollMarkers',
            props = {
                size = util.vector2(totalWidth, calcPianoRollEditorHeight()),
                position = util.vector2(pianoRollScrollX, 0),
            },
            content = ui.content {},
        }
        local function addMarker(x, color, alpha)
            editorMarkers.content:add({
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture { path = 'white' },
                    size = util.vector2(2, 0),
                    relativeSize = util.vector2(0, 1),
                    tileH = false,
                    tileV = true,
                    alpha = alpha or 1,
                    color = color,
                    position = util.vector2(x, 0),
                },
            })
        end
        -- Add playback marker
        addMarker(0, Editor.playbackLineColor, playback and 1 or 0)

        -- Add cyan lines for loop start and end bar
        local loopBars = Editor.song.loopBars
        if loopBars and #loopBars == 2 then
            if loopBars[1] > 0 then
                addMarker(loopBars[1] * barWidth, Editor.loopStartLineColor, 0.5)
            end
            addMarker(loopBars[2] * barWidth, Editor.loopEndLineColor, 0.5)
        end

        -- Add red line for end bar
        local endBar = Editor.song.lengthBars
        if endBar and endBar > 0 then
            local endBarX = endBar * barWidth
            addMarker(endBarX, util.color.rgb(1, 0, 0), 0.5)
        end

        pianoRollEditorMarkersWrapper = ui.create {
            type = ui.TYPE.Widget,
            props = {
                size = util.vector2(totalWidth, calcPianoRollEditorHeight()),
            },
            content = ui.content {
                editorMarkers,
            }
        }

        local editorNotes = {
            type = ui.TYPE.Widget,
            name = 'pianoRollNotes',
            props = {
                size = util.vector2(totalWidth, calcPianoRollEditorHeight()),
                position = util.vector2(pianoRollScrollX, pianoRollScrollY)
            },
            content = ui.content {},
        }
        editor.content:add(editorOverlay)
        editor.content:add(pianoRollEditorMarkersWrapper)
        editor.content:add(editorNotes)
        return editor
    end,
    pianoRollNote = function(id, note, tick, duration)
        local noteWidth = calcBeatWidth(Editor.song.timeSig[2]) * (Editor.song:tickToBeat(duration))
        local noteHeight = calcOctaveHeight() / 12
        local noteX = calcBeatWidth(Editor.song.timeSig[2]) * (Editor.song:tickToBeat(tick))
        local noteY = (127 - note) * noteHeight
        return {
            type = ui.TYPE.Image,
            name = tostring(id),
            props = {
                resource = uiTextures.pianoRollNote,
                size = util.vector2(noteWidth, noteHeight),
                tileH = true,
                tileV = false,
                color = Editor.noteColor,
                position = util.vector2(noteX, noteY),
            },
            events = {
                mousePress = async:callback(function(e, self)
                    if e.button == 3 then
                        removeNote(self)
                        saveNotes()
                    end
                end),
            }
        }
    end,
}

addNote = function(note, tick, duration, instrument)
    if not Editor.song then return end
    duration = duration or Editor.song.resolution * (4 / Editor.song.timeSig[2])
    instrument = instrument or 24
    local noteData = {
        id = Editor.noteIdCounter,
        note = note,
        velocity = 127,
        track = 1,
        instrument = instrument,
        time = tick,
        duration = duration,
    }
    table.insert(Editor.noteMap, noteData)
    pianoRollEditorWrapper.layout.content[1].content[3].content:add(uiTemplates.pianoRollNote(Editor.noteIdCounter, note, tick, duration))
    Editor.noteIdCounter = Editor.noteIdCounter + 1
    pianoRollEditorWrapper:update()
    return #Editor.noteMap
end

removeNote = function(element)
    if not Editor.song then return end
    local id = element.name
    if not id then return end
    for i, noteData in ipairs(Editor.noteMap) do
        if noteData.id == tonumber(id) then
            table.remove(Editor.noteMap, i)
            break
        end
    end
    local pianoRollNotes = pianoRollEditorWrapper.layout.content[1].content[3].content
    for i, note in ipairs(pianoRollNotes) do
        if note.name == id then
            table.remove(pianoRollNotes, i)
            break
        end
    end
    pianoRollEditorWrapper:update()
end

local function populateNotes()
    pianoRollEditorWrapper.layout.content[1].content[3].content = ui.content{}
    for _, noteData in ipairs(Editor.noteMap) do
        local id = noteData.id
        local note = noteData.note
        local tick = noteData.time
        local duration = noteData.duration
        -- Check if note is within the viewing area
        local noteX = calcBeatWidth(Editor.song.timeSig[2]) * (Editor.song:tickToBeat(tick))
        local noteWidth = calcBeatWidth(Editor.song.timeSig[2]) * (Editor.song:tickToBeat(duration))
        local wrapperSize = calcPianoRollEditorWrapperSize()

        if noteX + noteWidth >= -pianoRollScrollX - pianoRollScrollPopulateWindowSize and noteX <= -pianoRollScrollX + pianoRollScrollPopulateWindowSize + wrapperSize.x then
            -- Add note to the piano roll
            pianoRollEditorWrapper.layout.content[1].content[3].content:add(uiTemplates.pianoRollNote(id, note, tick, duration))
        end
        --pianoRollEditorWrapper.layout.content[1].content[3].content:add(uiTemplates.pianoRollNote(id, note, tick, duration))
        Editor.noteIdCounter = math.max(Editor.noteIdCounter, id + 1)
    end
    pianoRollEditorWrapper:update()
end

initNotes = function()
    if not Editor.song then return end
    Editor.noteIdCounter = 0
    noteEventsToNoteMap()
    populateNotes()
end

saveNotes = function()
    if not Editor.song then return end
    local noteEvents = noteMapToNoteEvents()
    Editor.song.notes = noteEvents
    saveSong()
end

local getSongManager

local function setMainContent(content)
    if wrapperElement then
        local mainContent = wrapperElement.layout.content[1].content[2].content.mainContent.content
        mainContent[2] = content
        wrapperElement:update()
    end
end

local function importSong()
    if not Editor.song then return end
    if wrapperElement then
        local manager = wrapperElement.layout.content[1].content[2].content.mainContent.content[2]
        if manager then
            local importTextBox = manager.content[2].content[2].content.importExportTextBox.content[1] --TODO make this use importExport tag, not sure why it isn't working
            local songData = importTextBox.props.text
            print(songData)
            if songData and songData ~= "" then
                local song = Song.decode(songData)
                if song then
                    setSong(song)
                    print("set song to " .. song.title)
                    saveSong()
                end
            end
        end
    end
end

local function exportSong()
    if not Editor.song then return end
    if wrapperElement then
        local manager = wrapperElement.layout.content[1].content[2].content.mainContent.content[2]
        if manager then
            local exportTextBox = manager.content[2].content[2].content.importExportTextBox.content[1] --TODO make this use importExport tag, not sure why it isn't working
            exportTextBox.props.text = Editor.song:encode()
            wrapperElement:update()
        end
    end
end

--[[local function setTextBoxesEnabledInLayout(layout, enabled)
    print("Recursing on: " .. ((layout.type and ("type: " .. layout.type) or "") .. (layout.name and (" name: " .. layout.name) or "")))
    for _, box in ipairs(layout.content) do
        if box.template == I.MWUI.templates.textEditLine or box.type == ui.TYPE.TextEdit then
            box.props.readOnly = not enabled
            box.props.textColor = enabled and util.color.rgb(1, 1, 1) or util.color.rgb(0.5, 0.5, 0.5)
        elseif box.content then
            setTextBoxesEnabledInLayout(box, enabled)
        end
    end
end

local function setTextBoxesEnabled(enabled)
    local manager = wrapperElement.layout.content[1].content[2].content.mainContent.content[2]
    if manager then
        setTextBoxesEnabledInLayout(manager, enabled)
        wrapperElement:update()
    end
end]]

local function updateSongManager()
    setMainContent(getSongManager())
end

local function initPianoRoll()
    if not Editor.song then return end
    if calcPianoRollEditorWidth() > calcPianoRollEditorWrapperSize().x then
        pianoRollScrollXMax = calcPianoRollEditorWidth() - calcPianoRollEditorWrapperSize().x
    else
        pianoRollScrollXMax = 0
    end
    if calcPianoRollEditorHeight() > calcPianoRollEditorWrapperSize().y then
        pianoRollScrollYMax = calcPianoRollEditorHeight() - calcPianoRollEditorWrapperSize().y
    else
        pianoRollScrollYMax = 0
    end 
end

local function redrawPianoRollEditor()
    if not Editor.song then return end
    if pianoRollEditorWrapper then
        auxUi.deepDestroy(pianoRollEditorWrapper.layout)
    end
    initPianoRoll()
    updateSongManager()
    updatePianoRollKeyboardLabels()
    pianoRollEditorWrapper.layout.content[1] = uiTemplates.pianoRollEditor()
    initNotes()
end

noteEventsToNoteMap = function()
    if not Editor.song then return end
    -- In this function, we will go through the list of note starts and note ends, and pair them up
    Editor.noteMap = {}
    local noteEvents = Editor.song.notes
    local activeNotes = {}

    for _, event in ipairs(noteEvents) do
        if event.type == 'noteOn' and event.velocity > 0 then
            local key = event.note .. '_' .. event.instrument
            activeNotes[key] = {
                start = event.time,
                velocity = event.velocity,
            }
        elseif (event.type == 'noteOff') or (event.type == 'noteOn' and event.velocity == 0) then
            local key = event.note .. '_' .. event.instrument
            if activeNotes[key] then
                local duration = event.time - activeNotes[key].start
                if duration > 0 then
                    local noteData = {
                        id = event.id,
                        note = event.note,
                        velocity = activeNotes[key].velocity,
                        track = event.track,
                        instrument = event.instrument,
                        time = activeNotes[key].start,
                        duration = duration,
                    }
                    table.insert(Editor.noteMap, noteData)
                    activeNotes[key] = nil
                end
            end
        end
    end
    table.sort(Editor.noteMap, function(a, b)
        return a.time < b.time
    end)
end

noteMapToNoteEvents = function()
    if not Editor.noteMap then return {} end
    -- This converts the merged note map back to a list of on/off note events
    local noteEvents = {}
    for _, noteData in ipairs(Editor.noteMap) do
        local noteOnEvent = {
            id = noteData.id,
            type = 'noteOn',
            note = noteData.note,
            velocity = noteData.velocity,
            track = noteData.track,
            instrument = noteData.instrument,
            time = noteData.time,
        }
        table.insert(noteEvents, noteOnEvent)

        local noteOffEvent = {
            id = noteData.id,
            type = 'noteOff',
            note = noteData.note,
            velocity = 0,
            track = noteData.track,
            instrument = noteData.instrument,
            time = noteData.time + noteData.duration,
        }
        table.insert(noteEvents, noteOffEvent)
    end
    table.sort(noteEvents, function(a, b)
        if a.time == b.time then
            return (a.type == "noteOff" and b.type == "noteOn")
        end
        return a.time < b.time
    end)
    return noteEvents
end

local function stopAllSounds()
    local profiles = Song.getInstrumentProfiles()
    for _, profile in pairs(profiles) do
        for j = 0, 127 do
            local filePath = 'sound\\Bardcraft\\samples\\' .. profile.name .. '\\' .. profile.name .. '_' .. Song.noteNumberToName(j) .. '.wav'
            if ambient.isSoundFilePlaying(filePath) then
                ambient.stopSoundFile(filePath)
            end
        end
    end
end

local function startPlayback()
    if not Editor.song then return end
    playback = true
    Editor.song:resetPlayback()
end

local function stopPlayback()
    playback = false
    Editor.song:resetPlayback()
    pianoRollEditorMarkersWrapper:update()
    stopAllSounds()
end

setSong = function(song)
    if song then
        Editor.song = song
        setmetatable(Editor.song, Song)
        redrawPianoRollEditor()
        stopPlayback()
    end
end

saveSong = function()
    --[[local songs = storage.playerSection('Bardcraft'):getCopy('songs/custom') or {}
    for i, song in ipairs(songs) do
        if song.id == Editor.song.id then
            songs[i] = Editor.song
            break
        end
    end
    storage.playerSection('Bardcraft'):set('songs/custom', songs)]]
end

addSong = function()
    --[[local song = Song.new()
    local songs = storage.playerSection('Bardcraft'):getCopy('songs/custom') or {}
    table.insert(songs, song)
    storage.playerSection('Bardcraft'):set('songs/custom', songs)
    setSong(song)
    setMainContent(getSongManager())]]
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

local lastMouseDragPos = nil

getSongManager = function()
    local manager = auxUi.deepLayoutCopy(uiTemplates.songManager)
    local leftBox = manager.content[1].content[1].content
    Editor.songs = storage.playerSection('Bardcraft'):getCopy('songs/preset') or {}
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
        local function numMatches(field, numStr)
            return tonumber(field) == tonumber(numStr)
        end
        local function parseExp(numStr)
            local parsedExp, err = luaxp.compile(numStr)
            if not parsedExp then
                return nil, err
            end
            local num, rerr = luaxp.run(parsedExp)
            if num == nil or type(num) ~= "number" then return nil, rerr end
            return num, nil
        end
        local middleBox = manager.content[2].content[1].content
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongTitle'), Editor.song.title, function(text, self)
            if not tostring(text) then
                self.props.text = Editor.song.title
            else
                Editor.song.title = text
                saveSong()
                redrawPianoRollEditor()
            end
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongTempo'), tostring(Editor.song.tempo), function(text, self)
            if not tonumber(text) then
                self.props.text = tostring(Editor.song.tempo)
            else
                Editor.song.tempo = tonumber(text)
                saveSong()
                redrawPianoRollEditor()
            end
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongTimeSig'), Editor.song.timeSig[1] .. '/' .. Editor.song.timeSig[2], function(text, self)
            local timeSig = parseTimeSignature(text)
            if not timeSig then
                self.props.text = Editor.song.timeSig[1] .. '/' .. Editor.song.timeSig[2]
            elseif not numMatches(Editor.song.timeSig[1], timeSig[1]) or not numMatches(Editor.song.timeSig[2], timeSig[2]) then
                Editor.song.timeSig = timeSig
                saveSong()
                redrawPianoRollEditor()
            end
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongLoopStart'), tostring(Editor.song.loopBars[1]), function(text, self)
            local parsed = parseExp(text)
            if not parsed or parsed < 0 then
                self.props.text = tostring(Editor.song.loopBars[1])
            elseif not numMatches(Editor.song.loopBars[1], parsed) then
                Editor.song.loopBars[1] = parsed
                saveSong()
                redrawPianoRollEditor()
            end
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongLoopEnd'), tostring(Editor.song.loopBars[2]), function(text, self)
            local parsed = parseExp(text)
            if not parsed or parsed > Editor.song.lengthBars then
                self.props.text = tostring(Editor.song.loopBars[2])
            elseif not numMatches(Editor.song.loopBars[2], parsed) then
                Editor.song.loopBars[2] = parsed
                saveSong()
                redrawPianoRollEditor()
            end
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongEnd'), tostring(Editor.song.lengthBars), function(text, self)
            local parsed = parseExp(text)
            if not parsed or parsed < 1 then
                self.props.text = tostring(Editor.song.lengthBars)
            elseif not numMatches(Editor.song.lengthBars, parsed) then
                Editor.song.lengthBars = parsed
                saveSong()
                redrawPianoRollEditor()
            end
        end))

        table.insert(manager.content[2].content, {
            type = ui.TYPE.Flex,
            name = 'importExport',
            props = {
                autoSize = false,
                size = util.vector2(0, 96),
                relativeSize = util.vector2(1, 0),
                align = ui.ALIGNMENT.Start,
                relativePosition = util.vector2(0, 1),
                anchor = util.vector2(0, 1),
                position = util.vector2(0, -32),
            },
            content = ui.content {
                {
                    template = I.MWUI.templates.borders,
                    name = 'importExportTextBox',
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
                                    if text == '' then
                                        Editor:destroyUI()
                                        Editor:createUI()
                                    else
                                        self.props.text = text
                                        wrapperElement:update()
                                    end
                                end),
                            }
                        }
                    },
                },
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
                                text = 'Import Song',
                                anchor = util.vector2(0.5, 0.5),
                                relativePosition = util.vector2(0.5, 0.5),
                            },
                        },
                    },
                    events = {
                        mouseClick = async:callback(function()
                            importSong()
                        end),
                    }
                },
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
                                text = 'Export Song',
                                anchor = util.vector2(0.5, 0.5),
                                relativePosition = util.vector2(0.5, 0.5),
                            },
                        },
                    },
                    events = {
                        mouseClick = async:callback(function()
                            exportSong()
                        end),
                    }
                },
            }
        })

        pianoRollEditorWrapper = ui.create {
            type = ui.TYPE.Widget,
            props = {
                size = util.vector2(calcPianoRollEditorWidth(), calcPianoRollEditorHeight()),
                position = util.vector2(96, 0)
            },
            content = ui.content {
                uiTemplates.pianoRollEditor(Editor.song.timeSig, 16),
            },
            events = {
                mouseMove = async:callback(function(e)
                    if input.isMouseButtonPressed(2) then
                        if textFocused then
                            Editor:destroyUI()
                            Editor:createUI()
                            textFocused = false
                        end
                        lastMouseDragPos = lastMouseDragPos or util.vector2(e.position.x, e.position.y)
                        local dx = e.position.x - lastMouseDragPos.x
                        local dy = e.position.y - lastMouseDragPos.y
                        lastMouseDragPos = util.vector2(e.position.x, e.position.y)
                        if pianoRollFocused then
                            pianoRollScrollX = util.clamp(pianoRollScrollX + dx, -pianoRollScrollXMax, 0)
                            pianoRollScrollY = util.clamp(pianoRollScrollY + dy, -pianoRollScrollYMax, 0)
                            updatePianoRoll()
                            if math.abs(pianoRollScrollX - pianoRollScrollLastPopulateX) > pianoRollScrollPopulateWindowSize then
                                pianoRollScrollLastPopulateX = pianoRollScrollX
                                populateNotes()
                            end
                        end
                    end
                    if e.button == 1 and pianoRollDragStart then
                        local offset = editorOffsetToRealOffset(e.offset)
                        if pianoRollDragType == DragType.RESIZE_RIGHT then
                            local _, tick = realOffsetToNote(offset)
                            local snap = Editor.song.resolution * Editor.resolutionSnap * (4 / Editor.song.timeSig[2])
                            tick = math.ceil(tick / snap) * snap + 1
                            local noteData = Editor.noteMap[pianoRollActiveNote]
                            noteData.duration = util.clamp(tick - noteData.time, snap, math.huge)
                            local layout = pianoRollEditorWrapper.layout.content[1].content[3].content
                            local notePos
                            for i, note in ipairs(layout) do
                                if note.name == tostring(noteData.id) then
                                    notePos = i
                                    break
                                end
                            end
                            layout[notePos] = uiTemplates.pianoRollNote(noteData.id, noteData.note, noteData.time, noteData.duration)
                            pianoRollEditorWrapper:update()
                        end
                    end
                end),
                mousePress = async:callback(function(e)
                    if textFocused then
                        Editor:destroyUI()
                        Editor:createUI()
                        textFocused = false
                    end
                    if e.button ~= 1 then return end
                    local note, tick = realOffsetToNote(editorOffsetToRealOffset(e.offset))
                    local snap = Editor.song.resolution * Editor.resolutionSnap * (4 / Editor.song.timeSig[2])
                    tick = math.floor(tick / snap) * snap + 1
                    playNoteSound(note)
                    pianoRollActiveNote = addNote(note, tick, snap)
                    pianoRollDragStart = editorOffsetToRealOffset(e.offset)
                    pianoRollDragType = DragType.RESIZE_RIGHT
                end),
                mouseRelease = async:callback(function(e)
                    if e.button == 2 then
                        lastMouseDragPos = nil
                    end
                    if e.button == 1 then
                        pianoRollDragStart = nil
                        pianoRollDragType = DragType.NONE
                        pianoRollActiveNote = nil
                        pianoRollActiveNoteElement = nil
                        pianoRollEditorWrapper:update()
                        saveNotes()
                    end
                end),
                focusLoss = async:callback(function()
                    lastMouseDragPos = nil
                end),
            }
        }

        initNotes()

        pianoRollKeyboardWrapper = ui.create{
            type = ui.TYPE.Widget,
            props = {
                size = util.vector2(96, calcPianoRollEditorHeight()),
                position = util.vector2(0, 0)
            },
            content = ui.content {
                uiTemplates.pianoRollKeyboard(Editor.song.timeSig),
            },
        }

        pianoRoll = ui.create { 
            type = ui.TYPE.Widget,
            props = {
                size = calcPianoRollWrapperSize(),
            },
            content = ui.content { 
                pianoRollKeyboardWrapper,
                pianoRollEditorWrapper,
            } 
        }

        pianoRollWrapper = ui.create{
                type = ui.TYPE.Widget,
                name = 'pianoRoll',
                props = {
                    size = calcPianoRollWrapperSize(),
                },
                content = ui.content {
                    pianoRoll
                },
        }
        table.insert(manager.content[3].content, pianoRollWrapper)
    end
    return manager
end

local function updatePlaybackMarker()
    if pianoRollEditorMarkersWrapper and pianoRollEditorMarkersWrapper.layout.content.pianoRollMarkers.content[1] then
        local playbackMarker = pianoRollEditorMarkersWrapper.layout.content.pianoRollMarkers.content[1]
        if playbackMarker then
            local playbackX = (Editor.song:tickToBeat(Editor.song.playbackTickCurr)) * calcBeatWidth(Editor.song.timeSig[2])
            playbackMarker.props.position = util.vector2(playbackX, 0)
            playbackMarker.props.alpha = playbackX > 0 and 0.8 or 0
            if (playbackX + pianoRollScrollX) > calcPianoRollEditorWrapperSize().x or (playbackX + pianoRollScrollX) < 0 then
                pianoRollScrollX = util.clamp(-playbackX, -pianoRollScrollXMax, 0)
                pianoRollScrollLastPopulateX = pianoRollScrollX
                updatePianoRoll()
                populateNotes()
            end
            pianoRollEditorMarkersWrapper:update()
        end
    end
end

local function tickPlayback(dt)
    if not Editor.song then return end
    if playback then
        Editor.song:tickPlayback(dt, 
        function(filePath, velocity, instrument)
            if velocity > 0 then
                ambient.playSoundFile(filePath, { volume = velocity / 127 })
            end
        end, 
        function(filePath)
            ambient.stopSoundFile(filePath)
        end)
        updatePlaybackMarker()
    end
end

function Editor:setState(state)
    self.state = state
    self:destroyUI()
    self:createUI()
end

function Editor:setContent()
    if self.state == self.STATE.SONG then
        setMainContent(getSongManager())
        updatePianoRoll()
    elseif self.state == self.STATE.PERFORMANCE then
        setMainContent(uiTemplates.songManager)
    end
end

function Editor:createUI()
    local wrapper = uiTemplates.wrapper
    screenSize = ui.screenSize()
    self.windowXOff = self.state == self.STATE.SONG and 20 or (screenSize.x / 2)
    wrapper.content[1].props.size = util.vector2(screenSize.x-Editor.windowXOff, screenSize.y - Editor.windowYOff)
    wrapperElement = ui.create(wrapper)
    Editor:setContent()
end

function Editor:destroyUI()
    if wrapperElement then
        auxUi.deepDestroy(wrapperElement)
        wrapperElement = nil
    end
end

function Editor:onToggle()
    if self.active then
        self:destroyUI()
        self.active = false
        I.UI.removeMode(I.UI.MODE.Interface)
        core.sendGlobalEvent('Unpause', 'BO_Editor')
    else
        self:createUI()
        self.active = true
        I.UI.setMode(I.UI.MODE.Interface, {windows = {}})
        core.sendGlobalEvent('Pause', 'BO_Editor')
    end
end

function Editor:togglePlayback()
    if playback then
        stopPlayback()
        updatePlaybackMarker()
    else
        startPlayback()
    end
end

function Editor:onUINil()
    if self.active then
        --self:createUI()
        I.UI.setMode(I.UI.MODE.Interface, {windows = {}})
    else
        self.active = false
    end
end

local cacheCoroutine = nil
local cacheTicker = 0

local function cacheAllSoundsCoroutine()
    local profiles = Song.getInstrumentProfiles()
    for _, profile in pairs(profiles) do
        for j = 0, 127 do
            local filePath = 'sound\\Bardcraft\\samples\\' .. profile.name .. '\\' .. profile.name .. '_' .. Song.noteNumberToName(j) .. '.wav'
            ambient.playSoundFile(filePath, { volume = 0 })
            print("Caching sound file: " .. filePath)
            coroutine.yield()
        end
    end
end

function Editor:onFrame()
    if self.active and playback then
        tickPlayback(core.getRealFrameDuration())
    end
    if cacheCoroutine and coroutine.status(cacheCoroutine) ~= 'dead' then
        cacheTicker = cacheTicker + core.getRealFrameDuration()
        if cacheTicker > 0.1 then
            local status, err = coroutine.resume(cacheCoroutine)
            if not status then
                print("Error in cache coroutine: " .. err)
                cacheCoroutine = nil
            end
            cacheTicker = 0
        end
    end
end

function Editor:onMouseWheel(vertical)
    if pianoRollFocused then
        local changeAmt = vertical * 48
        if input.isShiftPressed() then
            pianoRollScrollX = util.clamp(pianoRollScrollX + changeAmt, -pianoRollScrollXMax, 0)
            if math.abs(pianoRollScrollX - pianoRollScrollLastPopulateX) > pianoRollScrollPopulateWindowSize then
                pianoRollScrollLastPopulateX = pianoRollScrollX
                populateNotes()
            end
        else
            pianoRollScrollY = util.clamp(pianoRollScrollY + changeAmt, -pianoRollScrollYMax, 0)
        end
        updatePianoRoll()
    end
end

function Editor:init()
    --cacheCoroutine = coroutine.create(cacheAllSoundsCoroutine)
    self.state = self.STATE.PERFORMANCE
    self.song = nil
    self.noteMap = nil
end

return Editor