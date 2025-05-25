local ui = require('openmw.ui')
local auxUi = require('openmw_aux.ui')
local I = require('openmw.interfaces')
local storage = require('openmw.storage')
local async = require('openmw.async')
local ambient = require('openmw.ambient')
local core = require('openmw.core')
local util = require('openmw.util')
local input = require('openmw.input')
local nearby = require('openmw.nearby')
local types = require('openmw.types')
local calendar = require('openmw_aux.calendar')
local self = require('openmw.self')

local l10n = core.l10n('Bardcraft')

local luaxp = require('scripts.Bardcraft.util.luaxp')
local Song = require('scripts.Bardcraft.util.song').Song
local Instruments = require('scripts.Bardcraft.instruments').Instruments

local Editor = {}

Editor.STATE = {
    PERFORMANCE = 0,
    SONG = 1,
    STATS = 2,
    MODAL = 3,
}

Editor.ZOOM_LEVELS = {
    [1] = 1/8,
    [2] = 1/4,
    [3] = 1/2,
    [4] = 1.0,
    [5] = 2.0,
    [6] = 4.0,
    [7] = 8.0,
}

Editor.SNAP_LEVELS = {
    [1] = 1/32,
    [2] = 1/16,
    [3] = 1/8,
    [4] = 1/6,
    [5] = 1/4,
    [6] = 1/3,
    [7] = 1/2,
    [8] = 1.0,
    [9] = 2.0,
    [10] = 4.0,
}

Editor.SONGS_MODE = {
    PRESET = "songs/preset",
    CUSTOM = "songs/custom"
}

Editor.active = false
Editor.song = nil
Editor.songs = nil
Editor.songsMode = Editor.SONGS_MODE.CUSTOM
Editor.state = nil
Editor.noteMap = nil
Editor.snap = true
Editor.snapLevel = 5
Editor.zoomLevel = 4
Editor.activePart = nil
Editor.partsPlaying = {}

Editor.deletePartIndex = nil
Editor.deletePartClickCount = 0
Editor.deletePartConfirmTimer = 0
Editor.deletePartConfirmResetTime = 1

Editor.windowXOff = 20
Editor.windowYOff = 200
Editor.windowCaptionHeight = 20
Editor.windowTabsHeight = 32
Editor.windowLeftBoxXMult = 1 / 16
Editor.windowLeftBoxXSize = 150
Editor.windowMiddleBoxXMult = 1 / 16
Editor.windowMiddleBoxXSize = 150

Editor.uiColors = {
    DEFAULT = util.color.rgb(202 / 255, 165 / 255, 96 / 255),
    DEFAULT_LIGHT = util.color.rgb(223 / 255, 201 / 255, 159 / 255),
    WHITE = util.color.rgb(1, 1, 1),
    GRAY = util.color.rgb(0.5, 0.5, 0.5),
    BLACK = util.color.rgb(0, 0, 0),
    CYAN = util.color.rgb(0, 1, 1),
    YELLOW = util.color.rgb(1, 1, 0),
    RED = util.color.rgb(1, 0, 0),
    DARK_RED = util.color.rgb(0.5, 0, 0),
    RED_DESAT = util.color.rgb(0.7, 0.3, 0.3),
    DARK_RED_DESAT = util.color.rgb(0.3, 0.05, 0.05),
    BOOK_HEADER = util.color.rgb(0.3, 0.03, 0.03),
    BOOK_TEXT = util.color.rgb(0.05, 0.05, 0.05),
    BOOK_TEXT_LIGHT = util.color.rgb(80 / 255, 64 / 255, 38 / 255),
}

Editor.noteColor = Editor.uiColors.DEFAULT
Editor.backgroundColor = Editor.uiColors.WHITE
Editor.keyboardColor = Editor.uiColors.WHITE
Editor.keyboardWhiteTextColor = Editor.uiColors.BLACK
Editor.keyboardBlackTextColor = Editor.uiColors.WHITE
Editor.beatLineColor = Editor.uiColors.DEFAULT_LIGHT
Editor.barLineColor = Editor.uiColors.DEFAULT_LIGHT
Editor.loopStartLineColor = Editor.uiColors.CYAN
Editor.loopEndLineColor = Editor.uiColors.CYAN
Editor.playbackLineColor = Editor.uiColors.YELLOW

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

local function uiButton(text, active, onClick)
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
                            textColor = active and Editor.uiColors.WHITE or Editor.uiColors.DEFAULT,
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
local modalElement = nil
local screenSize = nil
local playingNoteSound = nil

local onModalDecline = nil

local scrollableFocused = nil

function Editor:getScaleTexture()
    if not self.song then return end
    local modeName = Song.Mode[self.song.scale.mode]
    return ui.texture {
        path = 'textures/bardcraft/ui/scales/' .. modeName .. '.dds',
        size = util.vector2(4, 192),
    }
end

local textFocused = false

local DragType = {
    NONE = 0,
    RESIZE_LEFT = 1,
    RESIZE_RIGHT = 2,
    MOVE = 3,
}

local pianoRoll = {
    scrollX = 0,
    scrollY = 0,
    scrollXMax = 0,
    scrollYMax = 0,
    scrollLastPopulateX = 0,
    scrollPopulateWindowSize = 400,
    focused = false,
    wrapper = nil,
    keyboardWrapper = nil,
    editorWrapper = nil,
    editorMarkersWrapper = nil,
    element = nil,
    activeNote = nil,
    lastNoteSize = 0,
    dragStart = nil,
    dragOffset = nil,
    dragType = DragType.NONE,
    dragLastNoteSize = 0,
}

local playback = false
local playbackStartScrollX = 0

local function getNoteSoundPath(note)
    if not Editor.activePart then return '' end
    local profile = Song.getInstrumentProfile(Editor.activePart.instrument)
    local filePath = 'sound\\Bardcraft\\samples\\' .. profile.name .. '\\' .. profile.name .. '_' .. Song.noteNumberToName(note) .. '.wav'
    return filePath
end

local function playNoteSound(note)
    ambient.playSoundFile(getNoteSoundPath(note))
end

local function stopNoteSound(note)
    ambient.stopSoundFile(getNoteSoundPath(note))
end

--[[local ZoomLevels = {
    [1] = 1.0,
    [2] = 2.0,
    [3] = 4.0,
}]]

-- This is a necessary optimization so that we don't have to render an image for each beat line (insanely taxing on performance)
local uiWholeNoteWidth = 256

local function calcBeatWidth(denominator)
    return uiWholeNoteWidth / denominator * Editor.ZOOM_LEVELS[Editor.zoomLevel]
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
    local width = windowWidth - ((screenSize.x * Editor.windowLeftBoxXMult + Editor.windowLeftBoxXSize) + (screenSize.x * Editor.windowMiddleBoxXMult + Editor.windowMiddleBoxXSize)) - 8
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

local function calcSnapFactor()
    if not Editor.song or not Editor.snap then return 1 end
    return Editor.song.resolution * Editor.SNAP_LEVELS[Editor.snapLevel] * (4 / Editor.song.timeSig[2])
end

local function editorOffsetToRealOffset(offset)
    return offset - util.vector2(pianoRoll.scrollX, pianoRoll.scrollY)
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
    local highestNote = 128 - math.floor(-pianoRoll.scrollY / 16)
    local lowestNote = math.floor(util.clamp(highestNote - (calcPianoRollEditorWrapperSize().y / 16), 1, 128))
    local notesToShow = {table.unpack(notesLayout, (129 - highestNote), (129 - lowestNote))}
    pianoRoll.keyboardWrapper.layout.content[1].content[2].content = ui.content(notesToShow)
    pianoRoll.keyboardWrapper.layout.content[1].content[2].props.position = util.vector2(0, 16 * (128 - highestNote))
    pianoRoll.keyboardWrapper:update()
end

local function updatePianoRollBarNumberLabels()
    -- First, calculate which bar lines are visible
    local barWidth = calcBarWidth()
    local editorSize = calcPianoRollEditorWrapperSize()
    local barCount = math.floor(editorSize.x / barWidth) + 1
    local barLines = {
        type = ui.TYPE.Widget,
        props = {
            size = editorSize,
        },
        content = ui.content {},
    }
    for i = 0, barCount do
        local xOffset = i * barWidth + pianoRoll.scrollX % barWidth
        local barNumber = i + math.floor((-pianoRoll.scrollX - (1 * Editor.ZOOM_LEVELS[Editor.zoomLevel])) / barWidth) + 2
        table.insert(barLines.content, {
            type = ui.TYPE.Widget,
            props = {
                size = util.vector2(96, 16),
                position = util.vector2(xOffset + 4, 0),
            },
            content = ui.content {
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = tostring(barNumber),
                        textSize = 16,
                        textColor = Editor.uiColors.DEFAULT_LIGHT,
                    },
                },
            }
        })
    end
    pianoRoll.editorMarkersWrapper.layout.content[2] = barLines
end

local editorOverlay, editorMarkers, editorNotes = nil, nil, nil

local function updatePianoRoll()
    if not Editor.song then return end
    if not pianoRoll.wrapper or not pianoRoll.editorWrapper or not pianoRoll.editorWrapper.layout or not pianoRoll.editorMarkersWrapper or not pianoRoll.editorMarkersWrapper.layout then return end
    local barWidth = calcBarWidth()
    local octaveHeight = calcOctaveHeight()
    pianoRoll.keyboardWrapper.layout.content[1].props.position = util.vector2(0, pianoRoll.scrollY)
    updatePianoRollKeyboardLabels()
    updatePianoRollBarNumberLabels()
    
    editorOverlay.props.position = util.vector2(pianoRoll.scrollX % barWidth - barWidth, pianoRoll.scrollY % octaveHeight - octaveHeight)
    editorMarkers.props.position = util.vector2(pianoRoll.scrollX, 0)
    editorNotes.props.position = util.vector2(pianoRoll.scrollX, pianoRoll.scrollY)
    pianoRoll.editorMarkersWrapper:update()
    pianoRoll.editorWrapper:update()
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
local addDraft, saveDraft, setDraft

local uiTemplates

