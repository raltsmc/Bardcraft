local util = require('openmw.util')

local INSTRUMENT_ITEMS = {
    Lute = {
        misc_de_lute_01 = true, -- Vanilla
        misc_de_lute_01_phat = true,
        t_imp_lute_01 = true, -- Tamriel Data
        t_com_lute_01 = true,
        t_de_uni_renaldlute = true,
        t_imp_uni_goldenlute = true,
        t_de_music_adun = true,
        t_de_music_shiratar = true,
        ab_mus_delutethin = true, -- OOAB Data
    },
    Drum = {
        misc_de_drum_01 = true, -- Vanilla
        misc_de_drum_02 = true,
        t_imp_drum_01 = true, -- Tamriel Data
        t_imp_drum_02 = true,
        t_imp_drum_03 = true,
        t_imp_drum_04 = true,
        t_nor_deerskin_drum_01 = true,
        t_orc_drum_01 = true,
        t_rga_drum_01 = true,
    },
    Ocarina = {
        _rlts_bc_ocarina = true, -- Bardcraft
    },
    BassFlute = {
        _rlts_bc_bassflute = true, -- Bardcraft
    },
    PanFlute = {
        t_de_music_panflute_01 = true,
        ab_misc_6thflute = true,
        ab_misc_ashlflute = true,
        ab_mus_6thflute = true,
        ab_mus_ashlflute = true,
    },
    Harp = {
        t_de_music_sudahk = true,
        ab_mus_deharp = true,
    },
    Lyre = {
        t_de_music_lyre_01 = true,
        t_de_music_takuratum = true,
        ab_mus_delyre = true,
        ab_mus_ashllyre = true,
    },
}

local SHEATHABLE_INSTRUMENTS = { -- Instruments that can be displayed on the back
    Lute = true,
    Drum = true
}

local PUBLICAN_CLASSES = {
    publican = true,
    t_sky_publican = true,
    t_cyr_publican = true,
    t_glb_publican = true,
}

local BARD_NPCS = {
    _rlts_bc_bard_oc1 = { -- Sees-Silent-Reeds
        home = {
            cell = "Seyda Neen, Arrille's Tradehouse",
            position = util.vector3(-586, -381, 385),
            rotation = util.transform.rotateZ(1.6),
        },
        startingLevel = 25,
    }
}

local QUEST_REWARDS = {
    B2_AhemmusaSafe = {
        stage = 50,
        msg = "UI_Msg_QuestReward_Ahemmusa",
        item = "_rlts_bc_songscroll_ahemmusa",
    },
    DA_Sheogorath = {
        stage = 70,
        msg = "UI_Msg_QuestReward_Sheogorath",
        item = "_rlts_bc_musbox_sheo_a",
    }
}

local SONG_IDS = {
    -- Starting:        0x00000 - 0x0FFFF
    [0x00000] = "scales.mid",
    [0x00001] = "start-altmer.mid",
    [0x00002] = "start-argonian.mid",
    [0x00003] = "start-bosmer.mid",
    [0x00004] = "start-breton.mid",
    [0x00005] = "start-dunmer.mid",
    [0x00006] = "start-imperial.mid",
    [0x00007] = "start-khajiit.mid",
    [0x00008] = "start-nord.mid",
    [0x00009] = "start-orc.mid",
    [0x0000A] = "start-redguard.mid",
    -- Beginner:        0x10000 - 0x1FFFF
    [0x10000] = "beg1.mid",
    [0x10001] = "beg2.mid",
    [0x10002] = "beg3.mid",
    [0x10100] = "bwv997.mid",
    -- Intermediate:    0x20000 - 0x2FFFF
    [0x20000] = "int1.mid",
    [0x20100] = "greensleeves.mid",
    [0x20101] = "imp1.mid",
    [0x20102] = "reddiamond.mid",
    -- Advanced:        0x30000 - 0x3FFFF
    [0x30000] = "adv1.mid",
    [0x30100] = "bwv997-adv.mid",
    -- Misc:            0xE0000 - 0xFFFFF
    [0xE0000] = "ahemmusa.mid",
    [0xE0001] = "molagberan.mid",
    [0xE0002] = "rollbretonnia.mid",
    [0xE0003] = "wondrouslove.mid",
    [0xE0004] = "redmountain.mid",
    [0xE0005] = "shrinktodust.mid",
    [0xE0006] = "brooding.mid",
    [0xE0007] = "lessrude.mid",
    [0xE0008] = "jornibret.mid",
    [0xE0009] = "moonsong.mid",
}

