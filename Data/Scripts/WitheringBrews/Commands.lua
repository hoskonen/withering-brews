-- [scripts/WitheringBrews/Commands.lua]
WitheringBrews = WitheringBrews or {}
local WB, U = WitheringBrews, WitheringBrews.Util

-- --- DB helpers -------------------------------------------------------------
local function ensureDB()
    if not WB.DB and KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory then
        WB.DB = KCDUtils.DB.Factory("witheringbrews")
    end
    return WB.DB
end

function WitheringBrews_Cmd_Ping()
    System.LogAlways("[WitheringBrews] ping OK (CCommand)")
end

function WitheringBrews_Cmd_DbTest()
    local db = ensureDB()
    if not db then
        System.LogAlways("[WitheringBrews] DB missing"); return
    end
    db:Set("WB_Config:ccmd", { t = os.time(), note = "from CCmd" })
    System.LogAlways("[WitheringBrews] db_test set->get: " .. (db:Get("WB_Config:ccmd") and "OK" or "nil"))
    db:Del("WB_Config:ccmd")
    System.LogAlways("[WitheringBrews] db_test del: " .. (db:Get("WB_Config:ccmd") == nil and "OK" or "FAILED"))
end

function WitheringBrews_Cmd_DbPut(key, value)
    if not key then
        System.LogAlways("[WitheringBrews] usage: wb_db_put <key> <value>"); return
    end
    local db = ensureDB(); if not db then
        System.LogAlways("[WitheringBrews] DB missing"); return
    end
    db:Set(key, value or "1"); System.LogAlways("[WitheringBrews] db_put " .. key .. "=" .. tostring(value or "1"))
end

function WitheringBrews_Cmd_DbGet(key)
    if not key then
        System.LogAlways("[WitheringBrews] usage: wb_db_get <key>"); return
    end
    local db = ensureDB(); if not db then
        System.LogAlways("[WitheringBrews] DB missing"); return
    end
    local v = db:Get(key); System.LogAlways("[WitheringBrews] db_get " .. key .. " -> " .. tostring(v))
end

function WitheringBrews_Cmd_UiDiag()
    local f = function(x) return (UIAction and UIAction[x]) and "yes" or "no" end
    System.LogAlways("[WitheringBrews] UIAction? " .. (UIAction and "yes" or "no"))
    System.LogAlways("[WitheringBrews]  - RegisterEventSystemListener: " .. f("RegisterEventSystemListener"))
    System.LogAlways("[WitheringBrews]  - RegisterEventMovieListener: " .. f("RegisterEventMovieListener"))
    System.LogAlways("[WitheringBrews]  - RegisterFSCommandListener: " .. f("RegisterFSCommandListener"))
    System.LogAlways("[WitheringBrews]  - RegisterElementListener: " .. f("RegisterElementListener"))
end

-- --- Bootstrap --------------------------------------------------------------
function WitheringBrews_Cmd_BootstrapPreview()
    local C = WB.Config or {}; local prev = C.DryRun
    WB.Config.DryRun = true
    System.LogAlways("[WitheringBrews] Bootstrap PREVIEW (DryRun=true)")
    WB.BuildPotionIndex()
    WB.BootstrapIfNeeded()
    WB.Config.DryRun = prev
end

function WitheringBrews_Cmd_BootstrapApply()
    local C = WB.Config or {}; local prev = C.DryRun
    WB.Config.DryRun = false
    System.LogAlways("[WitheringBrews] Bootstrap APPLY (DryRun=false)")
    WB.BuildPotionIndex()
    WB.BootstrapIfNeeded()
    WB.Config.DryRun = prev
end

function WitheringBrews_Cmd_BootstrapReset()
    local db = WB.DB or (KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory and KCDUtils.DB.Factory("witheringbrews"))
    if not db then
        System.LogAlways("[WitheringBrews] DB missing"); return
    end
    local flag = (WB.Config and WB.Config.Bootstrap and WB.Config.Bootstrap.db_flag) or "WB_Config:migrated_v1"
    db:Del(flag)
    System.LogAlways("[WitheringBrews] Bootstrap flag cleared; next run will execute again.")
