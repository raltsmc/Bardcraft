local anim = require('openmw.animation')
local self = require('openmw.self')
local I = require('openmw.interfaces')

local templates = {
    LeftArm = {
        mask = anim.BLEND_MASK.LeftArm,
        priority = {
            [anim.BONE_GROUP.LeftArm] = anim.PRIORITY.Weapon,
            [anim.BONE_GROUP.RightArm] = 0,
            [anim.BONE_GROUP.Torso] = 0,
            [anim.BONE_GROUP.LowerBody] = 0
        }
    },
    RightArm = {
        mask = anim.BLEND_MASK.RightArm,
        priority = {
            [anim.BONE_GROUP.LeftArm] = 0,
            [anim.BONE_GROUP.RightArm] = anim.PRIORITY.Weapon,
            [anim.BONE_GROUP.Torso] = 0,
            [anim.BONE_GROUP.LowerBody] = 0
        }
    },
    BothArms = {
        mask = anim.BLEND_MASK.LeftArm + anim.BLEND_MASK.RightArm,
        priority = {
            [anim.BONE_GROUP.LeftArm] = anim.PRIORITY.Weapon,
            [anim.BONE_GROUP.RightArm] = anim.PRIORITY.Weapon,
            [anim.BONE_GROUP.Torso] = 0,
            [anim.BONE_GROUP.LowerBody] = 0
        }
    },
    LeftArmLooping = {
        mask = anim.BLEND_MASK.LeftArm,
        priority = {
            [anim.BONE_GROUP.LeftArm] = anim.PRIORITY.Weapon,
            [anim.BONE_GROUP.RightArm] = 0,
            [anim.BONE_GROUP.Torso] = 0,
            [anim.BONE_GROUP.LowerBody] = 0
        },
        loops = 1000000,
        forceLoop = true,
        autoDisable = false
    },
    BothArmsLooping = {
        mask = anim.BLEND_MASK.LeftArm + anim.BLEND_MASK.RightArm,
        priority = {
            [anim.BONE_GROUP.LeftArm] = anim.PRIORITY.Weapon,
            [anim.BONE_GROUP.RightArm] = anim.PRIORITY.Weapon,
            [anim.BONE_GROUP.Torso] = 0,
            [anim.BONE_GROUP.LowerBody] = 0
        },
        loops = 1000000,
        forceLoop = true,
        autoDisable = false
    }
}

local animData = {
    Lute = {
        bolute_strum = templates.RightArm,
        bolute_strumalt = templates.RightArm,
        bolute_fret1 = templates.LeftArmLooping,
        bolute_fret2 = templates.LeftArmLooping,
        bolute_fret3 = templates.LeftArmLooping,
        bolute_fret4 = templates.LeftArmLooping,
    },
    Drum = {
        bodrum_hitl = templates.LeftArm,
        bodrum_hitr = templates.RightArm,
        bodrum_roll = templates.BothArms,
    },
    Ocarina = {
        boocarina_note1 = templates.BothArmsLooping,
        boocarina_note2 = templates.BothArmsLooping,
        boocarina_note3 = templates.BothArmsLooping,
        boocarina_note4 = templates.BothArmsLooping,
        boocarina_note5 = templates.BothArmsLooping,
    },
    BassFlute = {
        boflute_note1 = templates.BothArmsLooping,
        boflute_note2 = templates.BothArmsLooping,
        boflute_note3 = templates.BothArmsLooping,
        boflute_note4 = templates.BothArmsLooping,
        boflute_note5 = templates.BothArmsLooping,
    }
}

local animOverrideAll = {
    Drum = {
        bodrum_roll = true,
    },
    Ocarina = {}
}

local animMappings = {
    Drum = {
        [46] = "bodrum_hitl",
        [47] = "bodrum_hitr",
        [48] = "bodrum_hitl",
        [49] = "bodrum_hitr",
        [50] = "bodrum_roll",
        [51] = "bodrum_hitl",
    }
}

local lastPlayed = nil
local lastTime = nil
local lastNote = nil
local playedThisBar = false

