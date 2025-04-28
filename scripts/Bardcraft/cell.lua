local types = require('openmw.types')

local C = {}

function C.cellHasPublican(cell)
    if not cell then return false end
    if cell.isExterior then return false end
    local npcs = cell:getAll(types.NPC)
    for _, npc in ipairs(npcs) do
        if not types.Actor.isDead(npc) then
            local record = types.NPC.record(npc)
            if record and record.class == 'publican' then
                return true
            end
        end
    end
    return false
end

return C