local SONG_POOLS = {
    beginner = {
        0x10000, -- beg1.mid
        0x10001, -- beg2.mid
        0x10002, -- beg3.mid
        0x10100, -- bwv997.mid
    },
    intermediate = {
        0x20000, -- int1.mid
        0x20100, -- greensleeves.mid
        0x20101, -- imp1.mid
        0x20102, -- reddiamond.mid
    },
    advanced = {
        0x30000, -- adv1.mid
        0x30100, -- bwv997-adv.mid
    },
}

local SONG_BOOKS = {
    _rlts_bc_songbook_gen_beg = {
        pools = {
            "beginner",
        },
    },
    _rlts_bc_songbook_gen_int = {
        pools = {
            "intermediate",
        },
    },
    _rlts_bc_songbook_gen_adv = {
        pools = {
            "advanced",
        },
    },
    _rlts_bc_songscroll_ahemmusa = {
        songs = {
            0xE0000, -- ahemmusa.mid
        }
    },
    bk_battle_molag_beran = { -- Entertainers plug-in book
        songs = {
            0xE0001, -- molagberan.mid
        }
    },
    bk_balladeers_fakebook = { -- Entertainers plug-in book
        songs = {
            0xE0002, -- rollbretonnia.mid
        }
    },
    bk_ashland_hymns = { -- Vanilla book
        songs = {
            0xE0003, -- wondrouslove.mid
        }
    },
    bk_five_far_stars = { -- Vanilla book
        songs = {
            0xE0004, -- redmountain.mid
        }
    },
    bk_words_of_the_wind = { -- Vanilla book
        songs = {
            0xE0005, -- shrinktodust.mid
        }
    },
    bk_cantatasofvivec = { -- Vanilla book
        songs = {
            0xE0006, -- brooding.mid
        }
    },
    bk_istunondescosmology = { -- Vanilla book
        songs = {
            0xE0007, -- lessrude.mid
        }
    },
    ["bookskill_light armor3"] = { -- Vanilla book
        songs = {
            0xE0008, -- jornibret.mid
        }
    }
}

local MUSIC_BOXES = {
    _rlts_bc_musbox_beg_a = {
        pools = {
            "beginner",
        },
        spawnChance = 0.5,
    },
    _rlts_bc_musbox_int_a = {
        pools = {
            "intermediate",
        },
        spawnChance = 0.3,
    },
    _rlts_bc_musbox_adv_a = {
        pools = {
            "advanced",
        },
        spawnChance = 0.7,
    },
    _rlts_bc_musbox_dwv_a = {
        songs = {},
        spawnChance = 0.5,
    },
    _rlts_bc_musbox_imp_a = {
        songs = {},
        spawnChance = 0.5,
    },
    _rlts_bc_musbox_sheo_a = { -- Sheogorath's Music Box; picks a random song from all music box pools
        pools = {
            "beginner",
            "intermediate",
            "advanced",
        },
        spawnChance = 0.5,
    }
}

local STARTING_SONGS = {
    ["scales.mid"] = "any",
    ["start-altmer.mid"] = "high elf",
    ["start-argonian.mid"] = "argonian",
    ["start-bosmer.mid"] = "wood elf",
    ["start-breton.mid"] = "breton",
    ["start-dunmer.mid"] = "dark elf",
    ["start-imperial.mid"] = "imperial",
    ["start-khajiit.mid"] = "khajiit",
    ["start-nord.mid"] = "nord",
    ["start-orc.mid"] = "orc",
    ["start-redguard.mid"] = "redguard",
}

return {
    InstrumentItems = INSTRUMENT_ITEMS,
    SheathableInstruments = SHEATHABLE_INSTRUMENTS,
    PublicanClasses = PUBLICAN_CLASSES,
    BardNpcs = BARD_NPCS,
    QuestRewards = QUEST_REWARDS,
    SongBooks = SONG_BOOKS,
    MusicBoxes = MUSIC_BOXES,
    SongIds = SONG_IDS,
    SongPools = SONG_POOLS,
    StartingSongs = STARTING_SONGS,
}