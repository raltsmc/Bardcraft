local types = require('openmw.types')
local storage = require('openmw.storage')

local Song = require('scripts.Bardcraft.util.song').Song
local publicanClasses = require('scripts.Bardcraft.data').PublicanClasses

local C = {}

C.StreetType = {
    Town = 1,
    City = 2,
    Metropolis = 3,
}

function C.getPublican(cell)
    if not cell then return nil end
    if cell.isExterior then return nil end
    local npcs = cell:getAll(types.NPC)
    for _, npc in ipairs(npcs) do
        if not types.Actor.isDead(npc) then
            local record = types.NPC.record(npc)
            if record and publicanClasses[record.class] then
                return npc
            end
        end
    end
    return nil
end

function C.cellHasPublican(cell)
    return C.getPublican(cell) ~= nil
end

function C.canPerformHere(cell, type)
    local venues = storage.globalSection('Bardcraft'):getCopy('venues') or {}
    if type == Song.PerformanceType.Tavern then
        if C.cellHasPublican(cell) then
            return true
        end
        -- Search venues list for matching cell name
        for _, venue in ipairs(venues.taverns) do
            if string.find(cell.name, venue, 1, true) then
                return true
            end
        end
        return nil
    elseif type == Song.PerformanceType.Street then
        if not cell.isExterior then return nil end
        -- Check if the cell is in the list of street performance locations
        if not venues.street then return nil end
        local streetData = venues.street
        for _, venue in ipairs(streetData.metropolises) do
            if string.find(cell.name, venue, 1, true) then
                return true, venue, C.StreetType.Metropolis
            end
        end
        for _, venue in ipairs(streetData.cities) do
            if string.find(cell.name, venue, 1, true) then
                return true, venue, C.StreetType.City
            end
        end
        for _, venue in ipairs(streetData.towns) do
            if string.find(cell.name, venue, 1, true) then
                return true, venue, C.StreetType.Town
            end
        end
        return nil
    elseif type == Song.PerformanceType.Practice then
        if not C.canPerformHere(cell, Song.PerformanceType.Tavern) then
            return Song.PerformanceType.Practice
        else
            return nil
        end
    elseif type == Song.PerformanceType.Perform then
        if C.canPerformHere(cell, Song.PerformanceType.Tavern) then
            return Song.PerformanceType.Tavern
        end
        local streetResult, streetName, streetType = C.canPerformHere(cell, Song.PerformanceType.Street)
        if streetResult then
            return Song.PerformanceType.Street, streetName, streetType
        end
        return nil
    end
end

return C