uiTemplates = {
    wrapper = function() 
        return {
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
                                                        uiButton(l10n('UI_Tab_Performance'), Editor.state == Editor.STATE.PERFORMANCE, function()
                                                            Editor:setState(Editor.STATE.PERFORMANCE)
                                                        end),
                                                        uiButton(l10n('UI_Tab_Stats'), Editor.state == Editor.STATE.STATS, function()
                                                            Editor:setState(Editor.STATE.STATS)
                                                        end),
                                                        uiButton(l10n('UI_Tab_Songwriting'), Editor.state == Editor.STATE.SONG, function()
                                                            Editor:setState(Editor.STATE.SONG)
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
        } 
    end,
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
                    size = util.vector2(ui.screenSize().x * Editor.windowLeftBoxXMult + Editor.windowLeftBoxXSize, 0),
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
                    size = util.vector2(ui.screenSize().x * Editor.windowMiddleBoxXMult + Editor.windowMiddleBoxXSize, 0),
                    relativeSize = util.vector2(0, 1),
                },
                content = ui.content {
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            horizontal = true,
                            autoSize = false,
                            relativeSize = util.vector2(1, 1),
                        },
                        content = ui.content {
                            createPaddingTemplate(4),
                            {
                                type = ui.TYPE.Flex,
                                props = {
                                    autoSize = false,
                                    grow = 1,
                                    stretch = 1
                                },
                                external = {
                                    grow = 1,
                                    stretch = 1,
                                },
                                content = ui.content {},
                            },
                            createPaddingTemplate(4),
                        },
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
                        pianoRoll.focused = true
                    end),
                    focusLoss = async:callback(function()
                        pianoRoll.focused = false
                    end),
                }
            }
        }
    },
    baseTab = {
        type = ui.TYPE.Flex,
        props = {
            autoSize = false,
            relativeSize = util.vector2(1, 1),
        },
        content = ui.content {
            {
                template = I.MWUI.templates.borders,
                props = {
                    relativeSize = util.vector2(1, 1),
                },
                content = ui.content {
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            autoSize = false,
                            relativeSize = util.vector2(1, 1),
                            grow = 1,
                            stretch = 1,
                            arrange = ui.ALIGNMENT.Center,
                        },
                        content = ui.content {},
                    },
                },
            },
        }
    },
    textEdit = function(default, height, callback)
        return {
            template = I.MWUI.templates.borders,
            props = {
                size = util.vector2(0, height),
            },
            external = {
                grow = 1,
                stretch = 1,
            },
            content = ui.content {
                {
                    template = I.MWUI.templates.textEditLine,
                    props = {
                        text = default,
                        textAlignV = ui.ALIGNMENT.Center,
                        relativeSize = util.vector2(1, 1),
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
            },
        }
    end,
    labeledTextEdit = function(label, default, height, callback)
        return {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                autoSize = false,
                size = util.vector2(0, height),
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
                uiTemplates.textEdit(default, height, callback),
            },
        }
    end,
    select = function(items, index, addSize, localize, height, callback)
        local leftArrow = ui.texture {
            path = 'textures/omw_menu_scroll_left.dds',
        }
        local rightArrow = ui.texture {
            path = 'textures/omw_menu_scroll_right.dds',
        }
        local itemCount = #items

        local function getLabel()
            local label = items[index]
            if type(label) == 'number' then
                -- Round to 8 decimal places
                label = math.floor(label * 1e8 + 0.5) / 1e8
            end
            if localize then
                label = l10n('UI_' .. label)
            end
            return tostring(label)
        end

        local label = getLabel()
        local labelColor = nil
        if index == nil then
            labelColor = util.color.rgb(1, 0, 0)
        end
        local element = ui.create {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                autoSize = false,
                size = util.vector2(addSize, height),
                arrange = ui.ALIGNMENT.Center,
                selected = index,
            },
            external = {
                grow = 1,
                stretch = 1,
            },
            content = ui.content {
                {
                    type = ui.TYPE.Image,
                    props = {
                        resource = leftArrow,
                        size = util.vector2(1, 1) * 12,
                    },
                    events = {},
                },
                { template = I.MWUI.templates.interval },
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = label,
                        textColor = labelColor,
                    },
                    external = {
                        grow = 1,
                    },
                },
                { template = I.MWUI.templates.interval },
                {
                    type = ui.TYPE.Image,
                    props = {
                        resource = rightArrow,
                        size = util.vector2(1, 1) * 12,
                    },
                    events = {},
                },
            },
        }

        local function update()
            element.layout.props.selected = index
            element.layout.content[3].props.text = getLabel()
            callback(index)
            element:update()
        end

        element.layout.content[1].events.mouseClick = async:callback(function()
            index = (index - 2) % itemCount + 1
            update()
        end)
        element.layout.content[5].events.mouseClick = async:callback(function()
            index = (index) % itemCount + 1
            update()
        end)

        return element
    end,
    labeledSelect = function(label, items, index, addSize, localize, height, callback)
        return {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                autoSize = false,
                size = util.vector2(0, height),
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
                uiTemplates.select(items, index, addSize, localize, height, callback),
            },
        }
    end,
    checkbox = function(value, trueLabel, falseLabel, onChange)
        local function getLabel()
            return l10n('UI_' .. (value and trueLabel or falseLabel))
        end

        local element = ui.create {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                arrange = ui.ALIGNMENT.Center,
            },
            content = ui.content {
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = getLabel(),
                        textAlignV = ui.ALIGNMENT.Center,
                    },
                },
            },
            events = {
            }
        }

        element.layout.events.mouseClick = async:callback(function()
            value = not value
            element.layout.content[1].props.text = getLabel()
            if onChange then
                onChange(value)
            end
            element:update()
        end)
        return element
    end,
    partDisplay = function(part)
        local function getInstruments()
            local instruments = {}
            for k, _ in pairs(Instruments) do
                table.insert(instruments, k)
            end
            return instruments
        end

        local instruments = getInstruments()

        local function indexOf(table, i)
            for k, v in ipairs(table) do
                if v == i then
                    return k
                end
            end
            return nil
        end

        local function getInstrumentName()
            return Song.getInstrumentProfile(part.instrument).name
        end

        local partDisplay = ui.create {
            template = (part == Editor.activePart) and I.MWUI.templates.bordersThick or I.MWUI.templates.borders,
            props = {
                size = util.vector2(0, 48),
            },
            external = {
                stretch = 1,
            },
            content = ui.content {
                {
                    type = ui.TYPE.Flex,
                    props = {
                        horizontal = true,
                        autoSize = false,
                        size = util.vector2(0, 44),
                        relativeSize = util.vector2(1, 0),
                        arrange = ui.ALIGNMENT.Center,
                    },
                    content = ui.content {
                        {
                            type = ui.TYPE.Image,
                            props = {
                                resource = ui.texture { path = Instruments[getInstrumentName()].icon },
                                size = util.vector2(40, 40),
                            },
                            events = {}
                        },
                        {
                            type = ui.TYPE.Flex,
                            external = {
                                grow = 1,
                                stretch = 1,
                            },
                            content = ui.content {}
                        },
                        {
                            template = I.MWUI.templates.borders,
                            props = {
                                size = util.vector2(24, 0),
                            },
                            external = {
                                stretch = 1,
                            },
                            content = ui.content {
                                {
                                    type = ui.TYPE.Image,
                                    props = {
                                        anchor = util.vector2(0.5, 0.5),
                                        relativePosition = util.vector2(0.5, 0.5),
                                        resource = ui.texture { path = 'textures/Bardcraft/ui/' .. (Editor.partsPlaying[part.index] and 'part-vol-on.dds' or 'part-vol-off.dds') },
                                        color = Editor.uiColors.DEFAULT,
                                        alpha = Editor.partsPlaying[part.index] and 1 or 0.5,
                                        size = util.vector2(16, 16),
                                    }
                                }
                            },
                            events = {}
                        },
                        {
                            template = I.MWUI.templates.borders,
                            props = {
                                size = util.vector2(24, 0),
                            },
                            external = {
                                stretch = 1,
                            },
                            content = ui.content {
                                {
                                    type = ui.TYPE.Image,
                                    props = {
                                        anchor = util.vector2(0.5, 0.5),
                                        relativePosition = util.vector2(0.5, 0.5),
                                        resource = ui.texture { path = 'textures/Bardcraft/ui/part-delete.dds' },
                                        color = Editor.uiColors.RED_DESAT,
                                        size = util.vector2(16, 16),
                                    }
                                }
                            },
                            events = {
                                mouseClick = async:callback(function()
                                    if Editor.deletePartClickCount >= 2 then
                                        Editor.deletePartClickCount = 0
                                        if part == Editor.activePart then
                                            Editor.activePart = nil
                                        end
                                        if part then
                                            Editor.song:removePart(part.index)
                                            saveDraft()
                                            Editor:destroyUI()
                                            Editor:createUI()
                                        end
                                        return
                                    end
                                    if Editor.deletePartIndex ~= part.index then
                                        Editor.deletePartIndex = part.index
                                        Editor.deletePartClickCount = 0
                                    end
                                    Editor.deletePartClickCount = Editor.deletePartClickCount + 1
                                    Editor.deletePartConfirmTimer = Editor.deletePartConfirmResetTime
                                    ui.showMessage(l10n('UI_PRoll_DeletePartMsg'):gsub('%%{count}', tostring(3 - Editor.deletePartClickCount)))
                                end),
                            }
                        }
                    }
                }
            },
        }

        partDisplay.layout.content[1].content[3].events.mousePress = async:callback(function(e)
            -- Left mouse button: Mute/unmute, Right mouse button: Toggle solo
            if e.button == 1 then
                Editor.partsPlaying[part.index] = not Editor.partsPlaying[part.index]
                partDisplay.layout.content[1].content[3].content[1].props.resource = ui.texture { path = 'textures/Bardcraft/ui/' .. (Editor.partsPlaying[part.index] and 'part-vol-on.dds' or 'part-vol-off.dds') }
                partDisplay.layout.content[1].content[3].content[1].props.alpha = Editor.partsPlaying[part.index] and 1 or 0.5
                partDisplay:update()
            elseif e.button == 3 then
                local soloCount = 0
                local targetSoloed = false
                for i, isPlaying in pairs(Editor.partsPlaying) do
                    if isPlaying then
                        soloCount = soloCount + 1
                        if i == part.index then
                            targetSoloed = true
                        end
                    end
                end

                if soloCount == 1 and targetSoloed then
                    for i, _ in pairs(Editor.partsPlaying) do
                        Editor.partsPlaying[i] = true
                    end
                else
                    for i, _ in pairs(Editor.partsPlaying) do
                        Editor.partsPlaying[i] = i == part.index
                    end
                end
                
                Editor:destroyUI()
                Editor:createUI()
            end
        end)

        partDisplay.layout.content[1].content[1].events.mouseClick = async:callback(function()
            Editor.activePart = part
            Editor:destroyUI()
            Editor:createUI()
        end)

        partDisplay.layout.content[1].content[2].content = ui.content {
            uiTemplates.textEdit(part.title, 20, function(text, this)
                if text ~= part.title then
                    part.title = text
                    this.props.text = text
                    saveDraft()
                end
            end),
            uiTemplates.select(instruments, indexOf(instruments, getInstrumentName()), 0, true, 20, function(index)
                local instrumentName = instruments[index]
                local instrumentNumber = Song.getInstrumentNumber(instrumentName)
                if instrumentNumber ~= part.instrument then
                    part.instrument = instrumentNumber
                    saveDraft()
                    partDisplay.layout.content[1].content[1].props.resource = ui.texture { path = Instruments[instrumentName].icon }
                    partDisplay:update()
                end
            end),
        }
        return partDisplay
    end,
    partDisplaySmall = function(part, itemHeight, thickBorders, confidence, onClick)
        local function getInstrumentName()
            return Song.getInstrumentProfile(part.instrument).name
        end

        -- Generate RGB from confidence; 0 is gray, then blend from red to green
        local function blendRedToGreen(value)
            -- Input validation:  Check if the input is within the valid range.
            if not value or value < 0 or value > 1 then
                -- Return a default gray color for invalid input.  This is robust.
                return util.color.rgb(0.5, 0.5, 0.5)
            end
          
            if value == 0 then
                -- Return gray for value of 0
                return util.color.rgb(0.5, 0.5, 0.5)
            else
                -- Blend from red to green
                local red = 1 - value
                local green = value
                local blue = 0 -- Blue component is always 0 in this blend.
                return util.color.rgb(red, green, blue)
            end
        end
        local color = blendRedToGreen(confidence / 100)

        local partDisplaySmall = ui.create {
            template = (thickBorders and I.MWUI.templates.bordersThick or I.MWUI.templates.borders),
            props = {
                size = util.vector2(0, itemHeight),
            },
            external = {
                stretch = 1,
            },
            content = ui.content {
                thickBorders and {
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture { path = 'white', },
                        relativeSize = util.vector2(1, 1),
                        color = Editor.uiColors.BLACK,
                        alpha = 0.5,
                    }
                } or {},
                {
                    type = ui.TYPE.Flex,
                    props = {
                        horizontal = true,
                        autoSize = false,
                        size = util.vector2(0, itemHeight),
                        relativeSize = util.vector2(1, 0),
                        arrange = ui.ALIGNMENT.Center,
                    },
                    content = ui.content {
                        {
                            type = ui.TYPE.Image,
                            props = {
                                resource = ui.texture { path = Instruments[getInstrumentName()].icon },
                                size = util.vector2(itemHeight - 8, itemHeight - 8),
                            },
                        },
                        {
                            template = createPaddingTemplate(4),
                        },
                        {
                            type = ui.TYPE.Flex,
                            external = {
                                grow = 1,
                                stretch = 1,
                            },
                            content = ui.content {
                                {
                                    template = I.MWUI.templates.textNormal,
                                    props = {
                                        text = part.title,
                                        textColor = thickBorders and Editor.uiColors.WHITE or Editor.uiColors.DEFAULT,
                                    },
                                },
                                {
                                    template = I.MWUI.templates.textNormal,
                                    props = {
                                        text = l10n('UI_PartConfidence'):gsub('%%{confidence}', string.format('%.2f', confidence)),
                                        textColor = color,
                                    },
                                }
                            }
                        }
                    }
                }
            },
            events = {
                mouseClick = async:callback(function()
                    if onClick then
                        onClick()
                    end
                end),
            }
        }
        
        return partDisplaySmall
    end,
    songDisplay = function(song, itemHeight, thickBorders, onClick)
        local stars = {}
        if song.difficulty == "starter" then
            table.insert(stars, {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture { path = "textures/Bardcraft/ui/star-half.dds", size = util.vector2(26, 25) },
                    size = util.vector2(26, 25),
                }
            })
        elseif song.difficulty == "beginner" or song.difficulty == "intermediate" or song.difficulty == "advanced" then
            local count = ({ beginner = 1, intermediate = 2, advanced = 3 })[song.difficulty] or 0
            for i = 1, count do
                table.insert(stars, {
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture { path = "textures/Bardcraft/ui/star-full.dds", size = util.vector2(26, 25) },
                        size = util.vector2(26, 25),
                    }
                })
            end
        end

        local starRow = {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                align = ui.ALIGNMENT.Center,
                anchor = util.vector2(1, 0.5),
                relativePosition = util.vector2(1, 0.5),
                position = util.vector2(-8, 0),
            },
            content = ui.content(stars),
        }

        return {
            template = (thickBorders and I.MWUI.templates.bordersThick or I.MWUI.templates.borders),
            props = {
                size = util.vector2(0, itemHeight),
            },
            external = {
                stretch = 1,
            },
            content = ui.content {
                {
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture { 
                            path = 'textures/Bardcraft/ui/songbgr/' .. song.texture .. '.dds',
                            offset = util.vector2(0, 32),
                            size = util.vector2(0, 64),
                        },
                        relativeSize = util.vector2(1, 1),
                    },
                },
                {
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture { 
                            path = 'textures/Bardcraft/ui/songbgr-overlay.dds',
                            offset = util.vector2(0, 32),
                            size = util.vector2(0, 64),
                        },
                        relativeSize = util.vector2(1, 1),
                    },
                },
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = song.title,
                        textColor = thickBorders and Editor.uiColors.WHITE or Editor.uiColors.DEFAULT,
                        anchor = util.vector2(0, 0.5),
                        relativePosition = util.vector2(0, 0.5),
                        position = util.vector2(8, 0),
                    },
                },
                starRow
            },
            events = {
                mouseClick = async:callback(function()
                    if onClick then
                        onClick()
                    end
                end),
            }
        }
    end,
    performerDisplay = function(npc, itemHeight, thickBorders, onClick)
        local name = types.NPC.record(npc).name
        local performerInfo = Editor.performersInfo[npc.id]
        local level = performerInfo and performerInfo.performanceSkill and performerInfo.performanceSkill.level or 1

        return {
            template = (thickBorders and I.MWUI.templates.bordersThick or I.MWUI.templates.borders),
            props = {
                size = util.vector2(0, itemHeight),
            },
            external = {
                stretch = 1,
            },
            content = ui.content {
                thickBorders and {
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture { path = 'white', },
                        relativeSize = util.vector2(1, 1),
                        color = Editor.uiColors.BLACK,
                        alpha = 0.5,
                    }
                } or {},
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = name,
                        textColor = thickBorders and Editor.uiColors.WHITE or Editor.uiColors.DEFAULT,
                        position = util.vector2(8, 0),
                        anchor = util.vector2(0, 0.5),
                        relativePosition = util.vector2(0, 0.5),
                        size = util.vector2(0, itemHeight),
                    },
                },
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = "Lv. " .. tostring(level),
                        textColor = thickBorders and Editor.uiColors.WHITE or Editor.uiColors.DEFAULT,
                        textSize = 24,
                        anchor = util.vector2(1, 0.5),
                        relativePosition = util.vector2(1, 0.5),
                        position = util.vector2(-8, 0),
                        size = util.vector2(0, itemHeight),
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
    end,
    button = function(text, size, callback)
        return {
            template = I.MWUI.templates.bordersThick,
            props = {
                size = size or util.vector2(0, 0),
            },
            content = ui.content {
                {
                    type = ui.TYPE.Flex,
                    props = {
                        autoSize = false,
                        relativeSize = util.vector2(1, 1),
                        arrange = ui.ALIGNMENT.Center,
                        align = ui.ALIGNMENT.Center,
                    },
                    content = ui.content {
                        {
                            template = I.MWUI.templates.textNormal,
                            props = {
                                text = text,
                            },
                        },
                    },
                },
            },
            events = {
                mousePress = async:callback(function()
                    if callback then
                        callback()
                    end
                end),
            }
        }
    end,
    scrollable = function(size, content, flexSize)
        local scrollLimit = flexSize and (flexSize.y - size.y) or math.huge
        local canScroll
        if flexSize then
            canScroll = flexSize.y > size.y
        else
            canScroll = true
        end
        local scrollWidget = ui.create {
            template = I.MWUI.templates.borders,
            props = {
                size = size,
                scrollLimit = scrollLimit,
                canScroll = canScroll,
            },
            content = ui.content {
                {
                    type = ui.TYPE.Flex,
                    props = {
                        autoSize = flexSize == nil,
                        size = flexSize or util.vector2(0, 0),
                        relativeSize = flexSize and util.vector2(1, 0) or util.vector2(0, 0),
                        position = util.vector2(0, 0),
                    },
                    content = content or ui.content{},
                }
            },
        }
        scrollWidget.layout.events = {
            focusGain = async:callback(function()
                scrollableFocused = scrollWidget
            end),
            focusLoss = async:callback(function(self)
                if scrollableFocused == scrollWidget then
                    scrollableFocused = nil
                end
            end),
        }
        return scrollWidget
    end,
    pianoRollKeyboard = function(timeSig)
        local bar = {
            type = ui.TYPE.Widget,
            props = {
                size = util.vector2(96, calcPianoRollEditorHeight()),
                position = util.vector2(0, pianoRoll.scrollY)
            },
            content = ui.content {},
            events = {
                mouseMove = async:callback(function(e)
                    if e.button == 1 and Editor.activePart then
                        local noteIndex = math.floor((128 - (e.offset.y / 16)))
                        --[[local octave = math.floor(noteIndex / 12) - 1
                        local noteNames = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
                        local noteName = noteNames[(noteIndex % 12) + 1]
                        local fileName = 'sound\\Bardcraft\\samples\\Lute\\Lute_' .. noteName .. octave .. '.wav']]
                        local fileName = getNoteSoundPath(noteIndex)
                        if playingNoteSound ~= fileName then
                            ambient.playSoundFile(fileName)
                            if playingNoteSound and Song.getInstrumentProfile(Editor.activePart.instrument).sustain then
                                ambient.stopSoundFile(playingNoteSound)
                            end
                            playingNoteSound = fileName
                        end
                    end
                end),
                mousePress = async:callback(function(e)
                    if e.button == 1 and Editor.activePart then
                        local noteIndex = math.floor((128 - (e.offset.y / 16)))
                        --[[local octave = math.floor(noteIndex / 12) - 1
                        local noteNames = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
                        local noteName = noteNames[(noteIndex % 12) + 1]
                        local fileName = 'sound\\Bardcraft\\samples\\Lute\\Lute_' .. noteName .. octave .. '.wav']]
                        local fileName = getNoteSoundPath(noteIndex)
                        ambient.playSoundFile(fileName)
                        playingNoteSound = fileName
                    end
                end),
                mouseRelease = async:callback(function(e)
                    if e.button == 1 and Editor.activePart then
                        if playingNoteSound and Song.getInstrumentProfile(Editor.activePart.instrument).sustain then
                            ambient.stopSoundFile(playingNoteSound)
                        end
                    end
                end),
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
                position = util.vector2(pianoRoll.scrollX % barWidth - barWidth, pianoRoll.scrollY % calcOctaveHeight() - calcOctaveHeight())
            },
            content = ui.content {},
        }
        
        editorOverlay.content:add({
            type = ui.TYPE.Image,
            name = 'bgrRows',
            props = {
                resource = Editor:getScaleTexture(),
                relativeSize = util.vector2(1, 1),
                position = util.vector2(0, -16 * (Editor.song.scale.root - 1)),
                size = util.vector2(0, 16 * (Editor.song.scale.root - 1)),
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
        if Editor.zoomLevel > 1 then
            editorOverlay.content:add({
                type = ui.TYPE.Image,
                name = 'bgrBars',
                props = {
                    resource = uiTextures.pianoRollBeatLines[timeSig[2] / (Editor.ZOOM_LEVELS[Editor.zoomLevel])],
                    relativeSize = util.vector2(1, 1),
                    tileH = true,
                    tileV = true,
                    color = Editor.beatLineColor,
                    alpha = 0.3,
                },
            })
        end

        local editorMarkers = {
            type = ui.TYPE.Widget,
            name = 'pianoRollMarkers',
            props = {
                size = util.vector2(totalWidth, calcPianoRollEditorHeight()),
                position = util.vector2(pianoRoll.scrollX, 0),
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

        pianoRoll.editorMarkersWrapper = ui.create {
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
                position = util.vector2(pianoRoll.scrollX, pianoRoll.scrollY)
            },
            content = ui.content {},
        }
        editor.content:add(editorOverlay)
        editor.content:add(pianoRoll.editorMarkersWrapper)
        editor.content:add(editorNotes)
        return editor
    end,
    pianoRollNote = function(id, note, tick, duration, active)
        local noteWidth = calcBeatWidth(Editor.song.timeSig[2]) * (Editor.song:tickToBeat(duration))
        local noteHeight = calcOctaveHeight() / 12
        local noteX = calcBeatWidth(Editor.song.timeSig[2]) * (Editor.song:tickToBeat(tick))
        local noteY = (127 - note) * noteHeight
        if active == nil then
            active = true
        end
        local noteLayout = {
            type = ui.TYPE.Image,
            name = tostring(id),
            props = {
                active = active,
                resource = uiTextures.pianoRollNote,
                size = util.vector2(noteWidth, noteHeight),
                tileH = true,
                tileV = false,
                color = Editor.noteColor,
                position = util.vector2(noteX, noteY),
            },
            events = {}
        }
        if active then
            noteLayout.events.mousePress = async:callback(function(e, self)
                if not self.props.active then return end
                if e.button == 3 then
                    removeNote(self)
                    saveNotes()
                    return
                end
                if e.button == 1 then
                    pianoRoll.lastNoteSize = duration
                    pianoRoll.activeNote = tonumber(self.name)
                    pianoRoll.dragStart = editorOffsetToRealOffset(self.props.position + e.offset)
                    local resizeArea = math.min(8, noteWidth / 2)
                    local distFromEnd = noteWidth - e.offset.x
                    if distFromEnd < resizeArea then
                        pianoRoll.dragType = DragType.RESIZE_RIGHT
                        pianoRoll.dragOffset = util.vector2(0, 0)
                    else
                        pianoRoll.dragType = DragType.MOVE
                        pianoRoll.dragOffset = -e.offset
                    end
                    playNoteSound(note)
                end
            end)
            noteLayout.events.mouseRelease = async:callback(function()
                if not Editor.activePart then return end
                if not Song.getInstrumentProfile(Editor.activePart.instrument).sustain then return end
                stopNoteSound(note)
            end)
        end
        return noteLayout
    end,
    modal = function(content, size, title)
        return {
            layer = "Windows",
            props = {
                relativeSize = util.vector2(1, 1), -- take up the whole screen so players can't click anything else
            },
            content = ui.content {
                {
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture { path = 'white' },
                        size = util.vector2(0, 0),
                        relativeSize = util.vector2(1, 1),
                        color = Editor.uiColors.BLACK,
                        alpha = 0.5,
                    }
                },
                {
                    template = I.MWUI.templates.boxSolidThick,
                    props = {
                        size = size,
                        anchor = util.vector2(0.5, 0.5),
                        relativePosition = util.vector2(0.5, 0.5),
                    },
                    content = ui.content {
                        {
                            type = ui.TYPE.Flex,
                            props = {
                                autoSize = false,
                                size = size,
                            }, 
                            content = ui.content {
                                title and {
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
                                                text = '   ' .. title .. '   ',
                                            }
                                        },
                                        headerSection,
                                    },
                                } or {},
                                {
                                    template = I.MWUI.templates.bordersThick,
                                    external = {
                                        grow = 1,
                                        stretch = 1,
                                    },
                                    content = ui.content { content },
                                },
                            }
                        }
                    }
                }
            }
        }
    end,
    confirmModal = function(onConfirm)
        return uiTemplates.modal(
            {
                type = ui.TYPE.Flex,
                props = {
                    autoSize = false,
                    relativeSize = util.vector2(1, 1),
                    arrange = ui.ALIGNMENT.Center,
                },
                content = ui.content {
                    createPaddingTemplate(16),
                    {
                        template = I.MWUI.templates.textNormal,
                        props = {
                            text = "Are you sure?",
                            textAlignH = ui.ALIGNMENT.Center,
                        },
                    },
                    createPaddingTemplate(16),
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            horizontal = true,
                            autoSize = false,
                            relativeSize = util.vector2(1, 0),
                            size = util.vector2(0, 32),
                            align = ui.ALIGNMENT.Center,
                        },
                        content = ui.content {
                            uiTemplates.button("Yes", util.vector2(128, 32), function()
                                if onConfirm then
                                    onConfirm()
                                end
                                if modalElement then
                                    modalElement:destroy()
                                    modalElement = nil
                                end
                            end),
                            {
                                template = I.MWUI.templates.interval,
                            },
                            uiTemplates.button("No", util.vector2(128, 32), function()
                                if modalElement then
                                    modalElement:destroy()
                                    modalElement = nil
                                end
                            end),
                        },
                    },
                    createPaddingTemplate(16),
                },
            },
            util.vector2(300, 150),
            "Confirmation"
        )
    end,
    choiceModal = function(title, choices)
        return uiTemplates.modal(
            {
                type = ui.TYPE.Flex,
                props = {
                    autoSize = false,
                    relativeSize = util.vector2(1, 1),
                    arrange = ui.ALIGNMENT.Center,
                },
                content = ui.content {
                    createPaddingTemplate(16),
                    {
                        template = I.MWUI.templates.textNormal,
                        props = {
                            text = title or "Choose an option:",
                            textAlignH = ui.ALIGNMENT.Center,
                        },
                    },
                    createPaddingTemplate(16),
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            horizontal = false,
                            autoSize = false,
                            relativeSize = util.vector2(1, 0),
                            align = ui.ALIGNMENT.Center,
                        },
                        content = (function()
                            local buttons = {}
                            for _, choice in ipairs(choices) do
                                table.insert(buttons, uiTemplates.button(choice.text, util.vector2(200, 32), function()
                                    if choice.callback then
                                        choice.callback()
                                    end
                                    if modalElement then
                                        modalElement:destroy()
                                        modalElement = nil
                                    end
                                end))
                                table.insert(buttons, createPaddingTemplate(8))
                            end
                            return buttons
                        end)(),
                    },
                    createPaddingTemplate(16),
                },
            },
            util.vector2(300, 200),
            title or "Choice"
        )
    end,
}

