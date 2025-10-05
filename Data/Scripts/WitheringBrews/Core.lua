-- [scripts/WitheringBrews/Core.lua]
WitheringBrews                     = WitheringBrews or {}
local WB                           = WitheringBrews

WB.Config                          = WB.Config or { Version = "0.0.1-dev" }
WB._registered                     = WB._registered or false
WB._ready                          = WB._ready or false

WitheringBrews._loot_open_snapshot = nil

-- Logging & DB -----------------------------------------------------------
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

-- Lifecycle
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

    WitheringBrews.BuildPotionIndex()
    WitheringBrews.BootstrapIfNeeded()
end

-- Public stubs (filled next passes) --------------------------------------
function WB.RegisterNewStacks(ctx) LOG("RegisterNewStacks (stub)") end

function WB.AgeAndDowngrade() LOG("AgeAndDowngrade (stub)") end

function WB.Tick(ctx)
    WB.RegisterNewStacks(ctx); WB.AgeAndDowngrade()
end

-- --- ItemTransfer (primary anchor) ------------------------------------------
function WB:OnItemTransferOpened(...)
    System.LogAlways("[WitheringBrews] ItemTransfer opened (EL)")
    local U = self.Util
    self.BuildPotionIndex()
    self._loot_open_snapshot = U and U.InventorySnapshot and
    U.InventorySnapshot(U.Util and U.Util.Player and U.Util.Player() or nil) or {}
    System.LogAlways(string.format("[WitheringBrews] LootOpen snapshot: kinds=%d",
        (function(t)
            local c = 0; for _ in pairs(t or {}) do c = c + 1 end; return c
        end)(self._loot_open_snapshot)))
end

function WB:OnItemTransferClosed(...)
    System.LogAlways("[WitheringBrews] ItemTransfer closed (EL) → diff + cohorts")
    local U, D = self.Util, self.Debug
    if not self._loot_open_snapshot then
        if D and D.warn then D.warn("No open snapshot; skipping diff") end
        return
    end
    local after = U and U.InventorySnapshot and U.InventorySnapshot(U.Player and U.Player() or nil) or {}
    local added, removed = U.DiffCounts(self._loot_open_snapshot, after)
    self._loot_open_snapshot = nil

    local idx = self._PotionIndex or {}
    local totalAdded = 0
    for cid, qty in pairs(added) do
        totalAdded = totalAdded + qty
        local e = idx[cid]
        if e then
            -- Dry-run: only log; when enabled, push to cohorts
            System.LogAlways(string.format(
                "[WitheringBrews] Loot delta: POTION %s (family=%s tier=%s band=%s) +%d (WOULD seed)",
                cid, e.family, ({ "i", "ii", "iii", "iv", "v" })[e.tier] or e.tier, e.band, qty))
            if self.Config and self.Config.DryRun == false and self.CohortsAdd then
                for i = 1, qty do self.CohortsAdd(cid, 1, os.time(), "loot") end
            end
        else
            System.LogAlways(string.format("[WitheringBrews] Loot delta: %s +%d (ignored; not a potion)", cid, qty))
        end
    end
    System.LogAlways(string.format("[WitheringBrews] Loot delta summary: addedKinds=%d addedTotal=%d",
        (function(t)
            local c = 0; for _ in pairs(t) do c = c + 1 end; return c
        end)(added), totalAdded))
end

