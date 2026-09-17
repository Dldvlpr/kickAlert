-- Detector.lua
-- Alerte "KICK" quand la cible (ou le focus) lance un sort interruptible ET que
-- TON interrupt est réellement disponible. Logique reprise de
-- MyBossSuite/Modules/InterruptAlert/InterruptAlert.lua, sans la data WCL ni la
-- rotation de groupe.
--
-- Les trois conditions sont vérifiées ensemble, en continu pendant l'incantation.
-- Un kick qui revient de cooldown au milieu du cast déclenche l'alerte, et un
-- cast protégé (`notInterruptible`) n'en déclenche jamais.
local _, NS = ...

local Detector = CreateFrame("Frame")
NS.Detector = Detector

-- 0.15s : assez fin pour attraper la fin d'un cooldown au milieu d'un cast,
-- assez lâche pour ne rien coûter. Le ticker ne tourne que pendant une incantation.
local POLL_INTERVAL = 0.15

-- Durée de vie d'une incantation déduite du combat log, quand le client ne sait
-- pas répondre à UnitCastingInfo sur une unité hostile.
local FALLBACK_CAST_MAX = 6

--------------------------------------------------------------------------------
-- Sorts d'interruption
--------------------------------------------------------------------------------
-- Table par classe, plusieurs ids par classe : le bon est celui que le joueur
-- connaît réellement (`NS.KnowsSpell` couvre aussi les rangs Classic).

local INTERRUPTS = {
    WARRIOR     = { 6552, 72 },                   -- Pummel, Shield Bash
    ROGUE       = { 1766 },                       -- Kick
    MAGE        = { 2139 },                       -- Counterspell
    SHAMAN      = { 57994, 8042 },                -- Wind Shear, Earth Shock
    PRIEST      = { 15487 },                      -- Silence
    DRUID       = { 106839, 80965, 16979 },       -- Skull Bash, Feral Charge
    PALADIN     = { 96231, 31935 },               -- Rebuke, Avenger's Shield
    DEATHKNIGHT = { 47528, 47476 },               -- Mind Freeze, Strangulate
    HUNTER      = { 147362, 187707, 34490 },      -- Counter Shot, Muzzle, Silencing Shot
    WARLOCK     = { 19647, 119910, 132409 },      -- Spell Lock (familier)
    MONK        = { 116705 },                     -- Spear Hand Strike
    DEMONHUNTER = { 183752 },                     -- Disrupt
    EVOKER      = { 351338 },                     -- Quell
}
Detector.INTERRUPTS = INTERRUPTS

function Detector:ResolveInterrupt()
    local override = NS.db and NS.db.spellId
    if override then
        self.interruptSpell = override
        self.interruptName  = NS.GetSpellName(override) or tostring(override)
        return override
    end

    local _, class = UnitClass("player")
    local candidates = INTERRUPTS[class or ""]
    self.interruptSpell, self.interruptName = nil, nil
    if not candidates then return nil end
    for i = 1, #candidates do
        if NS.KnowsSpell(candidates[i]) then
            self.interruptSpell = candidates[i]
            self.interruptName  = NS.GetSpellName(candidates[i])
            return self.interruptSpell
        end
    end
    return nil
end

--- Cooldown restant du kick. nil = pas d'interrupt connu.
function Detector:InterruptRemaining()
    if not self.interruptSpell then return nil end
    return NS.GetSpellRemaining(self.interruptSpell)
end

--------------------------------------------------------------------------------
-- Incantations lues dans le combat log
--------------------------------------------------------------------------------
-- Repli pour les clients où UnitCastingInfo ne répond rien sur une unité hostile.
-- Le combat log ne dit pas si le sort est protégé : on assume interruptible
-- plutôt que de rater le kick.

local casts = {}   -- [guid] = { name, spellId, expires }

local function ClearCast(guid)
    if guid then casts[guid] = nil end
end