local function populateNotes()
    if not pianoRoll.editorWrapper then return end
    pianoRoll.editorWrapper.layout.content[1].content[3].content = ui.content{}
    for _, noteData in pairs(Editor.noteMap) do
        local active = not Editor.activePart or (noteData.part == Editor.activePart.index)
        local id = noteData.id
        local note = noteData.note
        local tick = noteData.time
        local duration = noteData.duration
        -- Check if note is within the viewing area
        local noteX = calcBeatWidth(Editor.song.timeSig[2]) * (Editor.song:tickToBeat(tick))
        local noteWidth = calcBeatWidth(Editor.song.timeSig[2]) * (Editor.song:tickToBeat(duration))
        local wrapperSize = calcPianoRollEditorWrapperSize()

        if noteX + noteWidth >= -pianoRoll.scrollX - pianoRoll.scrollPopulateWindowSize and noteX <= -pianoRoll.scrollX + pianoRoll.scrollPopulateWindowSize + wrapperSize.x then
            -- Add note to the piano roll
            local template = uiTemplates.pianoRollNote(id, note, tick, duration, active)
            template.props.alpha = active and 1 or 0.2
            template.props.active = active
            pianoRoll.editorWrapper.layout.content[1].content[3].content:add(template)
        end
        --pianoRoll.editorWrapper.layout.content[1].content[3].content:add(uiTemplates.pianoRollNote(id, note, tick, duration))
    end
    pianoRoll.editorWrapper:update()