-- === Bootstrap (dry-run by default) ======================================
function WitheringBrews.BootstrapIfNeeded()
    local WB, C = WitheringBrews, WitheringBrews.Config or {}
    local D = WitheringBrews.Debug
    local B = C.Bootstrap or {}

    local function info(s) if D and D.info then D.info(s) else System.LogAlways("[WitheringBrews] " .. s) end end
    local function warn(s) if D and D.warn then D.warn(s) else System.LogAlways("[WitheringBrews][WARN] " .. s) end end

    info("Bootstrap: enter")
    if B.enable == false then
        warn("Bootstrap: disabled via config"); info("Bootstrap: exit"); return
    end

    local db = WB.DB or (KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory and KCDUtils.DB.Factory("witheringbrews"))
    if not db then
        warn("Bootstrap: DB not available; skipping"); info("Bootstrap: exit"); return
    end

    local FLAG = B.db_flag or "WB_Config:migrated_v1"
    if db:Get(FLAG) then
        info("Bootstrap: flag already set → nothing to do"); info("Bootstrap: exit"); return
    end

    -- Util presence
    local U = WitheringBrews.Util
    if not (U and U.InventorySnapshot and U.Player) then
        warn("Bootstrap: Util missing (Util.lua not loaded?)"); info("Bootstrap: exit"); return
    end

    -- Player entity
    local player = U.Player()
    if not player then warn("Bootstrap: no player entity"); end

    -- Build index (safe if empty)
    if not WB._PotionIndex then WB.BuildPotionIndex() end
    info("Bootstrap: potion index size=" ..
        tostring(WB._PotionIndex and (next(WB._PotionIndex) and "nonzero" or "zero") or "nil"))

    -- Snapshots (currently stubbed; fine)
    local maps = {}
    if (B.affect or {}).player ~= false then
        maps.player = U.InventorySnapshot(player)
        info("Bootstrap: took player snapshot (size=" ..
            (maps.player and tostring(#(function(t)
                local c = 0; for _ in pairs(t) do c = c + 1 end; return { c }
            end)(maps.player)[1]) or "nil") .. ")")
    end
    if (B.affect or {}).stash == true then
        info("Bootstrap: stash requested but not implemented; skipping")
    end

    local total_items, total_potions, cohorts_planned = 0, 0, 0
    local perBand = { water = 0, wine = 0, oil = 0, spirit = 0 }
    local dryRun = (C.DryRun ~= false)
    local DAY = 24 * 60 * 60
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

    -- Iterate
    local matched_ids, matched_qty = 0, 0

    local okLoop, err = pcall(function()
        for scope, m in pairs(maps) do
            local unique = 0
            for cid, qty in pairs(m or {}) do
                unique = unique + 1
                total_items = total_items + (tonumber(qty) or 0)
                local e = WB._PotionIndex and WB._PotionIndex[cid]
                if e then
                    matched_ids     = matched_ids + 1
                    matched_qty     = matched_qty + (tonumber(qty) or 0)
                    total_potions   = total_potions + (tonumber(qty) or 0)
                    perBand[e.band] = (perBand[e.band] or 0) + (tonumber(qty) or 0)

                    if dryRun then
                        info(("[Bootstrap] %s: %s (tier %s) x%d → band=%s (WOULD seed)")
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
            info(("Bootstrap: scope=%s uniqueIds=%d"):format(scope, unique))
        end
    end)
    if not okLoop then
        warn("Bootstrap: iteration error → " .. tostring(err))
    end

    info(("[Bootstrap] matched=%d ids (qty=%d)"):format(matched_ids, matched_qty))
    info(("[Bootstrap] summary: scanned=%d items, potions=%d, cohorts=%d  [water=%d wine=%d oil=%d spirit=%d] dryRun=%s")
        :format(total_items, total_potions, cohorts_planned,
            perBand.water or 0, perBand.wine or 0, perBand.oil or 0, perBand.spirit or 0,
            tostring(dryRun)))

    if not dryRun then
        db:Set(FLAG, { t = os.time(), v = 1 })
        info("Bootstrap: flag set (migration complete).")
    else
        info("Bootstrap: DryRun=true → no cohorts written, no flag set.")
    end
    info("Bootstrap: exit")
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

-- === Potion reverse index (UUID -> {family,tier,label,band}) ===============
function WitheringBrews.BuildPotionIndex()
    local WB = WitheringBrews
    local fams = (WB.Config and WB.Config.PotionFamilies) or {}
    local idx = {}
    for family, data in pairs(fams) do
        local band = data.band or "water"
        for tierIdx, id in ipairs(data.ids or {}) do
            local label = ({ "i", "ii", "iii", "iv", "v" })[tierIdx] or tostring(tierIdx)
            idx[id] = { family = family, tier = tierIdx, label = label, band = band }
        end
    end
    WB._PotionIndex = idx
end

-- --- Optional fades (kept tiny; harmless if they fire) ----------------------
function WB:OnHide(...) LOG("OnHide (fade)") end

function WB:OnShow(...) LOG("OnShow (fade)") end