function Detector:FallbackCast(guid)
    local cast = guid and casts[guid]
    if not cast then return nil end
    if GetTime() > cast.expires then
        casts[guid] = nil
        return nil
    end
    return cast.name, cast.spellId
end

--- GUID des unités surveillées, mis à jour sur changement de cible / focus.
-- Le combat log les compare directement : aucun appel d'API dans le chemin chaud.
function Detector:UpdateWatchedGUIDs()
    self.targetGUID = UnitExists("target") and UnitGUID("target") or nil
    self.focusGUID  = NS.has.focus and NS.db.watchFocus ~= false
        and UnitExists("focus") and UnitGUID("focus") or nil
    for guid in pairs(casts) do
        if guid ~= self.targetGUID and guid ~= self.focusGUID then casts[guid] = nil end
    end
end

local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo

local function OnCombatLog()
    local _, sub, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()
    if sub == "SPELL_CAST_START" then
        if srcGUID ~= Detector.targetGUID and srcGUID ~= Detector.focusGUID then return end
        casts[srcGUID] = {
            name    = spellName or NS.GetSpellName(spellId) or "?",
            spellId = spellId,
            expires = GetTime() + FALLBACK_CAST_MAX,
        }
        Detector:Wake()
    elseif sub == "SPELL_CAST_SUCCESS" or sub == "SPELL_CAST_FAILED" then
        if casts[srcGUID] then
            ClearCast(srcGUID)
            Detector:Evaluate()
        end
    elseif sub == "SPELL_INTERRUPT" then
        -- dstGUID : c'est l'unité interrompue, pas l'interrupteur.
        if casts[dstGUID] then ClearCast(dstGUID) end
        Detector:Evaluate()
    elseif sub == "UNIT_DIED" then
        ClearCast(dstGUID)
    end
end

--------------------------------------------------------------------------------
-- Évaluation
--------------------------------------------------------------------------------

local WATCH_UNITS = { "target", "focus" }

--- Première incantation interruptible trouvée sur les unités surveillées.
-- Retourne unit, name, spellId. L'API du client fait foi ; le combat log ne
-- sert que là où elle ne répond rien.
function Detector:FindCast()
    for i = 1, #WATCH_UNITS do
        local unit = WATCH_UNITS[i]
        if (unit ~= "focus" or (NS.has.focus and NS.db.watchFocus ~= false))
            and UnitExists(unit) and NS.CanAttackUnit(unit) then
            local name, _, _, _, notInterruptible, spellId = NS.GetCastInfo(unit)
            if name then
                if not notInterruptible then return unit, name, spellId end
            else
                local fallbackName, fallbackSpell = self:FallbackCast(UnitGUID(unit))
                if fallbackName then return unit, fallbackName, fallbackSpell end
            end
        end
    end
    return nil
end

function Detector:InRange(unit)
    if not self.interruptName or not NS.IsSpellInRange then return true end
    -- 0 = hors de portée, 1 = à portée, nil = le client ne sait pas : seul le 0 franc bloque.
    return NS.IsSpellInRange(self.interruptName, unit) ~= 0
end

function Detector:Evaluate()
    if not NS.db then return end
    if _G.UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        self:ClearAlert()
        return self:Sleep()
    end

    local unit, name, spellId = self:FindCast()
    if not unit then
        self:ClearAlert()
        return self:Sleep()
    end

    -- Une incantation est en cours : le ticker tourne, même sans alerte affichée,
    -- pour attraper la fin du cooldown ou l'entrée en portée.
    self:EnsurePolling()

    local remaining = self:InterruptRemaining()
    local ready = (remaining ~= nil and remaining <= 0)
    if NS.db.onlyWhenReady ~= false and not ready then return self:ClearAlert() end
    if NS.db.checkRange ~= false and not self:InRange(unit) then return self:ClearAlert() end

    self:ShowAlert(unit, name, spellId)