end

addNote = function(note, tick, duration, active)
    if not Editor.song then return end
    duration = duration or Editor.song.resolution * (4 / Editor.song.timeSig[2])
    local id = #Editor.noteMap + 1
    local noteData = {
        id = id,
        note = note,
        velocity = 127,
        part = Editor.activePart.index,
        time = tick,
        duration = duration,
    }
    table.insert(Editor.noteMap, noteData)
    pianoRoll.editorWrapper.layout.content[1].content[3].content:add(uiTemplates.pianoRollNote(id, note, tick, duration, active))
    Editor.song.noteIdCounter = Editor.song.noteIdCounter + 1
    pianoRoll.editorWrapper:update()
    --[[table.sort(Editor.noteMap, function(a, b)
        return a.time < b.time
    end)]]
    return id
end

removeNote = function(element)
    if not Editor.song then return end
    local id = element.name
    if not id then return end
    for i, noteData in pairs(Editor.noteMap) do
        if noteData.id == tonumber(id) then
            --table.remove(Editor.noteMap, i)
            Editor.noteMap[i] = nil
            break
        end
    end
    local pianoRollNotes = pianoRoll.editorWrapper.layout.content[1].content[3].content
    for i, note in ipairs(pianoRollNotes) do
        if note.name == id then
            table.remove(pianoRollNotes, i)
            break
        end
    end
    pianoRoll.editorWrapper:update()
end

initNotes = function()
    if not Editor.song then return end
    Editor.noteMap = Editor.song:noteEventsToNoteMap(Editor.song.notes)
    populateNotes()
end

saveNotes = function()
    if not Editor.song then return end
    Editor.song.notes = Editor.song:noteMapToNoteEvents(Editor.noteMap)
    saveDraft()
end

local getSongTab, getPerformanceTab, getStatsTab

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
            if songData and songData ~= "" then
                local song = Song.decode(songData)
                if song then
                    setDraft(song)
                    saveDraft()
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
    setMainContent(getSongTab())
end

local function initPianoRoll()
    if not Editor.song then return end
    if calcPianoRollEditorWidth() > calcPianoRollEditorWrapperSize().x then
        pianoRoll.scrollXMax = calcPianoRollEditorWidth() - calcPianoRollEditorWrapperSize().x
    else
        pianoRoll.scrollXMax = 0
    end
    if calcPianoRollEditorHeight() > calcPianoRollEditorWrapperSize().y then
        pianoRoll.scrollYMax = calcPianoRollEditorHeight() - calcPianoRollEditorWrapperSize().y
    else
        pianoRoll.scrollYMax = 0
    end 
end

local alreadyRedrewThisFrame = false

local function redrawPianoRollEditor()
    if not Editor.song then return end
    if alreadyRedrewThisFrame then return end
    alreadyRedrewThisFrame = true
    if pianoRoll.editorWrapper and pianoRoll.editorWrapper.layout then
        auxUi.deepDestroy(pianoRoll.editorWrapper.layout)
    end
    initPianoRoll()
    updateSongManager()
    updatePianoRollKeyboardLabels()
    pianoRoll.editorWrapper.layout.content[1] = uiTemplates.pianoRollEditor()
    updatePianoRollBarNumberLabels()
    initNotes()

    editorOverlay = pianoRoll.editorWrapper.layout.content[1].content.pianoRollOverlay
    editorMarkers = pianoRoll.editorMarkersWrapper.layout.content.pianoRollMarkers
    editorNotes = pianoRoll.editorWrapper.layout.content[1].content.pianoRollNotes
end

local function stopSounds(instrument)
    local profile = Song.getInstrumentProfile(instrument)
    for j = 0, 127 do
        local filePath = 'sound\\Bardcraft\\samples\\' .. profile.name .. '\\' .. profile.name .. '_' .. Song.noteNumberToName(j) .. '.wav'
        if ambient.isSoundFilePlaying(filePath) then
            ambient.stopSoundFile(filePath)
        end
    end
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

local function startPlayback(fromStart)
    if not Editor.song then return end
    playback = true
    if fromStart then
        playbackStartScrollX = (pianoRoll.scrollX / Editor.ZOOM_LEVELS[Editor.zoomLevel])
    end
    Editor.song:resetPlayback()
    if not fromStart then
        Editor.song.playbackTickCurr = Editor.song:beatToTick(-pianoRoll.scrollX / calcBeatWidth(Editor.song.timeSig[2]))
        Editor.song.playbackTickPrev = Editor.song.playbackTickCurr
    end
end

local function stopPlayback()
    playback = false
    if playbackStartScrollX then
        pianoRoll.scrollX = util.clamp(playbackStartScrollX * Editor.ZOOM_LEVELS[Editor.zoomLevel], -pianoRoll.scrollXMax, 0)
        updatePianoRoll()
        pianoRoll.scrollLastPopulateX = pianoRoll.scrollX
        populateNotes()
        playbackStartScrollX = nil
    end
    Editor.song:resetPlayback()
    pianoRoll.editorMarkersWrapper:update()
    stopAllSounds()
end

setDraft = function(song)
    if song then
        Editor.song = song
        setmetatable(Editor.song, Song)
        Editor.activePart = nil
        pianoRoll.scrollX = 0
        local partKeys = {}
        for i, _ in pairs(Editor.song.parts) do
            if i ~= 0 then
                table.insert(partKeys, i)
            end
        end
        table.sort(partKeys, function(a, b)
            return a < b
        end)
        Editor.activePart = partKeys[1] and Editor.song.parts[partKeys[1]][1] or nil
        for _, part in pairs(Editor.song.parts) do
            Editor.partsPlaying[part.index] = true
        end
        redrawPianoRollEditor()
        stopPlayback()
        pianoRoll.lastNoteSize = Editor.song.resolution * (4 / Editor.song.timeSig[2])
    else
        Editor.song = nil
    end
end

saveDraft = function()
    local songs = storage.playerSection('Bardcraft'):getCopy('songs/drafts') or {}
    for i, song in ipairs(songs) do
        if song.id == Editor.song.id then
            songs[i] = Editor.song
            break
        end
    end
    storage.playerSection('Bardcraft'):set('songs/drafts', songs)
end

addDraft = function()
    local song = Song.new()
    local songs = storage.playerSection('Bardcraft'):getCopy('songs/drafts') or {}
    table.insert(songs, song)
    storage.playerSection('Bardcraft'):set('songs/drafts', songs)
    setDraft(song)
    setMainContent(getSongTab())
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

Editor.performanceSelectedSong = nil
Editor.performanceSelectedPerformer = nil
Editor.performanceSelectedPart = nil
Editor.performancePartAssignments = {}
Editor.performersInfo = {}
Editor.troupeMembers = {}
Editor.troupeSize = 0
Editor.canPerform = false

local function startPerformance(type)
    if Editor.performanceSelectedSong then
        local partCount = 0
        local performers = {}
        for id, part in pairs(Editor.performancePartAssignments) do
            table.insert(performers, { actorId = id, part = part })
            partCount = partCount + 1
        end
        if partCount == 0 then
            return
        end

        core.sendGlobalEvent('BO_StartPerformance', {
            song = Editor.performanceSelectedSong,
            performers = performers,
            type = type,
            playerStats = Editor.performersInfo[self.id],
        })
    end
end

local function getSongs()
    local merged = {}
    local presetSongs = storage.globalSection('Bardcraft'):getCopy(Editor.SONGS_MODE.PRESET) or {}
    local customSongs = storage.playerSection('Bardcraft'):getCopy(Editor.SONGS_MODE.CUSTOM) or {}
    for _, song in ipairs(presetSongs) do
        table.insert(merged, song)
    end
    for _, song in ipairs(customSongs) do
        table.insert(merged, song)
    end
    table.sort(merged, function(a, b)
        return a.title < b.title
    end)
    return merged
end

local function getDrafts()
    local drafts = {}
    local draftSongs = storage.playerSection('Bardcraft'):getCopy('songs/drafts') or {}
    for _, song in ipairs(draftSongs) do
        table.insert(drafts, song)
    end
    table.sort(drafts, function(a, b)
        return a.title < b.title
    end)
    return drafts
end

local function calcSheetMusicCost()
    if not Editor.song then return 0 end
    local lengthBars = Editor.song.lengthBars
    local cost = math.max(1, math.floor((lengthBars - 2) / 8) + 1) -- 1 sheet for every 8 bars + 2, minimum 1 sheet
    return cost
end

local function onFinalizeDraft(title, desc, cost)
    if not Editor.song then return false end

    -- Check if player has enough blanks
    local player = nearby.players[1]
    if not player then return false end
    local inv = player.type.inventory(player)
    if inv:countOf('r_bc_sheetmusic_blank') < cost then
        ui.showMessage(l10n('UI_Msg_PRoll_InsufficientBlanks'))
        return false
    end
    local used = 0
    for _, item in ipairs(inv:findAll('r_bc_sheetmusic_blank')) do
        local toRemove = math.min(item.count, cost - used)
        used = used + toRemove
        core.sendGlobalEvent('BC_ConsumeItem', { item = item, count = toRemove})
        if used >= cost then
            break
        end
    end

    local song = Editor.song
    song.title = title
    song.desc = desc
    song.id = song.title .. '_' .. os.time() + math.random(10000)
    song.texture = 'generic'

    local songs = storage.playerSection('Bardcraft'):getCopy('songs/custom') or {}
    for i, cSong in ipairs(songs) do
        if cSong.id == song.id then
            song.id = song.id .. '_' .. 1
            break
        end
    end
    table.insert(songs, song)
    storage.playerSection('Bardcraft'):set('songs/custom', songs)
    player:sendEvent('BC_FinalizeDraft', { song = song })
    return true
end

local draftTitle = nil
local draftDesc = nil

local function createFinalizeDraftModal()
    if modalElement then
        modalElement:destroy()
        modalElement = nil
    end

    draftTitle = Editor.song.title
    draftDesc = nil
    modalElement = ui.create(uiTemplates.modal(
    {
        type = ui.TYPE.Flex,
        props = {
            autoSize = false,
            relativeSize = util.vector2(1, 1),
            arrange = ui.ALIGNMENT.Center,
        },
        content = ui.content {
            uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongTitle'), draftTitle, 32, function(text)
                draftTitle = text
            end),
            createPaddingTemplate(8),
            {
                template = I.MWUI.templates.textHeader,
                props = {
                    text = l10n('UI_PRoll_SongDescription'),
                },
            },
            {
                template = I.MWUI.templates.borders,
                props = {
                    autoSize = false,
                    size = util.vector2(0, 100),
                    relativeSize = util.vector2(1, 0),
                },
                content = ui.content {
                    {
                        template = I.MWUI.templates.textEditBox,
                        props = {
                            wordWrap = true,
                            relativeSize = util.vector2(1, 1),
                            size = util.vector2(0, 0),
                        },
                        events = {
                            textChanged = async:callback(function(text)
                                draftDesc = text
                            end),
                        }
                    },
                },
            },
            {
                template = createPaddingTemplate(8),
            },
            {
                template = I.MWUI.templates.textNormal,
                props = {
                    text = l10n('UI_PRoll_DraftCost'):gsub('%%{amount}', tostring(calcSheetMusicCost())),
                    textAlignH = ui.ALIGNMENT.Center,
                },
            },
            {
                template = createPaddingTemplate(16),
            },
            {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                    autoSize = false,
                    relativeSize = util.vector2(1, 0),
                    size = util.vector2(0, 32),
                    align = ui.ALIGNMENT.Center,
                },
                content = ui.content {
                    uiTemplates.button(l10n('UI_Button_Confirm'), util.vector2(128, 32), function()
                        -- Confirm logic here
                        if onFinalizeDraft(draftTitle, draftDesc, calcSheetMusicCost()) then
                            modalElement:destroy()
                            modalElement = nil
                        end
                    end),
                    {
                        template = I.MWUI.templates.interval,
                    },
                    uiTemplates.button(l10n('UI_Button_Cancel'), util.vector2(128, 32), function()
                        modalElement:destroy()
                        modalElement = nil
                    end),
                },
            },
        },
    }, util.vector2(450, 400), l10n('UI_PRoll_FinalizeDraft')))
