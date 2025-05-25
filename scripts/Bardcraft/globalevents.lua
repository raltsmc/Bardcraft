local core = require('openmw.core')
local world = require('openmw.world')
local types = require('openmw.types')
local storage = require('openmw.storage')
local vfs = require('openmw.vfs')
local markup = require('openmw.markup')
local I = require('openmw.interfaces')
local async = require('openmw.async')

local MIDI = require('scripts.Bardcraft.util.midi')
local Song = require('scripts.Bardcraft.util.song').Song
local Data = require('scripts.Bardcraft.data')
local random = require('scripts.Bardcraft.util.random')

local function parseAllPreset()
    local metadataPath = 'midi/preset/metadata.yaml'
    local exists = vfs.fileExists(metadataPath)
    local metadata = exists and markup.loadYaml(metadataPath) or {
        midiData = {}
    }
    if not exists then
        print("WARNING: metadata.yaml missing")
    end

    local bardData = storage.globalSection('Bardcraft')
    bardData:set('songs/preset', nil) -- Clear the old data TODO remove
    local storedSongs = bardData:getCopy('songs/preset') or {}

    local midiSongs = {}
    for filePath in vfs.pathsWithPrefix(MIDI.MidiParser.presetFolder) do
        if filePath:sub(-4) == ".mid" then
            local fileName = string.match(filePath, "([^/]+)$")

            local alreadyParsed = false
            for _, song in pairs(storedSongs) do
                if song.sourceFile == fileName then
                    alreadyParsed = true
                    break
                end
            end

            if not alreadyParsed then
                local parser = MIDI.parseMidiFile(filePath)
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

    local feedbackPath = 'scripts/Bardcraft/feedback.yaml'
    exists = vfs.fileExists(feedbackPath)
    local feedback = exists and markup.loadYaml(feedbackPath) or {}
    if not exists then
        print("WARNING: feedback.yaml missing")
    elseif feedback then
        bardData:set('feedback', feedback)
    end
end

local mwscriptQueue = {}

I.ItemUsage.addHandlerForType(types.Miscellaneous, function(item, actor)
    if actor.type ~= types.Player then return true end
    local record = item.type.record(item)
    for instr, _ in pairs(Data.SheathableInstruments) do
        for recordId, _ in pairs(Data.InstrumentItems[instr]) do
            if record.id == recordId then
                actor:sendEvent('BC_SheatheInstrument', { record = {
                    id = record.id,
                    model = record.model,
                } })
                return true
            end
        end
    end
    return true
end)

