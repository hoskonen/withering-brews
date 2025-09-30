-- [scripts/WitheringBrews/Core.lua]
WitheringBrews = WitheringBrews or {}
local WB       = WitheringBrews

WB.Config      = WB.Config or { Version = "0.0.1-dev" }
WB._registered = WB._registered or false
WB._ready      = WB._ready or false

-- --- Logging & DB -----------------------------------------------------------
local function LOG(m)
    if WB.Logger and WB.Logger.Warn then WB.Logger:Warn(m) else System.LogAlways("[WitheringBrews] " .. m) end
end

local function ensureDB()
    if not WB.DB and KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory then
        WB.DB = KCDUtils.DB.Factory("witheringbrews")
    end
    return WB.DB
end

-- --- KCDUtils handshake (attach logger + DB) --------------------------------
function WB.Handshake(maxTries, delayMs)
    if WB._registered then return end
    maxTries, delayMs = maxTries or 50, delayMs or 100
    local tries = 0
    local function tick()
        if not WB._registered and KCDUtils and KCDUtils.RegisterMod then
            local mod = KCDUtils.RegisterMod({ Name = "witheringbrews" })
            WB.Logger = mod.Logger
            WB._registered = true
            ensureDB(); LOG(("WitheringBrews registered v%s"):format(WB.Config.Version))
            -- replay once in case gameplay already started before attach
            WB:OnGameplayStarted()
            return
        end
        tries = tries + 1
        if tries < maxTries then
            Script.SetTimer(delayMs, tick)
        else
            System.LogAlways("[WitheringBrews] KCDUtils did not appear")
        end
    end
    Script.SetTimer(delayMs, tick)
end

-- --- Lifecycle --------------------------------------------------------------
function WB:OnGameplayStarted()
    if WB._ready then return end
    if not WB._registered and KCDUtils and KCDUtils.RegisterMod then
        local mod = KCDUtils.RegisterMod({ Name = "witheringbrews" })
        WB.Logger = mod.Logger
        WB._registered = true
        ensureDB()
    end
    WB._ready = true
    LOG(("OnGameplayStarted → ready (v%s)"):format(self.Config.Version or "?"))

    -- DB smoke
    local db = ensureDB()
    if db then
        db:Set("WB_Config:ping", { t = os.time(), note = "hello-db" })
        LOG("DB smoke: read " .. (db:Get("WB_Config:ping") and "OK" or "nil"))
        db:Del("WB_Config:ping")
        LOG("DB smoke: delete " .. (db:Get("WB_Config:ping") == nil and "OK" or "FAILED"))
    else
        LOG("DB smoke: DB not attached yet")
    end
end

-- --- Public stubs (filled next passes) --------------------------------------
function WB.RegisterNewStacks(ctx) LOG("RegisterNewStacks (stub)") end

function WB.AgeAndDowngrade() LOG("AgeAndDowngrade (stub)") end

function WB.Tick(ctx)
    WB.RegisterNewStacks(ctx); WB.AgeAndDowngrade()
end

-- --- ItemTransfer (primary anchor) ------------------------------------------
function WB:OnItemTransferOpened(...)
    LOG("ItemTransfer opened (EL)")
end

function WB:OnItemTransferClosed(...)
    LOG("ItemTransfer closed (EL) → (next) delta & cohorts")
    -- NEXT: snapshot-after, compute delta, WB.RegisterNewStacks({ source="loot", added=... })
end