end

-- --- Inventory / potions inspection ----------------------------------------
function WitheringBrews_Cmd_UtilWho()
    local p = U and U.Player and U.Player() or nil
    System.LogAlways("[WitheringBrews] UtilWho: player=" .. tostring(p and p.id or "nil"))
end

function WitheringBrews_Cmd_UtilSnap()
    local snap = U and U.InventorySnapshot and U.InventorySnapshot() or {}
    local nUnique, nTotal = 0, 0
    for _, q in pairs(snap) do
        nUnique = nUnique + 1; nTotal = nTotal + (tonumber(q) or 0)
    end
    System.LogAlways("[WitheringBrews] UtilSnap: unique=" .. nUnique .. ", total=" .. nTotal)
    local printed = 0
    for cid, qty in pairs(snap) do
        local tag = (U and U.IsPotionId and U.IsPotionId(cid)) and "POTION " or ""
        System.LogAlways(string.format("[WitheringBrews]   %s%s x%d", tag, cid, qty))
        printed = printed + 1; if printed >= 10 then break end
    end
end

function WitheringBrews_Cmd_ScanPotions()
    local snap = U and U.InventorySnapshot and U.InventorySnapshot(U.Player()) or {}
    WB.BuildPotionIndex()
    local byFam, total = {}, 0

    for cid, qty in pairs(snap) do
        local e = WB.GetTrackedPotion(cid)
        if e then
            byFam[e.family] = (byFam[e.family] or 0) + (tonumber(qty) or 0); total = total + (tonumber(qty) or 0)
        end
    end
    System.LogAlways(("[WitheringBrews] ScanPotions: totalMatched=%d"):format(total))
    local printed = 0
    for fam, qty in pairs(byFam) do
        System.LogAlways(("[WitheringBrews]  - %s x%d"):format(fam, qty))
        printed = printed + 1; if printed >= 20 then break end
    end
    if printed == 0 then System.LogAlways("[WitheringBrews]  (no potions matched current families)") end
end

function WitheringBrews_Cmd_PotionsReload()
    local path =
        "Scripts/WitheringBrews/Potions.lua"

    local beforeCount =
        tonumber(WitheringBrews._potionsLoadCount) or 0

    local unloadOk, unloadErr = pcall(
        Script.UnloadScript,
        path
    )

    if not unloadOk then
        System.LogAlways(
            "[WitheringBrews] Potions reload FAILED during unload: "
            .. tostring(unloadErr)
        )
        return
    end

    local reloadOk, reloadErr = pcall(
        Script.ReloadScript,
        path
    )

    if not reloadOk then
        System.LogAlways(
            "[WitheringBrews] Potions reload FAILED during reload: "
            .. tostring(reloadErr)
        )
        return
    end

    local afterCount =
        tonumber(WitheringBrews._potionsLoadCount) or 0

    if afterCount <= beforeCount then
        System.LogAlways(
            "[WitheringBrews] Potions reload FAILED: "
            .. "Potions.lua did not execute"
        )
        return
    end

    WitheringBrews.BuildPotionIndex()

    System.LogAlways(
        ("[WitheringBrews] Potions reloaded and index rebuilt "
            .. "(loadCount=%d)")
            :format(afterCount)
    )
end

function WitheringBrews_Cmd_PotionAllow(cid)
    if not cid then
        System.LogAlways("[WitheringBrews] usage: wb_potion_allow <classId>")
        return
    end
    local C = WitheringBrews.Config; C.PotionWhitelist = C.PotionWhitelist or {}
    C.PotionWhitelist[cid] = true
    System.LogAlways("[WitheringBrews] whitelist + " .. cid)
end

function WitheringBrews_Cmd_PotionBlock(cid)
    if not cid then
        System.LogAlways("[WitheringBrews] usage: wb_potion_block <classId>")
        return
    end
    local C = WitheringBrews.Config; C.PotionWhitelist = C.PotionWhitelist or {}
    C.PotionWhitelist[cid] = nil
    System.LogAlways("[WitheringBrews] whitelist - " .. cid)
