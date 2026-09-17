-- Core.lua
-- SavedVariables, bus interne, mixin de positionnement, commandes slash.
local ADDON_NAME, NS = ...

NS.DEFAULTS = {
    version = 1,
    -- Déclenchement (mêmes réglages que le module InterruptAlert de MyBossSuite)
    watchFocus    = true,    -- surveille aussi le focus
    onlyWhenReady = true,    -- n'alerte que si ton kick est disponible
    checkRange    = true,    -- ... et que la cible est à portée
    spellId       = nil,     -- override manuel du sort d'interruption (/ka spell <id>)
    text = {
        enabled = true,
        label = "KICK",
        font = "Fonts\\FRIZQT__.TTF",
        size = 48,
        outline = "OUTLINE",        -- "NONE" | "OUTLINE" | "THICKOUTLINE"
        color = { r = 0.25, g = 0.85, b = 1, a = 1 },
        pulse = true,
        pulseSpeed = 2,             -- pulsations par seconde
    },
    aura = {
        enabled = true,
        color = { r = 0.25, g = 0.85, b = 1, a = 0.8 },
        thickness = 140,            -- épaisseur du halo en pixels
        pulse = true,
        pulseSpeed = 2,
    },
    sound = {
        enabled = true,
        sound = "alarm",            -- preset, id de SOUNDKIT ou chemin de fichier
        throttle = 0.4,             -- anti-spam sonore, en secondes
    },
    -- KICK au-dessus de la nameplate de n'importe quelle cible hostile, sans la cibler.
    nameplate = {
        enabled = true,
        text = {
            label = "KICK",
            font = "Fonts\\FRIZQT__.TTF",
            size = 14,
            outline = "OUTLINE",
            color = { r = 1, g = 0.2, b = 0.2, a = 1 },
        },
    },
    anchors = {},
}

local function CopyDefaults(defaults, target)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            CopyDefaults(value, target[key])
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

-- Bus interne : "CAST_START"(unit, spellName, spellId), "CAST_STOP"(), "DB_READY",
-- "UNLOCK"(bool), "RESET_ANCHORS".
local listeners = {}
function NS:On(event, fn)
    listeners[event] = listeners[event] or {}
    local list = listeners[event]
    list[#list + 1] = fn
end

function NS:Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do list[i](...) end
end

--------------------------------------------------------------------------------
-- Mixin de positionnement : drag en mode unlock, position sauvée par anchorKey.
-- relativeTo conservé et SetClampedToScreen, comme dans MyBossSuite/Core/Anchors.lua.
--------------------------------------------------------------------------------
NS.AnchorMixin = {}
local AnchorMixin = NS.AnchorMixin

function AnchorMixin:EnablePositioning()
    self:SetMovable(true)
    self:SetClampedToScreen(true)
    self:RegisterForDrag("LeftButton")
    self:SetScript("OnDragStart", self.StartMoving)
    self:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        frame:SaveAnchor()
    end)
    self:EnableMouse(false)
end

function AnchorMixin:SaveAnchor()
    local point, relTo, relPoint, x, y = self:GetPoint()
    if not point then return end
    NS.db.anchors[self.anchorKey] = {
        point = point,
        relTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent",
        relPoint = relPoint,
        x = x, y = y,
    }
end

function AnchorMixin:LoadAnchor()
    local saved = NS.db.anchors[self.anchorKey]
    self:ClearAllPoints()
    if saved then
        self:SetPoint(saved.point, _G[saved.relTo] or UIParent, saved.relPoint, saved.x, saved.y)
    else
        local point = self.defaultPoint or "CENTER"
        self:SetPoint(point, UIParent, point, 0, self.defaultY or 0)
    end
end

function AnchorMixin:ResetAnchor()
    NS.db.anchors[self.anchorKey] = nil
    self:LoadAnchor()
end

--------------------------------------------------------------------------------
-- Modes unlock et test
--------------------------------------------------------------------------------

NS.unlocked = false
function NS:SetUnlocked(unlocked)
    self.unlocked = unlocked
    self:Fire("UNLOCK", unlocked)
    NS.Print(unlocked and "Mode déplacement activé. /ka lock pour verrouiller." or "Positions verrouillées.")
end

-- Joue les 3 alertes pendant 3 secondes, puis rend la main au détecteur.
function NS:Test()
    self:Fire("CAST_START", "test", "Aperçu", 0)
    NS.Timer.After(3, function()
        NS:Fire("CAST_STOP")
        NS.Detector:ClearAlert()
        NS.Detector:Wake()
    end)
end

--------------------------------------------------------------------------------
-- SavedVariables : initialisées avant toute lecture de NS.db par les alertes.
--------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    KickAlertDB = KickAlertDB or {}
    CopyDefaults(NS.DEFAULTS, KickAlertDB)
    NS.db = KickAlertDB
    NS:Fire("DB_READY")
end)

--------------------------------------------------------------------------------
-- Slash
--------------------------------------------------------------------------------

SLASH_KICKALERT1 = "/kickalert"
SLASH_KICKALERT2 = "/ka"
SlashCmdList.KICKALERT = function(msg)
    local command, argument = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "unlock" then
        NS:SetUnlocked(true)
    elseif command == "lock" then
        NS:SetUnlocked(false)
    elseif command == "test" then
        NS:Test()
    elseif command == "reset" then
        NS:Fire("RESET_ANCHORS")
        NS.Print("Positions réinitialisées.")
    elseif command == "spell" then
        -- /ka spell <id> force le sort d'interruption suivi, /ka spell auto revient à la détection.
        NS.db.spellId = tonumber(argument)
        NS.Detector:ResolveInterrupt()
        NS.Print(NS.db.spellId and ("Interruption forcée : " .. (NS.Detector.interruptName or argument))
            or "Interruption détectée automatiquement.")
    elseif command == "status" then
        for _, line in ipairs(NS.Detector:StatusLines()) do NS.Print(line) end
    else
        NS.OpenOptions()
    end
end
