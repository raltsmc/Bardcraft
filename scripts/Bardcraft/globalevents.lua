local world = require('openmw.world')
local types = require('openmw.types')

return {
    eventHandlers = {
        BC_ThrowItem = function(data)
            local item = world.createObject(data.item, data.count or 1)
            item:moveInto(types.Actor.inventory(data.actor))
        end
    }
}