end

getSongTab = function()
    local manager = auxUi.deepLayoutCopy(uiTemplates.songManager)
    local leftBox = manager.content[1].content[1].content
    Editor.songs = getDrafts()
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
                    setDraft(song)
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
                            text = l10n('UI_PRoll_NewDraft'),
                            anchor = util.vector2(0.5, 0.5),
                            relativePosition = util.vector2(0.5, 0.5),
                        },
                    },
                },
                events = {
                    mouseClick = async:callback(function()
                        addDraft()
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
        local middleBox = manager.content[2].content[1].content[2].content

        table.insert(middleBox, createPaddingTemplate(8))
        table.insert(middleBox, {
            template = I.MWUI.templates.textHeader,
            props = {
                text = l10n('UI_PRoll_SongInfo'),
                textAlignH = ui.ALIGNMENT.Center,
                autoSize = false,
                relativeSize = util.vector2(1, 0),
                size = util.vector2(0, 32),
            },
        })

        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongTitle'), Editor.song.title, 32, function(text, self)
            if not tostring(text) then
                self.props.text = Editor.song.title
            else
                Editor.song.title = text
                saveDraft()
                redrawPianoRollEditor()
            end
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongTempo'), tostring(Editor.song.tempo), 32, function(text, self)
            if not tonumber(text) then
                self.props.text = tostring(Editor.song.tempo)
            else
                Editor.song.tempo = tonumber(text)
                saveDraft()
                redrawPianoRollEditor()
            end
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongTimeSig'), Editor.song.timeSig[1] .. '/' .. Editor.song.timeSig[2], 32, function(text, self)
            local timeSig = parseTimeSignature(text)
            if not timeSig then
                self.props.text = Editor.song.timeSig[1] .. '/' .. Editor.song.timeSig[2]
            elseif not numMatches(Editor.song.timeSig[1], timeSig[1]) or not numMatches(Editor.song.timeSig[2], timeSig[2]) then
                Editor.song.timeSig = timeSig
                saveDraft()
                redrawPianoRollEditor()
            end
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongLoopStart'), tostring(Editor.song.loopBars[1]), 32, function(text, self)
            local parsed = parseExp(text)
            if not parsed or parsed < 0 then
                self.props.text = tostring(Editor.song.loopBars[1])
            elseif not numMatches(Editor.song.loopBars[1], parsed) then
                Editor.song.loopBars[1] = parsed
                saveDraft()
                redrawPianoRollEditor()
            end
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongLoopEnd'), tostring(Editor.song.loopBars[2]), 32, function(text, self)
            local parsed = parseExp(text)
            if not parsed or parsed > Editor.song.lengthBars then
                self.props.text = tostring(Editor.song.loopBars[2])
            elseif not numMatches(Editor.song.loopBars[2], parsed) then
                Editor.song.loopBars[2] = parsed
                saveDraft()
                redrawPianoRollEditor()
            end
        end))
        table.insert(middleBox, uiTemplates.labeledTextEdit(l10n('UI_PRoll_SongEnd'), tostring(Editor.song.lengthBars), 32, function(text, self)
            local parsed = parseExp(text)
            if not parsed or parsed < 1 then
                self.props.text = tostring(Editor.song.lengthBars)
            elseif not numMatches(Editor.song.lengthBars, parsed) then
                Editor.song.lengthBars = parsed
                saveDraft()
                redrawPianoRollEditor()
            end
        end))

        local function updateEditorOverlayRows()
            local bgrRows = pianoRoll.editorWrapper.layout.content[1].content[1].content[1]
            if bgrRows then
                bgrRows.props.resource = Editor:getScaleTexture()
                bgrRows.props.position = util.vector2(0, -16 * (Editor.song.scale.root - 1))
                bgrRows.props.size = util.vector2(0, 16 * (Editor.song.scale.root - 1))
                pianoRoll.editorWrapper:update()
            end
        end

        local scaleSelect = {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                autoSize = false,
                relativeSize = util.vector2(1, 0),
                size = util.vector2(0, 32),
                arrange = ui.ALIGNMENT.Center,
                grow = 1,
                stretch = 1,
            },
            content = ui.content {
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = l10n('UI_PRoll_Scale'),
                        textAlignV = ui.ALIGNMENT.Center,
                    },
                },
                {
                    template = createPaddingTemplate(4),
                },
                uiTemplates.select(Song.Note, Editor.song.scale.root, 0, false, 32, function(newVal)
                    Editor.song.scale.root = newVal
                    updateEditorOverlayRows()
                    saveDraft()
                end),
                uiTemplates.select(Song.Mode, Editor.song.scale.mode, 75, true, 32, function(newVal)
                    Editor.song.scale.mode = newVal
                    updateEditorOverlayRows()
                    saveDraft()
                end)
            }
        }
        table.insert(middleBox, scaleSelect)

        local snapSelect = {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                autoSize = false,
                relativeSize = util.vector2(1, 0),
                size = util.vector2(0, 32),
                arrange = ui.ALIGNMENT.Center,
                grow = 1,
                stretch = 1,
            },
            content = ui.content {
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = l10n('UI_PRoll_Snap'),
                        textAlignV = ui.ALIGNMENT.Center,
                    },
                },
                {
                    template = createPaddingTemplate(4),
                },
                uiTemplates.select(Editor.SNAP_LEVELS, Editor.snapLevel, 0, true, 32, function(newVal)
                    Editor.snapLevel = newVal
                    --pianoRollLastNoteSize = Editor.song.resolution * (4 / Editor.song.timeSig[2])
                    --updatePianoRollBarNumberLabels()
                    --updatePianoRoll()
                end),
                {
                    template = createPaddingTemplate(4),
                },
                uiTemplates.checkbox(Editor.snap, 'CheckboxOn', 'CheckboxOff', function(checked)
                    Editor.snap = checked
                end),
            }
        }
        table.insert(middleBox, snapSelect)

        table.insert(middleBox, createPaddingTemplate(8))
        table.insert(middleBox, {
            template = I.MWUI.templates.textHeader,
            props = {
                text = l10n('UI_PRoll_Parts'),
                textAlignH = ui.ALIGNMENT.Center,
                autoSize = false,
                relativeSize = util.vector2(1, 0),
                size = util.vector2(0, 32),
            },
        })
        local parts = {}
        for _, v in ipairs(Editor.song.parts) do
            table.insert(parts, v)
        end
        table.sort(parts, function(a, b)
            return a.instrument < b.instrument
        end)
        for _, part in ipairs(parts) do
            table.insert(middleBox, uiTemplates.partDisplay(part))
        end

        table.insert(middleBox, {
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
                                text = l10n('UI_PRoll_NewPart'),
                                anchor = util.vector2(0.5, 0.5),
                                relativePosition = util.vector2(0.5, 0.5),
                            },
                        },
                    },
                    events = {
                        mouseClick = async:callback(function()
                            Editor.activePart = Editor.song:createNewPart()
                            saveDraft()
                            Editor:destroyUI()
                            Editor:createUI()
                        end),
                    }
                },
            }
        })

        --[[table.insert(manager.content[2].content, {
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
        })]]

        table.insert(manager.content[2].content, {
            type = ui.TYPE.Flex,
            name = 'songActions',
            props = {
                autoSize = false,
                size = util.vector2(0, 64),
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
                                text = l10n('UI_PRoll_FinalizeDraft'),
                                anchor = util.vector2(0.5, 0.5),
                                relativePosition = util.vector2(0.5, 0.5),
                            },
                        },
                    },
                    events = {
                        mouseClick = async:callback(function()
                            createFinalizeDraftModal()
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
                                text = l10n('UI_PRoll_DeleteDraft'),
                                textColor = Editor.uiColors.RED_DESAT,
                                anchor = util.vector2(0.5, 0.5),
                                relativePosition = util.vector2(0.5, 0.5),
                            },
                        },
                    },
                    events = {
                        mouseClick = async:callback(function()
                            modalElement = ui.create(uiTemplates.confirmModal(function()
                                local songs = storage.playerSection('Bardcraft'):getCopy('songs/drafts') or {}
                                for i, song in ipairs(songs) do
                                    if song.id == Editor.song.id then
                                        table.remove(songs, i)
                                        break
                                    end
                                end
                                storage.playerSection('Bardcraft'):set('songs/drafts', songs)
                                -- setDraft(nil)
                                -- setMainContent(getSongTab())
                                Editor.song = nil
                                Editor:setState(Editor.STATE.SONG)
                            end))
                        end),
                    }
                },
            }
        })

        pianoRoll.editorWrapper = ui.create {
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
                        if pianoRoll.focused then
                            pianoRoll.scrollX = util.clamp(pianoRoll.scrollX + dx, -pianoRoll.scrollXMax, 0)
                            pianoRoll.scrollY = util.clamp(pianoRoll.scrollY + dy, -pianoRoll.scrollYMax, 0)
                            updatePianoRoll()
                            if math.abs(pianoRoll.scrollX - pianoRoll.scrollLastPopulateX) > pianoRoll.scrollPopulateWindowSize then
                                pianoRoll.scrollLastPopulateX = pianoRoll.scrollX
                                populateNotes()
                            end
                        end
                    end
                    if e.button == 1 and pianoRoll.dragStart then
                        local offset = editorOffsetToRealOffset(e.offset + util.vector2(pianoRoll.dragOffset and pianoRoll.dragOffset.x or 0, 0))
                        local note, tick = realOffsetToNote(offset)
                        local snap = calcSnapFactor()
                        tick = util.round(tick / snap) * snap + 1
                        
                        local noteData = Editor.noteMap[pianoRoll.activeNote]
                        if pianoRoll.dragType == DragType.MOVE then
                            noteData.time = util.clamp(tick, 1, math.huge)
                            if note ~= noteData.note then
                                playNoteSound(note)
                                playingNoteSound = note
                                if Song.getInstrumentProfile(Editor.activePart.instrument).sustain then
                                    stopNoteSound(noteData.note)
                                end
                            end
                            noteData.note = note
                        elseif pianoRoll.dragType == DragType.RESIZE_RIGHT then
                            noteData.duration = util.clamp(tick - noteData.time, snap, math.huge)
                        end
                        local layout = pianoRoll.editorWrapper.layout.content[1].content[3].content
                        local notePos
                        for i, note in ipairs(layout) do
                            if note.name == tostring(noteData.id) then
                                notePos = i
                                break
                            end
                        end
                        layout[notePos] = uiTemplates.pianoRollNote(noteData.id, noteData.note, noteData.time, noteData.duration)
                        pianoRoll.lastNoteSize = noteData.duration
                        pianoRoll.editorWrapper:update()
                    end
                end),
                mousePress = async:callback(function(e)
                    if textFocused then
                        Editor:destroyUI()
                        Editor:createUI()
                        textFocused = false
                    end
                    if e.button ~= 1 then return end
                    if e.offset.y < 24 then
                        -- Set playback pos and start playback
                        local offset = editorOffsetToRealOffset(e.offset)
                        stopAllSounds()
                        playback = true
                        Editor.song:resetPlayback()
                        Editor.song.playbackTickCurr = Editor.song:beatToTick(editorOffsetToRealOffset(e.offset).x / calcBeatWidth(Editor.song.timeSig[2]))
                        Editor.song.playbackTickPrev = Editor.song.playbackTickCurr
                        return
                    elseif Editor.activePart then
                        local note, tick = realOffsetToNote(editorOffsetToRealOffset(e.offset))
                        local snap = calcSnapFactor()
                        tick = math.floor(tick / snap) * snap + 1
                        playNoteSound(note)
                        playingNoteSound = note
                        pianoRoll.activeNote = addNote(note, tick, pianoRoll.lastNoteSize, true)
                        pianoRoll.dragStart = editorOffsetToRealOffset(e.offset)
                        pianoRoll.dragOffset = util.vector2(0, 0)
                        pianoRoll.dragType = DragType.MOVE
                    end
                end),
                mouseRelease = async:callback(function(e)
                    if e.button == 2 then
                        lastMouseDragPos = nil
                    end
                    if e.button == 1 and pianoRoll.activeNote then
                        pianoRoll.dragStart = nil
                        pianoRoll.dragType = DragType.NONE
                        pianoRoll.lastNoteSize = Editor.noteMap[pianoRoll.activeNote].duration
                        pianoRoll.activeNote = nil
                        pianoRoll.activeNoteElement = nil
                        if playingNoteSound and Song.getInstrumentProfile(Editor.activePart.instrument).sustain then
                            stopNoteSound(playingNoteSound)
                            playingNoteSound = nil
                        end
                        pianoRoll.editorWrapper:update()
                        saveNotes()
                    end
                end),
                focusLoss = async:callback(function()
                    lastMouseDragPos = nil
                end),
            }
        }

        initNotes()

        pianoRoll.keyboardWrapper = ui.create{
            type = ui.TYPE.Widget,
            props = {
                size = util.vector2(96, calcPianoRollEditorHeight()),
                position = util.vector2(0, 0)
            },
            content = ui.content {
                uiTemplates.pianoRollKeyboard(Editor.song.timeSig),
            },
        }

        pianoRoll.element = ui.create { 
            type = ui.TYPE.Widget,
            props = {
                size = calcPianoRollWrapperSize(),
            },
            content = ui.content { 
                pianoRoll.keyboardWrapper,
                pianoRoll.editorWrapper,
            } 
        }

        pianoRoll.wrapper = ui.create{
                type = ui.TYPE.Widget,
                name = 'pianoRoll',
                props = {
                    size = calcPianoRollWrapperSize(),
                },
                content = ui.content {
                    pianoRoll.element
                },
        }
        table.insert(manager.content[3].content, pianoRoll.wrapper)
        editorOverlay = pianoRoll.editorWrapper.layout.content[1].content.pianoRollOverlay
        editorMarkers = pianoRoll.editorMarkersWrapper.layout.content.pianoRollMarkers
        editorNotes = pianoRoll.editorWrapper.layout.content[1].content.pianoRollNotes
    end
    return manager
