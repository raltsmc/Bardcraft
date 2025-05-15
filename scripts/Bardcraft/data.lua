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

local QUEST_REWARDS = {
    B2_AhemmusaSafe = {
        stage = 50,
        msg = "UI_Msg_QuestReward_Ahemmusa",
        item = "_rlts_bc_songscroll_ahemmusa",
    }
}

local SONGBOOKS = {
    _rlts_bc_songbook_gen_beg = {
        "bwv997.mid",
    },
    _rlts_bc_songbook_gen_int = {
        "greensleeves.mid",
        "imp1.mid",
    },
    _rlts_bc_songbook_gen_adv = {
        "bwv997-adv.mid",
    },
    _rlts_bc_songscroll_ahemmusa = {
        "ahemmusa.mid",
    },
    bk_battle_molag_beran = { -- Entertainers plug-in book
        "molagberan.mid",
    },
    bk_balladeers_fakebook = { -- Entertainers plug-in book
        "rollbretonnia.mid",
    },
    bk_ashland_hymns = { -- Vanilla book
        "wondrouslove.mid"
    },
    bk_five_far_stars = { -- Vanilla book
        "redmountain.mid",
    },
    bk_words_of_the_wind = { -- Vanilla book
        "shrinktodust.mid",
    },
    bk_cantatasofvivec = { -- Vanilla book
        "brooding.mid",
    },
    bk_istunondescosmology = { -- Vanilla book
        "lessrude.mid",
    },
    ["bookskill_light armor3"] = { -- Vanilla book
        "jornibret.mid",
    }
}

local MUSICBOXES = {
    _rlts_bc_musbox_beg_a = {
        songs = {
            0x10000, -- bwv997.mid
        },
        spawnChance = 0.2,
    },
    _rlts_bc_musbox_int_a = {
        songs = {
            0x20000, -- greensleeves.mid
            0x20001, -- imp1.mid
            0x20002, -- reddiamond.mid
        },
        spawnChance = 0.2,
    },
    _rlts_bc_musbox_adv_a = {
        songs = {
            0x30000, -- bwv997-adv.mid
        },
        spawnChance = 0.4,
    },
    _rlts_bc_musbox_dwv_a = {
        songs = {},
        spawnChance = 0.5,
    },
    _rlts_bc_musbox_imp_a = {
        songs = {},
        spawnChance = 0.5,
    }
}

local SONG_IDS = {
    -- Beginner
    [0x10000] = "bwv997.mid",
    -- Intermediate
    [0x20000] = "greensleeves.mid",
    [0x20001] = "imp1.mid",
    [0x20002] = "reddiamond.mid",
    -- Advanced
    [0x30000] = "bwv997-adv.mid",
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
    QuestRewards = QUEST_REWARDS,
    SongBooks = SONGBOOKS,
    MusicBoxes = MUSICBOXES,
    SongIds = SONG_IDS,
    StartingSongs = STARTING_SONGS,
}