end

--- Une signature par incantation : le même cast ne doit pas rejouer le son à chaque tick.
function Detector:ShowAlert(unit, name, spellId)
    local signature = unit .. "|" .. tostring(spellId or name)
    if self.showing == signature then return end
    self.showing = signature
    NS:Fire("CAST_START", unit, name, spellId)
end

function Detector:ClearAlert()
    if not self.showing then return end
    self.showing = nil
    NS:Fire("CAST_STOP")
end

--------------------------------------------------------------------------------
-- Ticker
--------------------------------------------------------------------------------

function Detector:EnsurePolling()
    if self.poll then return end
    self.poll = NS.Timer.NewTicker(POLL_INTERVAL, function() Detector:Evaluate() end)
end

function Detector:Wake()
    self:EnsurePolling()
    self:Evaluate()
end

function Detector:Sleep()
    if not self.poll then return end
    self.poll:Cancel()
    self.poll = nil
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local function IsWatched(unit)
    return unit == "target" or unit == "focus"
end

Detector:SetScript("OnEvent", function(self, event, unit)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        self:UpdateWatchedGUIDs()
        self:ClearAlert()
        self:Wake()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:ClearAlert()
        self:Sleep()
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
        self:ResolveInterrupt()
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:ResolveInterrupt()
        self:UpdateWatchedGUIDs()
        self:Wake()
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        if not IsWatched(unit) then return end
        -- Le client a vu la fin de l'incantation : l'entrée du repli combat log pour
        -- cette unité n'a plus lieu d'être (SPELL_CAST_FAILED n'est jamais loggé pour un PNJ).
        ClearCast(UnitGUID(unit))
        self:Evaluate()
    elseif IsWatched(unit) then
        -- START, CHANNEL_START, DELAYED, INTERRUPTIBLE, NOT_INTERRUPTIBLE, EMPOWER_START
        self:Wake()
    end
end)

--------------------------------------------------------------------------------
-- État lisible (/ka status)
--------------------------------------------------------------------------------

function Detector:StatusLines()
    local remaining = self:InterruptRemaining()
    local spell = self.interruptSpell
        and ("%s (%d)"):format(self.interruptName or "?", self.interruptSpell)
        or "|cffff5555aucun détecté|r"
    return {
        "interrupt : " .. spell .. (NS.db.spellId and " |cffaaaaaa(forcé)|r" or ""),
        ("disponible : %s"):format(
            remaining == nil and "?" or (remaining <= 0 and "oui" or ("dans %.1fs"):format(remaining))),
        ("focus : %s   portée : %s   kick dispo requis : %s"):format(
            NS.db.watchFocus ~= false and "oui" or "non",
            NS.db.checkRange ~= false and "oui" or "non",
            NS.db.onlyWhenReady ~= false and "oui" or "non"),
        ("lecture des incantations : %s"):format(
            NS.has.unitCastInfo and "API du client (+ repli combat log)" or "combat log uniquement"),
    }
end

--------------------------------------------------------------------------------
-- Démarrage
--------------------------------------------------------------------------------

NS:On("DB_READY", function()
    Detector:ResolveInterrupt()

    for _, event in ipairs({
        "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_ENABLED",
        "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_ENTERING_WORLD",
        -- Enregistré même quand UnitCastingInfo existe : sur les clients les plus
        -- anciens l'API répond nil sur une unité hostile, seul le combat log voit l'incantation.
        "COMBAT_LOG_EVENT_UNFILTERED",
    }) do
        NS.RegisterEventSafe(Detector, event)
    end

    for _, event in ipairs({
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
        "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP", -- retail (évocateur)
    }) do
        -- RegisterUnitEvent limite le coût aux unités surveillées quand il existe.
        NS.RegisterEventSafe(Detector, event, "target", "focus")
    end

    Detector:UpdateWatchedGUIDs()
    Detector:Wake()
end)