end

getPerformanceTab = function()
    local performance = auxUi.deepLayoutCopy(uiTemplates.baseTab)
    local flexContent = performance.content[1].content[1].content
    
    local doPerformers = Editor.troupeSize > 0
    
    Editor.songs = getSongs()
    local scrollableSongContent = ui.content{}
    local itemHeight = 40
    local scrollableHeight = 450 * screenSize.y / 1080
    local scrollableWidth = 320 * screenSize.x / 1920 -- TODO change to 300

    if not doPerformers then
        scrollableWidth = scrollableWidth * 1.5
    end

    if screenSize.y <= 720 then
        scrollableHeight = scrollableHeight / 2
        itemHeight = 40
    end

    local knownSongs = {}
    local player = nearby.players[1]
    if player then
        knownSongs = Editor.performersInfo[player.id] and Editor.performersInfo[player.id].knownSongs or {}
    end

    if not doPerformers then Editor.performanceSelectedPerformer = player end

    for i, song in ipairs(Editor.songs) do
        if knownSongs[song.id] then
            scrollableSongContent:add(uiTemplates.songDisplay(song, itemHeight, Editor.performanceSelectedSong and song.id == Editor.performanceSelectedSong.id, function()
                if Editor.performanceSelectedSong and Editor.performanceSelectedSong.id == song.id then
                    Editor.performanceSelectedSong = nil
                else
                    Editor.performanceSelectedSong = song
                end
                Editor.performanceSelectedPart = nil
                Editor.performancePartAssignments = {}
                setMainContent(getPerformanceTab())
            end))
        end
    end
    local scrollableSong = uiTemplates.scrollable(util.vector2(scrollableWidth, scrollableHeight), scrollableSongContent, util.vector2(0, itemHeight * #scrollableSongContent + 4))

    local scrollablePerformersContent = ui.content{}
    if doPerformers then
        for _, v in ipairs(nearby.actors) do
            if (v.type == types.NPC and Editor.troupeMembers[v.recordId]) or v.type == types.Player then
                scrollablePerformersContent:add(uiTemplates.performerDisplay(v, itemHeight, Editor.performanceSelectedPerformer and (v.id == Editor.performanceSelectedPerformer.id), function()
                    if Editor.performanceSelectedPerformer and Editor.performanceSelectedPerformer.id == v.id then
                        Editor.performanceSelectedPerformer = nil
                    else
                        Editor.performanceSelectedPerformer = v
                    end
                    setMainContent(getPerformanceTab())
                end))
            end
        end
    end
    local scrollablePerformers = uiTemplates.scrollable(util.vector2(scrollableWidth, scrollableHeight), scrollablePerformersContent, util.vector2(0, itemHeight * #scrollablePerformersContent + 4))

    local scrollablePartsContent = ui.content{}
    if Editor.performanceSelectedSong then
        local parts = {}
        for _, v in ipairs(Editor.performanceSelectedSong.parts) do
            table.insert(parts, v)
        end
        table.sort(parts, function(a, b)
            return a.instrument < b.instrument or (a.instrument == b.instrument and a.title < b.title)
        end)
        for _, part in ipairs(parts) do
            local selected = false
            local confidence = 0
            if Editor.performanceSelectedPerformer then
                selected = part.index == Editor.performancePartAssignments[Editor.performanceSelectedPerformer.id]
                if Editor.performersInfo[Editor.performanceSelectedPerformer.id] then
                    local knownSong = Editor.performersInfo[Editor.performanceSelectedPerformer.id].knownSongs[Editor.performanceSelectedSong.id]
                    if knownSong then
                        confidence = knownSong.partConfidences[part.index] or 0
                    end
                end
            end
            scrollablePartsContent:add(uiTemplates.partDisplaySmall(part, itemHeight, selected, confidence * 100, function()
                if not Editor.performanceSelectedPerformer then return end
                if Editor.performancePartAssignments[Editor.performanceSelectedPerformer.id] == part.index then
                    Editor.performancePartAssignments[Editor.performanceSelectedPerformer.id] = nil
                else
                    Editor.performancePartAssignments[Editor.performanceSelectedPerformer.id] = part.index
                end
                setMainContent(getPerformanceTab())
            end))
        end
    end
    local scrollableParts = uiTemplates.scrollable(util.vector2(scrollableWidth, scrollableHeight), scrollablePartsContent, util.vector2(0, itemHeight * #scrollablePartsContent + 4))

    local selectedSongInfoTitle, selectedSongInfoDescription, selectedSongPerformButtons = {}, {}, {}
    if Editor.performanceSelectedSong then
        selectedSongInfoTitle = {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
            },
            content = ui.content {
                {
                    template = I.MWUI.templates.textHeader,
                    props = {
                        text = l10n('UI_PRoll_SongTitle') .. ': ',
                    }
                },
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = Editor.performanceSelectedSong.title,
                    }
                },
            }
        }
        selectedSongInfoDescription = {
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
                    template = I.MWUI.templates.textHeader,
                    props = {
                        text = l10n('UI_PRoll_SongDescription') .. ': ',
                    }
                },
                {
                    template = I.MWUI.templates.textParagraph,
                    props = {
                        text = Editor.performanceSelectedSong.desc or 'No description',
                    },
                    external = {
                        grow = 1,
                        stretch = 1,
                    },
                },
            }
        }
        selectedSongPerformButtons = {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                autoSize = false,
                relativeSize = util.vector2(1, 0),
                size = util.vector2(0, 32),
                align = ui.ALIGNMENT.Center,
                relativePosition = util.vector2(0, 1),
                anchor = util.vector2(0, 1),
                position = util.vector2(0, -96),
            },
            content = ui.content {
                uiTemplates.button(l10n('UI_Button_Perform'), util.vector2(192, 32), function()
                    startPerformance(Song.PerformanceType.Perform)
                end),
                {
                    template = I.MWUI.templates.interval,
                },
                uiTemplates.button(l10n('UI_Button_Practice'), util.vector2(192, 32), function()
                    startPerformance(Song.PerformanceType.Practice)
                end),
                {
                    template = I.MWUI.templates.interval,
                },
                uiTemplates.button(l10n('UI_Button_PlayIdly'), util.vector2(192, 32), function()
                    startPerformance(Song.PerformanceType.Ambient)
                end),
            }
        }
    end

    table.insert(flexContent, {
        type = ui.TYPE.Flex,
        props = {
            autoSize = false,
            relativeSize = util.vector2(1, 1),
            align = ui.ALIGNMENT.Start,
            arrange = ui.ALIGNMENT.Center,
        },
        content = ui.content {
            createPaddingTemplate(16),
            {
                type = ui.TYPE.Flex,
                content = ui.content {
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            horizontal = true,
                        },
                        content = ui.content {
                            scrollableSong,
                            {
                                template = I.MWUI.templates.interval
                            },
                            doPerformers and scrollablePerformers or {},
                            doPerformers and {
                                template = I.MWUI.templates.interval
                            } or {},
                            scrollableParts
                        }
                    },
                    {
                        template = I.MWUI.templates.interval,
                    },
                    {
                        type = ui.TYPE.Flex,
                        external = {
                            stretch = 1,
                        },
                        content = ui.content {
                            selectedSongInfoTitle,
                            selectedSongInfoDescription,
                        }
                    },
                }
            },      
        }
    })
    table.insert(performance.content[1].content, selectedSongPerformButtons)
    return performance
end

getStatsTab = function()
    local playerInfo = Editor.performersInfo[nearby.players[1].id]
    if not playerInfo then return end

    local level = playerInfo.performanceSkill.level or 1
    local maxLevel = level >= 100
    local xp = playerInfo.performanceSkill.xp or 0
    local req = playerInfo.performanceSkill.req or 10
    local progress = maxLevel and 1 or (xp / req)
    local rank = l10n('UI_Lvl_Performance_' .. math.floor(level / 10))

    local stats = auxUi.deepLayoutCopy(uiTemplates.baseTab)
    local flexContent = stats.content[1].content[1].content
    table.insert(flexContent, {
        type = ui.TYPE.Flex,
        props = {
            autoSize = false,
            relativeSize = util.vector2(1, 1),
            arrange = ui.ALIGNMENT.Center,
        },
        content = ui.content {
            createPaddingTemplate(8),
            {
                type = ui.TYPE.Flex,
                props = {
                    autoSize = false,
                    relativeSize = util.vector2(1, 0),
                    size = util.vector2(0, 32),
                    horizontal = true,
                    arrange = ui.ALIGNMENT.Center,
                    align = ui.ALIGNMENT.Center,
                },
                content = ui.content {
                    {
                        template = I.MWUI.templates.textHeader,
                        props = {
                            text = l10n('UI_Lvl_Rank') .. ':',
                            textSize = 24,
                        }
                    },
                    createPaddingTemplate(4),
                    {
                        template = I.MWUI.templates.textNormal,
                        props = {
                            text = rank,
                            textSize = 24,
                        }
                    },
                }
            },
            createPaddingTemplate(8),
            {
                type = ui.TYPE.Flex,
                props = {
                    autoSize = false,
                    relativeSize = util.vector2(1, 0),
                    size = util.vector2(0, 128),
                    arrange = ui.ALIGNMENT.Center,
                },
                content = ui.content {
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            autoSize = false,
                            relativeSize = util.vector2(1, 0),
                            size = util.vector2(0, 32),
                            horizontal = true,
                            arrange = ui.ALIGNMENT.Center,
                            align = ui.ALIGNMENT.Center,
                        },
                        content = ui.content {
                            {
                                template = I.MWUI.templates.textNormal,
                                props = {
                                    text = tostring(level),
                                    textSize = 16,
                                    textColor = Editor.uiColors.DEFAULT,
                                }
                            },
                            createPaddingTemplate(8),
                            {
                                template = I.MWUI.templates.borders,
                                props = {
                                    autoSize = false,
                                    relativeSize = util.vector2(0.8, 0),
                                    size = util.vector2(0, 32),
                                },
                                content = ui.content {
                                    {
                                        type = ui.TYPE.Image,
                                        props = {
                                            resource = ui.texture {
                                                path = 'textures/Bardcraft/ui/xpbar.dds',
                                            },
                                            tileH = true,
                                            tileV = false,
                                            relativeSize = util.vector2(progress, 1),
                                        }
                                    },
                                    maxLevel and {
                                        template = I.MWUI.templates.textNormal,
                                        props = {
                                            text = 'Max Level!',
                                            textColor = Editor.uiColors.DEFAULT_LIGHT,
                                            anchor = util.vector2(0.5, 0.5),
                                            relativePosition = util.vector2(0.5, 0.5),
                                            relativeSize = util.vector2(0, 1),
                                            textAlignV = ui.ALIGNMENT.Center,
                                        }
                                    } or {},
                                }
                            },
                            createPaddingTemplate(8),
                            {
                                template = I.MWUI.templates.textNormal,
                                props = {
                                    text = maxLevel and '--' or (tostring(level + 1)),
                                    textColor = Editor.uiColors.DEFAULT,
                                }
                            },
                        }
                    },
                    createPaddingTemplate(4),
                    not maxLevel and {
                        template = I.MWUI.templates.textNormal,
                        props = {
                            text = (util.round(xp) .. '/' .. util.round(req) .. ' (' .. util.round(progress * 100) .. '%) to next level'),
                            textColor = Editor.uiColors.DEFAULT,
                        }
                    } or {},
                    createPaddingTemplate(4),
                }
            },
        }
    })
    return stats
end

local logShowing = false