-- === Bootstrap (dry-run by default) ======================================
function WitheringBrews.BootstrapIfNeeded()
    local WB, C, D = WitheringBrews, WitheringBrews.Config or {}, WitheringBrews.Debug
    local B = C.Bootstrap or {}
    if B.enable == false then return end

    local db = WB.DB or (KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory and KCDUtils.DB.Factory("witheringbrews"))
    if not db then
        (D and D.warn or System.LogAlways)("[WitheringBrews] Bootstrap: DB not available; skipping"); return
    end

    local FLAG = B.db_flag or "WB_Config:migrated_v1"
    if db:Get(FLAG) then return end -- already migrated

    -- Our own Util (no external mod)
    local U = WitheringBrews.Util
    if not (U and U.InventorySnapshot and U.Player) then
        (D and D.warn or System.LogAlways)("[WitheringBrews] Bootstrap: Util missing; skipping")
        return
    end

    local maps = {}
    if (B.affect or {}).player ~= false then maps.player = U.InventorySnapshot(U.Player()) end
    if (B.affect or {}).stash == true then
        -- leave stash disabled by default; we don’t have a resolver yet
        (D and D.info or System.LogAlways)("[WitheringBrews] Bootstrap: stash disabled (no resolver)")
    end

    WB.BuildPotionIndex()

    local total_items, total_potions, cohorts_planned = 0, 0, 0
    local perBand = { water = 0, wine = 0, oil = 0, spirit = 0 }
    local DAY = 24 * 60 * 60
    local dryRun = (C.DryRun ~= false)
    local seed_cfg = (C.Bootstrap and C.Bootstrap.seed_age_days) or {}

    local function tierLabel(tier) return ({ "i", "ii", "iii", "iv", "v" })[tier] or tostring(tier) end
    local function seed_created_at(band, tlabel)
        local bandCfg = seed_cfg[band] or seed_cfg["water"] or {}
        local rng = bandCfg[tlabel] or { 0, 1 }
        local lo, hi = math.floor((rng[1] or 0)), math.floor((rng[2] or 0))
        if hi < lo then hi = lo end
        local days = lo + math.floor(math.random() * (hi - lo + 1))
        return os.time() - days * DAY
    end

    for scope, m in pairs(maps) do
        for cid, qty in pairs(m or {}) do
            total_items = total_items + (tonumber(qty) or 0)
            local e = WB._PotionIndex and WB._PotionIndex[cid]
            if e then
                total_potions = total_potions + (tonumber(qty) or 0)
                perBand[e.band] = (perBand[e.band] or 0) + (tonumber(qty) or 0)

                if dryRun then
                    System.LogAlways(("[WitheringBrews][Bootstrap] %s: %s (tier %s) x%d → band=%s (WOULD seed)")
                        :format(scope, e.family, tierLabel(e.tier), qty, e.band))
                    cohorts_planned = cohorts_planned + qty
                else
                    for i = 1, qty do
                        local created = seed_created_at(e.band, tierLabel(e.tier))
                        if WitheringBrews.CohortsAdd then
                            WitheringBrews.CohortsAdd(cid, 1, created, "bootstrap:" .. scope)
                        end
                        cohorts_planned = cohorts_planned + 1
                    end
                end
            end
        end
    end

    System.LogAlways(("[WitheringBrews] Bootstrap summary: scanned=%d items, potions=%d, cohorts=%d  [water=%d wine=%d oil=%d spirit=%d]")
        :format(total_items, total_potions, cohorts_planned, perBand.water or 0, perBand.wine or 0, perBand.oil or 0,
            perBand.spirit or 0))

    if not dryRun then
        db:Set(FLAG, { t = os.time(), v = 1 })
        System.LogAlways("[WitheringBrews] Bootstrap flag set (migration complete).")
    else
        System.LogAlways(
            "[WitheringBrews] DryRun=true → no cohorts written, no flag set. (Use wb_bootstrap_apply when ready.)")
    end
end

-- --- Lookup and downgrade ------------------------------------------

-- Given a template UUID, return { family, tierIndex, band } or nil
function WitheringBrews.ResolvePotionById(tplId)
    local fams = WitheringBrews.Config.PotionFamilies or {}
    for family, data in pairs(fams) do
        for tier, id in ipairs(data.ids or {}) do
            if id == tplId then
                return family, tier, data.band
            end
        end
    end
    return nil, nil, nil
end

-- Given {family, tier}, return the UUID for a lower tier (or nil if already lowest)
function WitheringBrews.DowngradeId(family, tier)
    local fam = WitheringBrews.Config.PotionFamilies[family]
    if not fam or not fam.ids then return nil end
    local nextTier = math.max(1, math.min(#fam.ids, tier - 1))
    if nextTier == tier then return nil end
    return fam.ids[nextTier]
end

-- --- Optional fades (kept tiny; harmless if they fire) ----------------------
function WB:OnHide(...) LOG("OnHide (fade)") end

function WB:OnShow(...) LOG("OnShow (fade)") end

-- --- CCommands: quick diagnostics -------------------------------------------
function WitheringBrews_Cmd_Ping() LOG("ping OK (CCommand)") end

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

-- Optional: simple DB put/get helpers while developing
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

function WitheringBrews_Cmd_BootstrapPreview()
    local C = WitheringBrews.Config or {}; local prev = C.DryRun
    WitheringBrews.Config.DryRun = true
    System.LogAlways("[WitheringBrews] Bootstrap PREVIEW (DryRun=true)")
    WitheringBrews.BuildPotionIndex()
    WitheringBrews.BootstrapIfNeeded()
    WitheringBrews.Config.DryRun = prev
end

function WitheringBrews_Cmd_BootstrapApply()
    local C = WitheringBrews.Config or {}; local prev = C.DryRun
    WitheringBrews.Config.DryRun = false
    System.LogAlways("[WitheringBrews] Bootstrap APPLY (DryRun=false)")
    WitheringBrews.BuildPotionIndex()
    WitheringBrews.BootstrapIfNeeded()
    WitheringBrews.Config.DryRun = prev
end

function WitheringBrews_Cmd_BootstrapReset()
    local db = WitheringBrews.DB or
    (KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory and KCDUtils.DB.Factory("witheringbrews"))
    if not db then
        System.LogAlways("[WitheringBrews] DB missing"); return
    end
    local flag = (WitheringBrews.Config and WitheringBrews.Config.Bootstrap and WitheringBrews.Config.Bootstrap.db_flag) or
    "WB_Config:migrated_v1"
    db:Del(flag)
    System.LogAlways("[WitheringBrews] Bootstrap flag cleared; next run will execute again.")
end