local Instruments = {
    Lute = {
        path = "meshes/m/misc_de_lute_01.nif",
        anim = "bolute",
        boneName = "Bip01 BOInstrument",
        eventHandler = function(data)
            if data.type == 'NoteEvent' then
                local animName = "bolute_strum"
                local doubleStrum = lastTime and data.time - lastTime < 0.1
                if doubleStrum then return end
                if anim.isPlaying(self, "bolute_strumalt") then
                    animName = "bolute_strum"
                    anim.cancel(self, "bolute_strumalt")
                end
                if anim.isPlaying(self, "bolute_strum") then
                    animName = "bolute_strumalt"
                    anim.cancel(self, "bolute_strum")
                end
                if doubleStrum then animName = lastPlayed end
                lastPlayed = animName
                lastTime = data.time
                local aData = animData.Lute[animName]
                if aData then
                    I.AnimationController.playBlendedAnimation(animName, aData)
                end
                playedThisBar = true
            elseif data.type == 'NewBar' and playedThisBar then
                playedThisBar = false
                local curr
                for i = 1, 4 do
                    local animName = "bolute_fret" .. i
                    if anim.isPlaying(self, animName) then
                        curr = i
                        anim.cancel(self, animName)
                    end
                end
                local num = data.bar % 4 + 1
                if curr and curr == num then
                    num = (num + 1) % 4
                end
                local animName = "bolute_fret" .. num
                local aData = animData.Lute[animName]
                if aData then
                    I.AnimationController.playBlendedAnimation(animName, aData)
                end
            end
        end,
    },
    Drum = {
        path = "meshes/m/misc_de_drum_01.nif",
        anim = "bodrum",
        boneName = "Bip01 BOInstrument",
        eventHandler = function(data)
            if data.type ~= 'NoteEvent' then return end
            local animName = animMappings.Drum[data.note]
            local aData = animData.Drum[animName]
            if aData then
                if animOverrideAll.Drum[animName] then
                    for animName, _ in pairs(animData.Drum) do
                        if anim.isPlaying(self, animName) then
                            anim.cancel(self, animName)
                        end
                    end
                else
                    if anim.isPlaying(self, animName) then
                        anim.cancel(self, animName)
                    end
                end
                I.AnimationController.playBlendedAnimation(animName, aData)
            end
        end,
    },
    Ocarina = {
        path = "meshes/Bardcraft/ocarina.nif",
        anim = "boocarina",
        boneName = "Bip01 BOInstrumentHand",
        eventHandler = function(data)
            if data.type ~= 'NoteEvent' then return end
            if data.note == lastNote then return end -- Only change fingering if the note changes
            local dt = lastTime and data.time - lastTime or 0
            lastTime = data.time
            if dt < 0.025 then return end
            lastNote = data.note
            for note, _ in pairs(animData.Ocarina) do
                if anim.isPlaying(self, note) then
                    anim.cancel(self, note)
                end
            end

            local animIndex = 0
            if lastNote and math.abs(data.note - lastNote) % 5 == 0 then
                if data.note > lastNote then animIndex = animIndex + 1
                elseif data.note < lastNote then animIndex = animIndex - 1 end
            end
            animIndex = (animIndex + data.note) % 5 + 1
            local animName = "boocarina_note" .. animIndex
            local aData = animData.Ocarina[animName]
            I.AnimationController.playBlendedAnimation(animName, aData)
        end,
    },
    BassFlute = {
        path = "meshes/Bardcraft/flute.nif",
        anim = "boflute",
        boneName = "Bip01 BOInstrumentHand",
        eventHandler = function(data)
            if data.type ~= 'NoteEvent' then return end
            if data.note == lastNote then return end -- Only change fingering if the note changes
            local dt = lastTime and data.time - lastTime or 0
            lastTime = data.time
            if dt < 0.025 then return end
            lastNote = data.note
            for note, _ in pairs(animData.BassFlute) do
                if anim.isPlaying(self, note) then
                    anim.cancel(self, note)
                end
            end

            local animIndex = 0
            if lastNote and math.abs(data.note - lastNote) % 5 == 0 then
                if data.note > lastNote then animIndex = animIndex + 1
                elseif data.note < lastNote then animIndex = animIndex - 1 end
            end
            animIndex = (animIndex + data.note) % 5 + 1
            local animName = "boflute_note" .. animIndex
            local aData = animData.BassFlute[animName]
            I.AnimationController.playBlendedAnimation(animName, aData)
        end,
    }
}

return {
    Instruments = Instruments,
    AnimData = animData,
}