function Editor:showPerformanceLog(log)
    screenSize = ui.screenSize()
    local sizeX = math.min(1600, screenSize.x * 5/6)
    local sizeY = sizeX * 9/16
    local scaleMod = sizeX / 1600
    
    self:destroyUI()
    I.UI.setMode(I.UI.MODE.Interface, {windows = {}})
    core.sendGlobalEvent('Pause', 'BO_Editor')
    logShowing = true

    local dateString = calendar.formatGameTime('%d %B, %Y', log.gameTime):match("0*(.+)")
    local baseTextSize = math.max(16 * scaleMod, 8)
    local headerSize = baseTextSize * 2
    local textSize = baseTextSize * 1.5

    local function textWithLabel(label, text, size, headerColor, textColor)
        headerColor = headerColor or Editor.uiColors.BOOK_HEADER
        textColor = textColor or Editor.uiColors.BOOK_TEXT
        size = size or textSize
        return {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
            },
            content = ui.content {
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = label .. ': ',
                        textSize = size,
                        textColor = headerColor,
                    },
                },
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = text,
                        textSize = size,
                        textColor = textColor,
                    },
                    external = {
                        grow = 1,
                        stretch = 1,
                    },
                },
            }
        }
    end
    local qualityString
    if log.quality == 100 then
        qualityString = 'Perfect'
    elseif log.quality >= 95 then
        qualityString = 'Excellent'
    elseif log.quality >= 85 then
        qualityString = 'Great'
    elseif log.quality >= 70 then
        qualityString = 'Good'
    elseif log.quality >= 40 then
        qualityString = 'Mediocre'
    elseif log.quality >= 15 then
        qualityString = 'Bad'
    else
        qualityString = 'Terrible'
    end
    
    local starsTexture = ui.texture {
        path = 'textures/Bardcraft/ui/stars-' .. qualityString .. '.dds',
        size = util.vector2(500, 96),
    }

    qualityString = l10n('UI_Quality_' .. qualityString)

    local tavernNotes = {}
    if log.type == Song.PerformanceType.Tavern then
        local patronComments = {}
        if log.patronComments and #log.patronComments > 0 then
            for _, comment in ipairs(log.patronComments) do
                table.insert(patronComments, {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = comment.name .. ':',
                        textSize = textSize,
                        textColor = Editor.uiColors.BOOK_TEXT,
                    }
                })
                table.insert(patronComments, {
                    template = I.MWUI.templates.textParagraph,
                    props = {
                        text = '"' .. l10n(comment.comment) .. '"',
                        textSize = textSize,
                        textColor = Editor.uiColors.BOOK_TEXT_LIGHT,
                        relativeSize = util.vector2(1, 0),
                        size = util.vector2(-32, 0),
                    },
                })
                table.insert(patronComments, createPaddingTemplate(4 * scaleMod))
            end
        end
        tavernNotes = {
            {
                template = createPaddingTemplate(4 * scaleMod),
            },
            {
                template = I.MWUI.templates.textNormal,
                props = {
                    text = 'Notes from the Evening',
                    textSize = headerSize,
                    textColor = Editor.uiColors.BOOK_HEADER
                },
            },
            {
                template = I.MWUI.templates.horizontalLine,
            },
            {
                template = createPaddingTemplate(8 * scaleMod),
            },
            textWithLabel('From the Publican', ''),
            {
                template = createPaddingTemplate(4 * scaleMod),
            },
            {
                template = I.MWUI.templates.textParagraph,
                props = {
                    text = log.publicanComment and ('"' .. l10n(log.publicanComment) .. '"') or 'No comment.',
                    textSize = textSize,
                    textColor = Editor.uiColors.BOOK_TEXT,
                    relativeSize = util.vector2(1, 0),
                    size = util.vector2(-32, 0),
                },
            },
            {
                template = createPaddingTemplate(8 * scaleMod),
            },
            textWithLabel('From the Patrons', ''),
            {
                template = createPaddingTemplate(4 * scaleMod),
            },
            table.unpack(patronComments),
        }
    end

    local notMaxLevel = log.level < 100
    local xpProg = notMaxLevel and (log.xpCurr / log.xpReq) or 1

    local cellBlurb = 'UI_Blurb_' .. log.cell
    local cellBlurbLoc = l10n(cellBlurb)
    if cellBlurb ~= cellBlurbLoc then
        log.cellBlurb = cellBlurb
    end

    if log.type == Song.PerformanceType.Street then
        log.cell = l10n('UI_PerfLog_StreetsOf'):gsub('%%{city}', log.cell)
    end

    wrapperElement = ui.create {
        layer = 'Windows',
        type = ui.TYPE.Widget,
        props = {
            size = util.vector2(sizeX, sizeY),
            anchor = util.vector2(0.5, 0.5),
            relativePosition = util.vector2(0.5, 0.5),
        },
        content = ui.content {
            {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture {
                        path = 'textures/Bardcraft/ui/tx_performancebook.dds',
                    },
                    relativeSize = util.vector2(1, 1),
                    anchor = util.vector2(0.5, 0.5),
                    relativePosition = util.vector2(0.5, 0.5),
                }
            },
            {
                type = ui.TYPE.Flex,
                props = {
                    autoSize = false,
                    relativeSize = util.vector2(0.7, 0.92),
                    anchor = util.vector2(0.5, 0.5),
                    relativePosition = util.vector2(0.5, 0.5),
                    horizontal = true,
                },
                content = ui.content {
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            autoSize = false,
                            relativeSize = util.vector2(0.475, 1), -- left page of the book
                        },
                        content = ui.content {
                            {
                                template = I.MWUI.templates.textNormal,
                                props = {
                                    text = 'Performance Log',
                                    textSize = headerSize,
                                    textColor = Editor.uiColors.BOOK_HEADER
                                },
                            },
                            {
                                template = I.MWUI.templates.horizontalLine,
                            },
                            {
                                template = I.MWUI.templates.textNormal,
                                props = {
                                    text = dateString,
                                    textSize = textSize,
                                    textColor = Editor.uiColors.BOOK_TEXT,
                                },
                            },
                            {
                                template = createPaddingTemplate(4 * scaleMod),
                            },
                            textWithLabel('Venue', log.cell),
                            {
                                template = createPaddingTemplate(4 * scaleMod),
                            },
                            log.cellBlurb and {
                                template = I.MWUI.templates.textParagraph,
                                props = {
                                    text = log.cellBlurb and l10n(log.cellBlurb) or '',
                                    textSize = textSize,
                                    textColor = Editor.uiColors.BOOK_TEXT_LIGHT,
                                    relativeSize = util.vector2(1, 0),
                                    size = util.vector2(-32, 0),
                                },
                            } or {},
                            log.cellBlurb and {
                                template = createPaddingTemplate(4 * scaleMod),
                            } or {},
                            textWithLabel('Song', log.songName),
                            {
                                template = createPaddingTemplate(4 * scaleMod),
                            },
                            textWithLabel('Performance Quality', qualityString),
                            {
                                type = ui.TYPE.Image,
                                props = {
                                    resource = starsTexture,
                                    size = util.vector2(500 / 2 * scaleMod, 96 / 2 * scaleMod),
                                }
                            },
                            table.unpack(tavernNotes),
                        }
                    },
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            autoSize = false,
                            relativeSize = util.vector2(0.05, 1), -- space between pages
                        }
                    },
                    {
                        type = ui.TYPE.Flex,
                        props = {
                            autoSize = false,
                            relativeSize = util.vector2(0.475, 1), -- right page of the book
                        },
                        content = ui.content {
                            {
                                template = I.MWUI.templates.textNormal,
                                props = {
                                    text = 'Rewards & Advancement',
                                    textSize = headerSize,
                                    textColor = Editor.uiColors.BOOK_HEADER
                                },
                            },
                            {
                                template = I.MWUI.templates.horizontalLine,
                            },
                            {
                                template = createPaddingTemplate(4 * scaleMod),
                            },
                            textWithLabel('Experience Gained', ''),
                            {
                                template = createPaddingTemplate(8 * scaleMod),
                            },
                            {
                                type = ui.TYPE.Flex,
                                props = {
                                    autoSize = false,
                                    relativeSize = util.vector2(1, 0),
                                    size = util.vector2(0, 96 * scaleMod),
                                    arrange = ui.ALIGNMENT.Center,
                                },
                                content = ui.content {
                                    {
                                        type = ui.TYPE.Flex,
                                        props = {
                                            autoSize = false,
                                            relativeSize = util.vector2(1, 0),
                                            size = util.vector2(0, 32 * scaleMod),
                                            horizontal = true,
                                            arrange = ui.ALIGNMENT.Center,
                                            align = ui.ALIGNMENT.Center,
                                        },
                                        content = ui.content {
                                            {
                                                template = I.MWUI.templates.textNormal,
                                                props = {
                                                    text = tostring(log.level),
                                                    textSize = textSize,
                                                    textColor = Editor.uiColors.BOOK_TEXT,
                                                }
                                            },
                                            createPaddingTemplate(8 * scaleMod),
                                            {
                                                template = I.MWUI.templates.borders,
                                                props = {
                                                    autoSize = false,
                                                    relativeSize = util.vector2(0.8, 0),
                                                    size = util.vector2(0, 32 * scaleMod),
                                                },
                                                content = ui.content {
                                                    {
                                                        type = ui.TYPE.Image,
                                                        props = {
                                                            resource = ui.texture {
                                                                path = 'textures/Bardcraft/ui/xpbar.dds',
                                                            },
                                                            tileH = true,
                                                            tileV = false,
                                                            relativeSize = util.vector2(xpProg, 1),
                                                        }
                                                    },
                                                    {
                                                        template = I.MWUI.templates.textNormal,
                                                        props = {
                                                            text = notMaxLevel and ('+' .. log.xpGain .. ' XP') or 'Max Level!',
                                                            textSize = textSize,
                                                            textColor = xpProg < 0.5 and Editor.uiColors.BOOK_TEXT or Editor.uiColors.DEFAULT_LIGHT,
                                                            anchor = util.vector2(xpProg < 0.5 and 0 or (notMaxLevel and 1 or 0.5), 0),
                                                            relativePosition = util.vector2(notMaxLevel and xpProg or 0.5, 0),
                                                            position = util.vector2(notMaxLevel and (xpProg < 0.5 and 4 or -4) or 0, 0),
                                                            relativeSize = util.vector2(0, 1),
                                                            textAlignV = ui.ALIGNMENT.Center,
                                                        }
                                                    }
                                                }
                                            },
                                            createPaddingTemplate(8 * scaleMod),
                                            {
                                                template = I.MWUI.templates.textNormal,
                                                props = {
                                                    text = notMaxLevel and (tostring(log.level + 1)) or '--',
                                                    textSize = textSize,
                                                    textColor = Editor.uiColors.BOOK_TEXT,
                                                }
                                            },
                                        }
                                    },
                                    createPaddingTemplate(4 * scaleMod),
                                    {
                                        template = I.MWUI.templates.textNormal,
                                        props = {
                                            text = log.levelGain > 0 and ('Leveled up! (x' .. log.levelGain .. ')') or '',
                                            textSize = textSize,
                                            textColor = Editor.uiColors.BOOK_HEADER,
                                        }
                                    },
                                    {
                                        template = I.MWUI.templates.textNormal,
                                        props = {
                                            text = notMaxLevel and (log.xpCurr .. '/' .. log.xpReq .. ' (' .. util.round(xpProg * 100) .. '%) to next level') or '',
                                            textSize = textSize,
                                            textColor = Editor.uiColors.BOOK_TEXT,
                                        }
                                    }
                                }
                            },
                            {
                                template = createPaddingTemplate(4 * scaleMod),
                            },
                            textWithLabel('Outcome', ''),
                            {
                                template = createPaddingTemplate(4 * scaleMod),
                            },
                            {
                                type = ui.TYPE.Widget,
                                props = {
                                    relativeSize = util.vector2(1, 0),
                                    size = util.vector2(0, 96 * scaleMod),
                                },
                                content = ui.content {
                                    {
                                        type = ui.TYPE.Image,
                                        props = {
                                            resource = ui.texture {
                                                path = 'textures/Bardcraft/ui/bookicon-gold.dds',
                                            },
                                            size = util.vector2(96 * scaleMod, 96 * scaleMod),
                                        }
                                    },
                                    {
                                        type = ui.TYPE.Flex,
                                        props = {
                                            autoSize = false,
                                            relativeSize = util.vector2(1, 1),
                                            size = util.vector2(-96 * scaleMod - 8, 0),
                                            anchor = util.vector2(1, 0),
                                            relativePosition = util.vector2(1, 0),
                                            align = ui.ALIGNMENT.Center,
                                        },
                                        content = ui.content {
                                            textWithLabel('Gold Gained', tostring((log.payment or 0) + (log.tips or 0))),
                                            log.payment and createPaddingTemplate(4 * scaleMod) or {},
                                            log.payment and textWithLabel('From publican', tostring(log.payment or 0), baseTextSize, Editor.uiColors.BOOK_TEXT_LIGHT, Editor.uiColors.BOOK_TEXT_LIGHT) or {},
                                            log.payment and textWithLabel('From tips', tostring(log.tips or 0), baseTextSize, Editor.uiColors.BOOK_TEXT_LIGHT, Editor.uiColors.BOOK_TEXT_LIGHT) or {},
                                        }
                                    }
                                }
                            },
                            {
                                type = ui.TYPE.Widget,
                                props = {
                                    relativeSize = util.vector2(1, 0),
                                    size = util.vector2(0, 96 * scaleMod),
                                },
                                content = ui.content {
                                    {
                                        type = ui.TYPE.Image,
                                        props = {
                                            resource = ui.texture {
                                                path = 'textures/Bardcraft/ui/bookicon-rep.dds',
                                            },
                                            size = util.vector2(96 * scaleMod, 96 * scaleMod),
                                        }
                                    },
                                    {
                                        type = ui.TYPE.Flex,
                                        props = {
                                            autoSize = false,
                                            relativeSize = util.vector2(1, 1),
                                            size = util.vector2(-96 * scaleMod - 8, 0),
                                            anchor = util.vector2(1, 0),
                                            relativePosition = util.vector2(1, 0),
                                            align = ui.ALIGNMENT.Center,
                                        },
                                        content = ui.content {
                                            textWithLabel('Reputation', ((log.rep and log.rep > 0) and '+' or '') .. tostring(log.rep or 0)),
                                            {
                                                template = createPaddingTemplate(4 * scaleMod),
                                            },
                                            textWithLabel('From', tostring(log.oldRep) .. ' -> ' .. tostring(log.newRep), baseTextSize, Editor.uiColors.BOOK_TEXT_LIGHT, Editor.uiColors.BOOK_TEXT_LIGHT),
                                        }
                                    }
                                }
                            },
                            {
                                type = ui.TYPE.Widget,
                                props = {
                                    relativeSize = util.vector2(1, 0),
                                    size = log.disp and util.vector2(0, 96 * scaleMod) or util.vector2(0, 0),
                                },
                                content = log.disp and ui.content {
                                    {
                                        type = ui.TYPE.Image,
                                        props = {
                                            resource = ui.texture {
                                                path = 'textures/Bardcraft/ui/bookicon-pub' .. (
                                                    ((log.kickedOut or log.disp < -10) and 'mad') or
                                                    ((log.disp < 10) and 'meh') or
                                                    ((log.disp < 20) and 'happy') or
                                                    'grin') .. '.dds',
                                            },
                                            size = util.vector2(96 * scaleMod, 96 * scaleMod),
                                        }
                                    },
                                    {
                                        type = ui.TYPE.Flex,
                                        props = {
                                            autoSize = false,
                                            relativeSize = util.vector2(1, 1),
                                            size = util.vector2(-96 * scaleMod - 8, 0),
                                            anchor = util.vector2(1, 0),
                                            relativePosition = util.vector2(1, 0),
                                            align = ui.ALIGNMENT.Center,
                                        },
                                        content = ui.content {
                                            textWithLabel('Publican Disposition', ((log.disp and log.disp > 0) and '+' or '') .. tostring(log.disp or 0)),
                                            {
                                                template = createPaddingTemplate(4 * scaleMod),
                                            },
                                            textWithLabel('From', tostring(log.oldDisp) .. ' -> ' .. tostring(log.newDisp), baseTextSize, Editor.uiColors.BOOK_TEXT_LIGHT, Editor.uiColors.BOOK_TEXT_LIGHT),
                                        }
                                    }
                                } or ui.content {}
                            },
                            createPaddingTemplate(16 * scaleMod),
                            {
                                template = I.MWUI.templates.textParagraph,
                                props = {
                                    text = log.kickedOut and l10n('UI_Msg_PerfTavern_KickedOut'):gsub('%%{date}', calendar.formatGameTime('%d %B', log.banEndTime)):match("0*(.+)") or '',
                                    textColor = Editor.uiColors.BOOK_HEADER,
                                    textSize = textSize,
                                    textAlignH = ui.ALIGNMENT.Center,
                                },
                                external = {
                                    grow = 1,
                                    stretch = 1,
                                },
                            }
                        }
                    }
                }
            },
            {
                type = ui.TYPE.Container,
                props = {
                    anchor = util.vector2(0.5, 1),
                    relativePosition = util.vector2(0.5, 1),
                },
                content = ui.content {
                    {
                        type = ui.TYPE.Image,
                        props = {
                            resource = ui.texture { path = 'white' },
                            color = Editor.uiColors.BLACK,
                            size = util.vector2(256, 32),
                        }
                    },
                    uiTemplates.button(l10n('UI_Button_Close'), util.vector2(256, 32), function()
                        self:destroyUI()
                        if self.active then
                            self:createUI()
                            I.UI.setMode(I.UI.MODE.Interface, {windows = {}})
                            core.sendGlobalEvent('Pause', 'BO_Editor')
                        else
                            I.UI.removeMode(I.UI.MODE.Interface)
                            core.sendGlobalEvent('Unpause', 'BO_Editor')
                        end
                        ambient.playSoundFile('sound\\Fx\\BOOKCLS2.wav', { volume = 0.5 })
                    end),
                }
            }
        },
    }
    wrapperElement:update()
    ambient.playSoundFile('sound\\Fx\\BOOKOPN1.wav', { volume = 0.5 })