end

function WitheringBrews_Cmd_PotionList()
    local wl = (WitheringBrews.Config and WitheringBrews.Config.PotionWhitelist) or {}
    local n = 0; for _ in pairs(wl) do n = n + 1 end
    System.LogAlways("[WitheringBrews] whitelist entries: " .. n)
    local shown = 0
    for cid, _ in pairs(wl) do
        System.LogAlways("  " .. cid)
        shown = shown + 1; if shown >= 50 then break end
    end
end

function WitheringBrews_Cmd_WhitelistFromFamilies()
    local C = WitheringBrews.Config
    C.PotionWhitelist = C.PotionWhitelist or {}
    local fams = C.PotionFamilies or {}
    local n = 0
    for _, data in pairs(fams) do
        for _, id in ipairs(data.ids or {}) do
            C.PotionWhitelist[id] = true
            n = n + 1
        end
    end
    System.LogAlways(("[WitheringBrews] Whitelist populated from families: %d ids"):format(n))
end

function WitheringBrews_Cmd_CohValidate()
    if type(WB.CohortsValidatePlayer) ~= "function" then
        System.LogAlways(
            "[WitheringBrews] Cohort validator unavailable"
        )
        return
    end

    WB.CohortsValidatePlayer()
end

function WitheringBrews_Cmd_AgingSelfTest()
    local aging = WB.Aging

    if not (
        aging
        and type(aging.RunSelfTests) == "function"
    ) then
        System.LogAlways(
            "[WitheringBrews] Aging self-test unavailable"
        )

        return
    end

    aging.RunSelfTests()
end

function WitheringBrews_Cmd_AgingPreview()
    local aging = WB.Aging

    if not (
        aging
        and type(aging.PreviewPlayer) == "function"
    ) then
        System.LogAlways(
            "[WitheringBrews] Aging preview unavailable"
        )

        return
    end

    aging.PreviewPlayer()
end

function WitheringBrews_Cmd_AgingTxPreview()
    local execution = WB.AgingExecution

    if not (
        execution
        and type(
            execution.PreviewPlayerTransaction
        ) == "function"
    ) then
        System.LogAlways(
            "[WitheringBrews] Aging transaction preview unavailable"
        )

        return
    end

    execution.PreviewPlayerTransaction()
end

function WitheringBrews_Cmd_AgingInventoryRoundTrip(classId, quantity,confirmation)
    local execution = WB.AgingExecution

    if not (
        execution
        and type(
            execution.TestInventoryRoundTrip
        ) == "function"
    ) then
        System.LogAlways(
            "[WitheringBrews] Aging inventory round-trip unavailable"
        )

        return
    end

    execution.TestInventoryRoundTrip(
        classId,
        quantity,
        confirmation
    )
end

function WitheringBrews_Cmd_AgingValidateRules()
    local aging = WB.Aging

    if not (
        aging
        and type(
            aging.ValidateConfiguredRules
        ) == "function"
    ) then
        System.LogAlways(
            "[WitheringBrews] Aging rule validator unavailable"
        )

        return
    end

    aging.ValidateConfiguredRules()
end

-- --- Foundation diagnostics / development helpers --------------------------
local function dev()
    return WitheringBrews and WitheringBrews.Dev or nil
end

function WitheringBrews_Cmd_Help()
    local Dv = dev()
    if Dv and Dv.PrintHelp then Dv.PrintHelp() else System.LogAlways("[WitheringBrews] Dev.lua missing") end
end

function WitheringBrews_Cmd_Status()
    local Dv = dev()
    if Dv and Dv.PrintStatus then Dv.PrintStatus() else System.LogAlways("[WitheringBrews] Dev.lua missing") end
end

function WitheringBrews_Cmd_Validate()
    local Dv = dev()
    if Dv and Dv.Validate then Dv.Validate() else System.LogAlways("[WitheringBrews] Dev.lua missing") end
end

function WitheringBrews_Cmd_Time()
    local Dv = dev()
    if Dv and Dv.PrintTime then Dv.PrintTime() else System.LogAlways("[WitheringBrews] Dev.lua missing") end