return {
    engineHandlers = {
        --onInit = parseAll,
        onUpdate = function()
            if #mwscriptQueue > 0 then
                for _, data in ipairs(mwscriptQueue) do
                    local item = data.object
                    local mwscript = world.mwscript.getLocalScript(item)
                    if mwscript then
                        mwscript.variables.hasbeenplayed = data.hasBeenPlayed or 0
                        mwscript.variables.songid = data.songId or 0
                    end
                end
                mwscriptQueue = {}
            end
        end
    },
    eventHandlers = {
        BC_RecheckTroupe = function(data)
            local player = data and data.player or world.players[1]
            if not player then return end

            local troupeMembers = {}
            for _, actor in ipairs(world.activeActors) do
                local mwscript = world.mwscript.getLocalScript(actor)
                if mwscript and mwscript.recordId == "_bchireablebard" then
                    if mwscript.variables.followplayer == 1 then
                        table.insert(troupeMembers, actor)
                    end
                    if mwscript.variables.tphome == 1 then
                        local bardInfo = Data.BardNpcs[actor.recordId]
                        local home = bardInfo and bardInfo.home
                        if home then
                            mwscript.variables.tphome = 0
                            actor:teleport(home.cell, home.position, home.rotation)
                            player:sendEvent('BC_TPFadeIn')
                            player:sendEvent('AttendMeFollowerStatus', { -- Attend Me compatibility
                                actor = actor,
                                status = false,
                            }) 
                        end
                    end
                end
            end

            player:sendEvent("BC_TroupeStatus", { members = troupeMembers })
        end,
        BC_GiveItem = function(data)
            if not data then return end
            local item = world.createObject(data.item, data.count or 1)
            item:moveInto(types.Actor.inventory(data.actor))
        end,
        BC_ConsumeItem = function(data)
            if not data then return end
            data.item:remove(data.count)
        end,
        BC_ParseMidis = function()
            parseAllPreset()
        end,
        BC_Trespass = function(data)
            if not data then return end
            I.Crimes.commitCrime(data.player, {
                type = types.Player.OFFENSE_TYPE.Trespassing,
            })
        end,
        BC_BookRead = function(data)
            if not data then return end
            local book = data.book
            if not book then return end

            local mwscript = world.mwscript.getLocalScript(book)
            if not mwscript or mwscript.recordId ~= '_bcsheetmusic' then 
                data.player:sendEvent('BC_BookReadResult', { id = book.recordId, success = true })
                return 
            end
            if not mwscript.variables.hasbeenread or mwscript.variables.hasbeenread == 0 then
                mwscript.variables.hasbeenread = 1
                data.player:sendEvent('BC_BookReadResult', { id = book.recordId, success = true })
            else
                data.player:sendEvent('BC_BookReadResult', { success = false })
            end
        end,
        BC_ReplaceMusicBox = function(data)
            if not data then return end
            local object = data.object
            if not object or data.object.type ~= types.Miscellaneous then return end
            if data.object.count < 1 then return end
            if not object.cell then return end

            local mwscript = world.mwscript.getLocalScript(object)
            local hasBeenPlayed = mwscript.variables.hasbeenplayed or 0
            local songId = mwscript.variables.songid or 0

            local activatorId = object.recordId .. '_a'
            local activator = world.createObject(activatorId, 1)
            activator:teleport(object.cell, object.position, object.rotation)
            activator:sendEvent('BC_MusicBoxInit', { hasBeenPlayed = hasBeenPlayed, songId = songId, playerPlaced = true })
            object:remove()
        end,
        BC_PruneMusicBox = function(data)
            if not data then return end
            local object = data.object
            if not object or object.type ~= types.Activator then return end

            local globalVars = world.mwscript.getGlobalVariables()
            if not globalVars.bcInitTime or globalVars.bcInitTime == 0 then
                globalVars.bcInitTime = math.floor(core.getRealTime() * 1000)
                print("Bardcraft global seed set to: " .. globalVars.bcInitTime)
            end

            local cellName = object.cell and object.cell.name or "UnknownCell"
            local position = object.position
            local hashInput = string.format("%s_%.0f_%.0f_%.0f", cellName, position.x, position.y, position.z)
            local randomValue = random.hashStringToUnitFloat(globalVars.bcInitTime, hashInput)
            local record = Data.MusicBoxes[object.recordId]
            local spawnChance = record and record.spawnChance or 0.5

            -- print("Hash input: " .. hashInput)
            -- print("Random value: " .. randomValue)
            -- print("Spawn chance: " .. spawnChance)

            if randomValue > spawnChance then
                object:remove()
            end
        end,
        BC_MusicBoxPickup = function(data)
            local object = data.object
            if object.type ~= types.Activator then return end

            local itemId = object.recordId:sub(1, -3)
            local item = world.createObject(itemId, 1)
            local value = item.type.record(item).value
            local owner = object.owner
            if owner.factionId or owner.recordId then
                I.Crimes.commitCrime(data.actor, {
                    arg = value,
                    type = types.Player.OFFENSE_TYPE.Theft,
                    faction = owner.factionId,
                })
            end
            item.owner.factionId = object.owner.factionId
            item.owner.factionRank = object.owner.factionRank
            item.owner.recordId = object.owner.recordId

            table.insert(mwscriptQueue, {
                object = item,
                hasBeenPlayed = data.hasBeenPlayed or 0,
                songId = data.songId or 0,
            })

            item:moveInto(types.Actor.inventory(data.actor))
            object:remove()
        end,
        BC_SetCreationTime = function()
            local globalVars = world.mwscript.getGlobalVariables()
            if not globalVars.bcInitTime or globalVars.bcInitTime == 0 then
                globalVars.bcInitTime = math.floor(core.getRealTime() * 1000)
                print("Bardcraft global seed set to: " .. globalVars.bcInitTime)
            end
        end,
    }
}