end

local function updatePlaybackMarker()
    if pianoRoll.editorMarkersWrapper and pianoRoll.editorMarkersWrapper.layout.content.pianoRollMarkers.content[1] then
        local playbackMarker = pianoRoll.editorMarkersWrapper.layout.content.pianoRollMarkers.content[1]
        if playbackMarker then
            local playbackX = (Editor.song:tickToBeat(Editor.song.playbackTickCurr)) * calcBeatWidth(Editor.song.timeSig[2])
            playbackMarker.props.position = util.vector2(playbackX, 0)
            playbackMarker.props.alpha = playbackX > 0 and 0.8 or 0
            if playback and ((playbackX + pianoRoll.scrollX) > calcPianoRollEditorWrapperSize().x or (playbackX + pianoRoll.scrollX) < 0) then
                pianoRoll.scrollX = util.clamp(-playbackX, -pianoRoll.scrollXMax, 0)
                pianoRoll.scrollLastPopulateX = pianoRoll.scrollX
                updatePianoRoll()
                populateNotes()
            end
            pianoRoll.editorMarkersWrapper:update()
        end
    end
end

local function tickPlayback(dt)
    if not Editor.song then return end
    if playback then
        if not Editor.song:tickPlayback(dt, 
        function(filePath, velocity, instrument, note, part)
            local profile = Song.getInstrumentProfile(instrument)
            -- if not profile.polyphonic then
            --     stopSounds(instrument)
            -- end
            if velocity > 0 and Editor.partsPlaying[part] then
                ambient.playSoundFile(filePath, { volume = velocity / 127 * profile.volume })
            end
        end, 
        function(filePath, instrument)
            local profile = Song.getInstrumentProfile(instrument)
            if profile.sustain then
                ambient.stopSoundFile(filePath)
            end
        end) then
            playback = false
            Editor.song:resetPlayback()
            stopAllSounds()
        end
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
        setMainContent(getSongTab())
        updatePianoRoll()
    elseif self.state == self.STATE.PERFORMANCE then
        setMainContent(getPerformanceTab())
    elseif self.state == self.STATE.STATS then
        setMainContent(getStatsTab())
    end
end

function Editor:createUI()
    self:destroyUI()
    local wrapper = uiTemplates.wrapper()
    screenSize = ui.screenSize()
    self.windowXOff = self.state == self.STATE.SONG and 20 or (screenSize.x * 1 / 3)
    wrapper.content[1].props.size = util.vector2(screenSize.x-Editor.windowXOff, screenSize.y - Editor.windowYOff)
    wrapperElement = ui.create(wrapper)
    Editor:setContent()
end

function Editor:destroyUI()
    if wrapperElement then
        auxUi.deepDestroy(wrapperElement)
        wrapperElement = nil
    end
    if modalElement then
        auxUi.deepDestroy(modalElement)
        modalElement = nil
    end
    logShowing = false
end

function Editor:closeUI()
    I.UI.removeMode(I.UI.MODE.Interface)
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

function Editor:togglePlayback(fromStart)
    if playback then
        stopPlayback()
        updatePlaybackMarker()
    else
        startPlayback(fromStart)
    end
end

function Editor:onUINil()
    if self.active and self.state == self.STATE.SONG then
        --self:createUI()
        I.UI.setMode(I.UI.MODE.Interface, {windows = {}})
        core.sendGlobalEvent('Pause', 'BO_Editor')
    else
        self:destroyUI()
        self.active = false
        core.sendGlobalEvent('Unpause', 'BO_Editor')
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
    alreadyRedrewThisFrame = false
    if self.deletePartConfirmTimer > 0 then
        self.deletePartConfirmTimer = self.deletePartConfirmTimer - core.getRealFrameDuration()
    else
        self.deletePartClickCount = 0
        self.deletePartIndex = nil
    end
    if self.active and playback and self.state == self.STATE.SONG then
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

function Editor:onMouseWheel(vertical, horizontal)
    if scrollableFocused and scrollableFocused.layout then
        if not scrollableFocused.layout.props.canScroll then return end
        local pos = scrollableFocused.layout.content[1].props.position
        scrollableFocused.layout.content[1].props.position = util.vector2(pos.x, util.clamp(pos.y + vertical * 32, -scrollableFocused.layout.props.scrollLimit, 0))
        scrollableFocused:update()
    elseif pianoRoll.focused then
        if input.isCtrlPressed() then
            local currZoom = self.ZOOM_LEVELS[self.zoomLevel]
            self.zoomLevel = util.clamp(self.zoomLevel + vertical, 1, #self.ZOOM_LEVELS)
            local diff = self.ZOOM_LEVELS[self.zoomLevel] / currZoom
            initPianoRoll()
            pianoRoll.scrollX = util.clamp(pianoRoll.scrollX * diff, -pianoRoll.scrollXMax, 0)
            redrawPianoRollEditor()
            return
        end

        local changeAmtY = vertical * 48
        local changeAmtX = horizontal * 48
        if input.isShiftPressed() then
            local y = changeAmtY
            changeAmtY = changeAmtX
            changeAmtX = y
        end

        pianoRoll.scrollX = util.clamp(pianoRoll.scrollX + changeAmtX, -pianoRoll.scrollXMax, 0)
        if math.abs(pianoRoll.scrollX - pianoRoll.scrollLastPopulateX) > pianoRoll.scrollPopulateWindowSize then
            pianoRoll.scrollLastPopulateX = pianoRoll.scrollX
            populateNotes()
        end
        pianoRoll.scrollY = util.clamp(pianoRoll.scrollY + changeAmtY, -pianoRoll.scrollYMax, 0)
        updatePianoRoll()
    end
end

function Editor:init()
    --cacheCoroutine = coroutine.create(cacheAllSoundsCoroutine)
    self.state = self.STATE.PERFORMANCE
    self.song = nil
    self.noteMap = nil
end

function Editor:playerConfirmModal(player, onYes, onNo)
    self:destroyUI()
    core.sendGlobalEvent('Pause', 'BO_Editor')
    I.UI.setMode(I.UI.MODE.Interface, {windows = {}})
    modalElement = ui.create(uiTemplates.modal(
        {
            type = ui.TYPE.Flex,
            props = {
                autoSize = false,
                relativeSize = util.vector2(1, 1),
                arrange = ui.ALIGNMENT.Center,
            },
            content = ui.content {
                createPaddingTemplate(16),
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = "Stop performing?",
                        textAlignH = ui.ALIGNMENT.Center,
                    },
                },
                createPaddingTemplate(16),
                {
                    type = ui.TYPE.Flex,
                    props = {
                        horizontal = true,
                        autoSize = false,
                        relativeSize = util.vector2(1, 0),
                        size = util.vector2(0, 32),
                        align = ui.ALIGNMENT.Center,
                    },
                    content = ui.content {
                        uiTemplates.button("Yes", util.vector2(128, 32), function()
                            if onYes then onYes() end
                            self:closeUI()
                        end),
                        {
                            template = I.MWUI.templates.interval,
                        },
                        uiTemplates.button("No", util.vector2(128, 32), function()
                            if onNo then onNo() end
                            self:closeUI()
                        end),
                    },
                },
                createPaddingTemplate(16),
            },
        },
        util.vector2(300, 150),
        "Confirmation"
    ))
end

function Editor:playerChoiceModal(player, title, choices, text)
    self:destroyUI()
    core.sendGlobalEvent('Pause', 'BO_Editor')
    I.UI.setMode(I.UI.MODE.Interface, {windows = {}})
    modalElement = ui.create(uiTemplates.modal(
        {
            type = ui.TYPE.Flex,
            props = {
                autoSize = false,
                relativeSize = util.vector2(1, 1),
                arrange = ui.ALIGNMENT.Center,
            },
            content = ui.content {
                createPaddingTemplate(8),
                text and {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = text,
                        textAlignH = ui.ALIGNMENT.Center,
                    },
                } or {},
                text and createPaddingTemplate(8) or {},
                {
                    type = ui.TYPE.Flex,
                    props = {
                        horizontal = false,
                        autoSize = false,
                        arrange = ui.ALIGNMENT.Center,
                        align = ui.ALIGNMENT.Center,
                    },
                    external = {
                        grow = 1,
                        stretch = 1,
                    },
                    content = (function()
                        local buttons = {createPaddingTemplate(8)}
                        for _, choice in ipairs(choices) do
                            table.insert(buttons, uiTemplates.button(choice.text, util.vector2(200, 32), function()
                                if choice.callback then
                                    choice.callback()
                                end
                                self:closeUI()
                            end))
                            table.insert(buttons, createPaddingTemplate(8))
                        end
                        return ui.content(buttons)
                    end)(),
                },
                createPaddingTemplate(8),
            },
        },
        util.vector2(400, 180),
        title--"Choice"
    ))
end

return Editor