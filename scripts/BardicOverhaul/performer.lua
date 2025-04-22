local P = {}

local types = require("openmw.types")
local core = require("openmw.core")
local self = require("openmw.self")
local anim = require("openmw.animation")
local I = require("openmw.interfaces")
local nearby = require("openmw.nearby")

local configGlobal = require('scripts.BardicOverhaul.config.global')

P.bpm = 0
P.musicTime = -1
P.playing = false

P.wasMoving = false
P.idleTimer = nil
P.instrument = nil

P.instrumentData = {
    Lute = {
        path = "meshes/m/misc_de_lute_01.nif",
        anim = "BOLute",
        boneName = "Bip01 BOInstrument",
    },
    Drum = {
        path = "meshes/m/misc_de_drum_01.nif",
        anim = "BODrum",
        boneName = "Bip01 BOInstrument",
    },
    Ocarina = {
        path = "meshes/BardicOverhaul/ocarina.nif",
        anim = "BOOcarina",
        boneName = "Bip01 BOInstrumentHand",
    },
}

local function getBpmConstant()
    local animFps = 24
    local animFramesPerBeat = 20
    local animBpm = animFps * 60 / animFramesPerBeat
    print("constant: " .. (P.bpm / animBpm))
    return P.bpm / animBpm
end

local function getAnimStartPoint(timeOffset)
    if timeOffset == -1 then
        return 0
    end
    local songBeatLength = 1 / (P.bpm / 60)
    local songTime = timeOffset % (songBeatLength * 16) -- in seconds
    local animTime = songTime / (songBeatLength * 16) -- from 0 to 1
    return animTime
end

function P.startAnim(animKey)
    local priority = {
        [anim.BONE_GROUP.LeftArm] = anim.PRIORITY.Hit,
        [anim.BONE_GROUP.RightArm] = anim.PRIORITY.Hit,
        [anim.BONE_GROUP.Torso] = anim.PRIORITY.Hit,
        [anim.BONE_GROUP.LowerBody] = anim.PRIORITY.WeaponLowerBody
    }

    I.AnimationController.playBlendedAnimation(animKey, {
        loops = 100000000,
        priority = priority,
        startPoint = getAnimStartPoint(P.musicTime) % 1,
        speed = getBpmConstant(),
    })
end

function P.resyncAnim(animKey)
    if anim.isPlaying(self, animKey) then
        anim.cancel(self, animKey)
        P.startAnim(animKey)
    end
end

function P.handleMovement(dt, idleAnim)
    if not P.playing then return false end
    if idleAnim == nil then
        idleAnim = 'idle'
    end
    local lowerBodyAnim = anim.getActiveGroup(self, anim.BONE_GROUP.LowerBody)
    local isMoving = lowerBodyAnim and (lowerBodyAnim:find('walk') or lowerBodyAnim:find('run') or lowerBodyAnim:find('sneak'))
    if P.wasMoving and not isMoving then
        I.AnimationController.playBlendedAnimation(idleAnim, { 
            loops = 1000000000,
            priority = {
                [anim.BONE_GROUP.LeftArm] = 0,
                [anim.BONE_GROUP.RightArm] = 0,
                [anim.BONE_GROUP.Torso] = 0,
                [anim.BONE_GROUP.LowerBody] = anim.PRIORITY.Scripted
            },
            blendMask = anim.BLEND_MASK.LowerBody
        })
        P.idleTimer = 0.25
    elseif P.idleTimer and P.idleTimer > 0 then
        P.idleTimer = P.idleTimer - dt
        if P.idleTimer <= 0 then
            anim.cancel(self, idleAnim)
            P.idleTimer = nil
        end
    end

    P.wasMoving = isMoving
end

function P.resetVfx()
    if P.instrumentData[P.instrument] then
        anim.removeVfx(self, 'BO_Instrument')
        anim.addVfx(self, P.instrumentData[P.instrument].path, {
            boneName = P.instrumentData[P.instrument].boneName,
            vfxId = 'BO_Instrument',
            loop = true,
            useAmbientLight = false
        })
    end
end

function P.resetAnim()
    if P.instrumentData[P.instrument] then
        anim.cancel(self, P.instrumentData[P.instrument].anim)
        P.startAnim(P.instrumentData[P.instrument].anim)
    end
end

function P.handlePerformEvent(data)
    P.musicTime = data.time + (core.getRealTime() - data.realTime)
    P.bpm = data.bpm
    local instrumentData = P.instrumentData[data.instrument]
    if not instrumentData then return end
    if data.instrument ~= P.instrument then
        P.instrument = data.instrument
        P.resetVfx()
    end
    if P.playing ~= true then
        P.playing = true
        P.resetAnim()
    end
end

return P