end

function WitheringBrews_Cmd_SpawnPotion(family, tier, quantity)
    local Dv = dev()
    if Dv and Dv.SpawnPotion then
        Dv.SpawnPotion(family, tier, quantity)
    else
        System.LogAlways("[WitheringBrews] Dev.lua missing")
    end
end

function WitheringBrews_Cmd_SpawnTestSet(tier, quantity)
    local Dv = dev()
    if Dv and Dv.SpawnTestSet then
        Dv.SpawnTestSet(tier, quantity)
    else
        System.LogAlways("[WitheringBrews] Dev.lua missing")
    end
end

function WitheringBrews_Cmd_AgingCohortRoundTrip(classId, confirmation)
    local execution = WB.AgingExecution

    if not (
        execution
        and type(
            execution.TestCohortRoundTrip
        ) == "function"
    ) then
        System.LogAlways(
            "[WitheringBrews] Aging cohort round-trip unavailable"
        )

        return
    end

    execution.TestCohortRoundTrip(
        classId,
        confirmation
    )
end

function WitheringBrews_Cmd_AgingTxApply(confirmation)
    local execution = WB.AgingExecution

    if not (
        execution
        and type(
            execution.ApplyPlayerTransaction
        ) == "function"
    ) then
        System.LogAlways(
            "[WitheringBrews] Aging transaction apply unavailable"
        )

        return
    end

    execution.ApplyPlayerTransaction(
        confirmation
    )
end

function WitheringBrews_Cmd_AgingTxTestAfterRemovals(confirmation)
    local execution =
        WB.AgingExecution

    if not (
        execution
        and type(
            execution.TestCompensationAfterRemovals
        ) == "function"
    ) then
        System.LogAlways(
            "[WitheringBrews] Aging compensation test unavailable"
        )

        return false
    end

    return execution.TestCompensationAfterRemovals(
        confirmation
    )
end

function WitheringBrews_Cmd_AgingTxTestAfterAdditions(confirmation)
    local execution =
        WB.AgingExecution

    if not (
        execution
        and type(
            execution.TestCompensationAfterAdditions
        ) == "function"
    ) then
        System.LogAlways(
            "[WitheringBrews] Aging compensation test unavailable"
        )

        return false
    end

    return execution.TestCompensationAfterAdditions(
        confirmation
    )
end

function WitheringBrews_Cmd_AgingTxTestAfterCohortWrite(confirmation)
    local execution =
        WB.AgingExecution

    if not (
        execution
        and type(
            execution.TestCompensationAfterFirstCohortWrite
        ) == "function"
    ) then
        System.LogAlways(
            "[WitheringBrews] Aging compensation test unavailable"
        )

        return false
    end

    return execution.TestCompensationAfterFirstCohortWrite(
        confirmation
    )
end

function WitheringBrews_Cmd_AgingTxTestAfterCohortWrites(confirmation)
    local execution =
        WB.AgingExecution

    if not (
        execution
        and type(
            execution.TestCompensationAfterCohortWrites
        ) == "function"
    ) then
        System.LogAlways(
            "[WitheringBrews] Aging compensation test unavailable"
        )

        return false
    end

    return execution.TestCompensationAfterCohortWrites(
        confirmation
    )
end

function WitheringBrews_Cmd_InstallMultiTransitionFixture(confirmation)
    local execution =
        WB.AgingExecution

    if not (
        execution
        and type(
            execution.InstallMultiTransitionFixture
        ) == "function"
    ) then
        System.LogAlways(
            "[WitheringBrews] Multi-transition fixture installer unavailable"
        )

        return false
    end

    return execution.InstallMultiTransitionFixture(
        confirmation
    )
end

function WitheringBrews_Cmd_InstallCompactionFixture(confirmation)
    local execution =
        WB.AgingExecution

    if not (
        execution
        and type(
            execution.InstallCompactionFixture
        ) == "function"
    ) then
        System.LogAlways(
            "[WitheringBrews] Compaction fixture installer unavailable"
        )

        return false
    end

    return execution.InstallCompactionFixture(
        confirmation
    )
end