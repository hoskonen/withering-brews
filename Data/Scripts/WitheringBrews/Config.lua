WitheringBrews            = WitheringBrews or {}
WitheringBrews.Config     = WitheringBrews.Config or {}

local C                   = WitheringBrews.Config
C.Name                    = C.Name or "WitheringBrews"
C.Version                 = C.Version or "0.0.1-dev"

-- flags
C.DryRun                  = (C.DryRun ~= false) -- default true

C.TrackMode               = "whitelist"         -- families or whitelist

-- bootstrap
C.Bootstrap               = C.Bootstrap or {}
C.Bootstrap.enable        = (C.Bootstrap.enable ~= false)
C.Bootstrap.db_flag       = C.Bootstrap.db_flag or "WB_Config:migrated_v1"
C.Bootstrap.affect        = C.Bootstrap.affect or { player = true, stash = false, saddle = false }
C.Bootstrap.seed_age_days = C.Bootstrap.seed_age_days or {
    water  = { iv = { 0, 2 }, iii = { 2, 6 }, ii = { 6, 10 }, i = { 10, 14 } },
    wine   = { iv = { 0, 4 }, iii = { 4, 10 }, ii = { 10, 18 }, i = { 18, 28 } },
    oil    = { iv = { 0, 60 }, iii = { 0, 90 }, ii = { 0, 120 }, i = { 0, 180 } },
    spirit = { iv = { 0, 120 }, iii = { 0, 160 }, ii = { 0, 200 }, i = { 0, 240 } },
}

-- replacers (keep your values)
C.PotionReplacers         = C.PotionReplacers or {
    empty  = "d7bb6617-9b14-41d2-8e59-93b7aaa08fd7",
    empty2 = "14989547-a6e3-4b9a-a2ba-923aaefa14fb",
}

-- Optional strict inclusion (whitelist only these classIds)
C.PotionWhitelist         = C.PotionWhitelist or {
    -- aquavitalis
    ["850d28d9-9d0a-4b2e-9feb-e6c48c5f1aad"] = true,
    ["ade54ad7-c400-4b19-a3fe-d34bd1fc3b30"] = true,
    ["0da553ab-9df7-4ed4-92b8-a9c9e42566a5"] = true,
    ["dec304dc-47f4-4bb2-8e4c-1c0a30203b6e"] = true,

    -- artemisia
    ["07016792-531f-4ef2-8c3c-ea7566326c04"] = true,
    ["2a17517c-e5f3-4c9e-ad45-b9e4b171b452"] = true,
    ["301cc8ff-f3f5-4c39-b27b-129bb58792d0"] = true,
    ["68853c50-8e91-4644-b914-3035715896cd"] = true,

    -- bowman_brew
    ["3157d51d-7461-4fdc-9601-93bd5ed42156"] = true,
    ["980ce52a-866c-4212-a80a-dfc6b53f5c40"] = true,
    ["e843c734-f28f-4263-9033-f6f40fe65a85"] = true,
    ["f613838b-0a41-4dee-a1cf-41cb753b5eb6"] = true,

    -- bucks_blood
    ["92c829ca-41f6-40a7-b8d9-aac5159c7a89"] = true,
    ["be58eb36-bd45-45d9-8a38-5bd07ceb4258"] = true,
    ["c016f34b-be76-47c7-9f96-caec61afa238"] = true,
    ["9ca97b1a-579b-44f2-8624-46d081b9001a"] = true,

    -- chamomile_decoction
    ["5060809f-feec-4c39-b7f4-1cea5e55ab70"] = true,
    ["ca4bb7aa-12a9-45d5-a589-de2a2458fc4d"] = true,
    ["12c30ac1-f9fc-4b61-a337-b3eb98779ca6"] = true,
    ["12174dd5-16bb-4e3c-9a3e-f66d851994e9"] = true,

    -- cockerel
    ["c40dc516-9886-4245-8a8b-2cbb16da918d"] = true,
    ["d4d378ef-0fb1-4030-880e-6b2fea8a394c"] = true,
    ["16aad4a8-c992-4230-8175-f3ec4ef4d4f8"] = true,
    ["6a3efa9e-700a-412a-88ee-721d34da98a8"] = true,

    -- digestive
    ["8b713d0c-9a04-4354-a53f-ffd384057fa6"] = true,
    ["2f566495-fbee-4b58-9abb-6a5287b2e681"] = true,
    ["5dd0afa5-3c76-475c-9775-6ed5c69132fd"] = true,
    ["e3023c6f-1293-49f1-8cd4-21cac3e3f604"] = true,

    -- fox
    ["34d9f446-e5a7-4af4-858a-e96473de814f"] = true,
    ["4f60ae85-28a3-45c1-9040-e11ed56edc87"] = true,
    ["2907cc32-ff8e-4a3c-b357-8fe434341874"] = true,
    ["ecd5ec75-6483-4376-a7ff-83be58847f11"] = true,

    -- lethean_water
    ["601f9ff2-0413-40c9-b443-9695aafa71a5"] = true,

    -- marigold
    ["b38c34b7-6016-4f64-9ba2-65e1ce31d4a1"] = true,
    ["761f9e84-e07b-4b4b-9425-7681898abccd"] = true,
    ["b4e0af8c-3ed7-40ed-8537-7772489832c8"] = true,
    ["c7022225-70b4-4bde-afe0-1d42763a2ecd"] = true,

    -- nighthawk
    ["6b955a9b-d8de-492c-a53e-a052fab4ff0a"] = true,
    ["122b7fbe-3ce3-4c4a-b692-cedfa355e7b6"] = true,
    ["555739da-ec53-49a0-a465-651e56ff1e96"] = true,
    ["0422b7ef-1554-4c9b-b7a0-037be091094f"] = true,

    -- painkiller
    ["09834ed5-010e-438b-8ac0-cf60529ff383"] = true,
    ["b53dc1c8-29c9-4002-878d-6b75fc10f217"] = true,
    ["10134a72-9c08-4bee-8352-208cdba64534"] = true,
    ["b6456b1c-ba84-4b3a-ba5b-47c388d3befb"] = true,

    -- saviour_schnapps
    ["928463d9-e21a-4f7c-b5d3-8378ed375cd1"] = true,
    ["d273bcad-6b58-4eae-9d2a-800c40176cfd"] = true,
    ["3d4a8904-98f1-464a-9b3e-d3926b835804"] = true,
    ["b7e25984-1dce-4129-b857-dd61821503c1"] = true,

    -- padfoot
    ["ab25a50a-7836-47a9-acb2-5fd93684b8c5"] = true,
    ["e730436c-53f6-4041-bdd1-3f4826f15975"] = true,
    ["cc2060b0-b588-4a54-9a73-293a8a4f2ff6"] = true,
    ["a881243c-ea11-4d4b-a7e4-0b2105c79e28"] = true,

    -- fevertonic
    ["f57b55ad-b964-4555-b564-726ab821670e"] = true,

    -- embrocation
    ["567fc1b1-1424-4784-9da8-5104e2e7354d"] = true,
    ["5cd3c6f7-ddb8-4475-870d-895d604c1d98"] = true,
    ["0e6f3e1b-961a-447e-ba58-17901f70896f"] = true,
    ["9536b229-2454-48cd-83a2-2f6292e18044"] = true,
}
