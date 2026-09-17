-- tests/run_tests.lua
-- Tests headless : lua5.1 tests/run_tests.lua [--no-c-timer] [--retail]
--
-- Les fichiers se chargent dans l'ordre du .toc, avec le même vararg
-- (addonName, ns) que le client, puis on pilote le temps et les events à la
-- main. Le mock est celui de MyBossSuite (tests/wow_mock.lua), complété ici des
-- méthodes que KickAlert utilise en plus.

package.path = "tests/?.lua;" .. package.path
require("wow_mock")

--------------------------------------------------------------------------------
-- Compléments du mock
--------------------------------------------------------------------------------

local useNativeTimers, retail = true, false
for _, argument in ipairs({ ... }) do
    if argument == "--no-c-timer" then useNativeTimers = false end
    if argument == "--retail" then retail = true end
end

local FrameMeta = getmetatable(CreateFrame("Frame"))
local function NoOp() end
for _, name in ipairs({ "SetAutoFocus", "ClearFocus", "SetValueStep", "SetObeyStepOnDrag" }) do
    FrameMeta[name] = FrameMeta[name] or NoOp
end
-- Dégradés : ancienne API (SetGradientAlpha) en classic, SetGradient + CreateColor en retail.
Mock.gradients = 0
if retail then
    FrameMeta.SetGradient = function() Mock.gradients = Mock.gradients + 1 end
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
else
    FrameMeta.SetGradientAlpha = function() Mock.gradients = Mock.gradients + 1 end
end
FrameMeta.GetStringWidth  = FrameMeta.GetStringWidth  or function(self) return (self.fontSize or 12) * 3 end
FrameMeta.GetStringHeight = FrameMeta.GetStringHeight or function(self) return self.fontSize or 12 end

--------------------------------------------------------------------------------
-- Framework minimal
--------------------------------------------------------------------------------

local passed, failed = 0, 0
local function say(line) io.write(line, "\n") end
local function suite(name) say("\n== " .. name) end

local function ok(condition, label)
    if condition then
        passed = passed + 1
        say("  ok   " .. label)
    else
        failed = failed + 1
        say("  FAIL " .. label)
    end
end

local function equal(actual, expected, label)
    ok(actual == expected, ("%s (attendu %s, obtenu %s)"):format(label, tostring(expected), tostring(actual)))
end

--------------------------------------------------------------------------------
-- Chargement
--------------------------------------------------------------------------------

local FILES = { "Compat.lua", "Core.lua", "Alerts.lua", "Detector.lua", "Nameplates.lua", "Config.lua" }

Mock.InstallTimerAPI(useNativeTimers)
if retail then Mock.InstallRetail() end

local ns = {}
for _, file in ipairs(FILES) do
    local chunk = assert(loadfile(file))
    chunk("KickAlert", ns)
end
Mock.FireEvent("ADDON_LOADED", "KickAlert")

local BOSS_GUID   = "Creature-0-1-2-3-10184-000001"
local PLAYER_GUID = "Player-0-0001"
local Text, Aura, Detector = ns.Text, ns.Aura, ns.Detector

local function StartCast(spellId, notInterruptible)
    Mock.SetCast("target", spellId, notInterruptible)
    Mock.FireEvent("UNIT_SPELLCAST_START", "target")
end

local function StopCast()
    Mock.SetCast("target", nil)
    Mock.FireEvent("UNIT_SPELLCAST_STOP", "target")
end

--------------------------------------------------------------------------------

suite("Compat")
equal(ns.has.nativeTimers, useNativeTimers, "détection de C_Timer")
equal(ns.flavor, retail and "retail" or "vanilla", "flavor détecté")
ok(ns.db ~= nil and ns.db.text.label == "KICK", "SavedVariables initialisées avec les défauts")
ok(ns.KnowsSpell(1766), "KnowsSpell : sort du grimoire")
equal(ns.KnowsSpell(2139), false, "KnowsSpell : sort inconnu")
equal(ns.GetSpellRemaining(1766), 0, "kick prêt = 0")

Mock.SetCast("target", 17086, true)
local castName, _, _, _, castProtected, castSpell = ns.GetCastInfo("target")
equal(castName, "Flame Breath", "GetCastInfo : nom")
equal(castProtected, true, "GetCastInfo : cast protégé")
equal(castSpell, 17086, "GetCastInfo : spellId")
Mock.legacyCastInfo = true
castName, _, _, _, castProtected, castSpell = ns.GetCastInfo("target")
equal(castProtected, false, "GetCastInfo (Classic Era) : pas de notInterruptible = interruptible")
equal(castSpell, 17086, "GetCastInfo (Classic Era) : spellId lu malgré le décalage")
Mock.legacyCastInfo = false
Mock.SetCast("target", nil)

suite("Détection")
equal(Detector.interruptSpell, 1766, "interrupt de la classe détecté dans le grimoire")

Mock.units.target = { guid = BOSS_GUID, name = "Onyxia", health = 100, healthMax = 100 }
Mock.FireEvent("PLAYER_TARGET_CHANGED")

local soundsBefore = #Mock.sounds
StartCast(17086, false)
ok(Text:IsShown(), "cast interruptible : texte affiché")
equal(Text.label:GetText(), "KICK", "texte KICK")
ok(Aura:IsShown(), "cast interruptible : halo affiché")
ok(Mock.gradients > 0, "halo : dégradé appliqué via l'API du client")
equal(#Mock.sounds, soundsBefore + 1, "cast interruptible : son joué une fois")

StartCast(17086, true)
equal(Text:IsShown(), false, "cast devenu protégé : alerte retirée")
StopCast()
StartCast(17086, false)
ok(Text:IsShown(), "cast interruptible : alerte de nouveau")

soundsBefore = #Mock.sounds
Mock.Advance(3)
ok(Text:IsShown(), "l'alerte reste tant que l'incantation dure")
equal(#Mock.sounds, soundsBefore, "le ticker ne rejoue pas le son")

StopCast()
equal(Text:IsShown(), false, "alerte retirée à la fin de l'incantation")
equal(Aura:IsShown(), false, "halo retiré à la fin de l'incantation")

Mock.cooldowns[1766] = { start = Mock.now, duration = 15 }
StartCast(17086, false)
equal(Text:IsShown(), false, "kick en cooldown : aucune alerte")
Mock.cooldowns[1766] = nil
Mock.Advance(0.4)
ok(Text:IsShown(), "alerte dès que le kick revient, sans nouvel event (ticker)")

Mock.outOfRange = true
Mock.Advance(0.4)
equal(Text:IsShown(), false, "hors de portée : alerte retirée")
Mock.outOfRange = false
Mock.Advance(0.4)
ok(Text:IsShown(), "de retour à portée : alerte de nouveau")

ns.db.onlyWhenReady = false
Mock.cooldowns[1766] = { start = Mock.now, duration = 15 }
Detector:ClearAlert()
equal(Text:IsShown(), false, "alerte effacée manuellement")
Mock.Advance(0.4)
ok(Text:IsShown(), "option 'kick dispo requis' désactivée : alerte neuve malgré le cooldown")
Mock.cooldowns[1766] = nil
ns.db.onlyWhenReady = true
StopCast()

-- Repli combat log, pour les clients où UnitCastingInfo ne répond rien.
Mock.FireCombatLog("SPELL_CAST_START", BOSS_GUID, PLAYER_GUID, 18435, "Fireball Volley")
ok(Text:IsShown(), "repli combat log : alerte sur SPELL_CAST_START")
Mock.FireCombatLog("SPELL_CAST_SUCCESS", BOSS_GUID, PLAYER_GUID, 18435, "Fireball Volley")
equal(Text:IsShown(), false, "repli combat log : alerte retirée au SUCCESS")

Mock.SetCast("target", 18435, false)
Mock.FireCombatLog("SPELL_CAST_START", BOSS_GUID, PLAYER_GUID, 18435, "Fireball Volley")
Mock.FireEvent("UNIT_SPELLCAST_START", "target")
ok(Text:IsShown(), "cast vu par l'API et par le combat log : alerte")
Mock.SetCast("target", nil)
Mock.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "target")
equal(Text:IsShown(), false, "cast annulé côté client : pas d'incantation fantôme via le repli")
Mock.Advance(0.5)
equal(Text:IsShown(), false, "... et le ticker ne la ressort pas")

Mock.FireCombatLog("SPELL_CAST_START", "Creature-0-1-2-3-99999-000009", PLAYER_GUID, 18435, "Autre")
equal(Text:IsShown(), false, "incantation d'une autre unité : ignorée")

Mock.legacyCastInfo = true
StartCast(17086, false)
ok(Text:IsShown(), "Classic Era (sans notInterruptible) : alerte")
Mock.legacyCastInfo = false
StopCast()

Mock.FireEvent("PLAYER_REGEN_ENABLED")
equal(Detector.poll, nil, "fin de combat : ticker arrêté")

suite("Alertes indépendantes")
ns.db.text.enabled = false
ns.db.sound.enabled = false
soundsBefore = #Mock.sounds
StartCast(17086, false)
equal(Text:IsShown(), false, "texte désactivé : pas de texte")
ok(Aura:IsShown(), "texte désactivé : le halo s'affiche quand même")
equal(#Mock.sounds, soundsBefore, "son désactivé : silence")
StopCast()
ns.db.text.enabled = true
ns.db.sound.enabled = true
ns.db.aura.enabled = false
StartCast(17086, false)
ok(Text:IsShown(), "halo désactivé : le texte s'affiche quand même")
equal(Aura:IsShown(), false, "halo désactivé : pas de halo")
StopCast()
ns.db.aura.enabled = true

ns.db.text.label = "STOP ÇA"
ns.db.text.size = 64
StartCast(17086, false)
equal(Text.label:GetText(), "STOP ÇA", "mot affiché configurable")
equal(select(2, Text.label:GetFont()), 64, "taille de police configurable")
StopCast()
ns.db.text.label = "KICK"

suite("Commandes")
SlashCmdList.KICKALERT("spell 2139")
equal(Detector.interruptSpell, 2139, "/ka spell <id>")
SlashCmdList.KICKALERT("spell auto")
equal(Detector.interruptSpell, 1766, "/ka spell auto")

SlashCmdList.KICKALERT("unlock")
ok(Text:IsShown(), "/ka unlock : texte visible pour le déplacement")
SlashCmdList.KICKALERT("lock")
equal(Text:IsShown(), false, "/ka lock : texte masqué")

SlashCmdList.KICKALERT("test")
ok(Text:IsShown() and Aura:IsShown(), "/ka test : les alertes s'affichent")
Mock.Advance(3.2)
equal(Text:IsShown(), false, "/ka test : fin après 3 secondes")

Text:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -200)
Text:SaveAnchor()
equal(ns.db.anchors.Text.x, 100, "position du texte sauvée")
SlashCmdList.KICKALERT("reset")
equal(ns.db.anchors.Text, nil, "/ka reset : position oubliée")

suite("Nameplates")
local Nameplate = ns.Nameplate

Mock.AddNamePlate("nameplate3", "Creature-0-1-2-3-40000-000001")
Mock.SetCast("nameplate3", 17086, false)
Mock.FireEvent("UNIT_SPELLCAST_START", "nameplate3")
ok(Nameplate:GetFrame("nameplate3"):IsShown(), "cast interruptible sur nameplate : indicateur affiché")
equal(Nameplate:GetFrame("nameplate3").label:GetText(), "KICK", "texte KICK sur la nameplate")

Mock.SetCast("nameplate3", 17086, true)
Mock.FireEvent("UNIT_SPELLCAST_START", "nameplate3")
equal(Nameplate:GetFrame("nameplate3"):IsShown(), false, "cast protégé sur nameplate : rien affiché")

Mock.SetCast("nameplate3", 17086, false)
Mock.FireEvent("UNIT_SPELLCAST_START", "nameplate3")
ok(Nameplate:GetFrame("nameplate3"):IsShown(), "de nouveau interruptible : réaffiché")
Mock.SetCast("nameplate3", nil)
Mock.FireEvent("UNIT_SPELLCAST_STOP", "nameplate3")
equal(Nameplate:GetFrame("nameplate3"):IsShown(), false, "fin de l'incantation : masqué")

Mock.SetCast("nameplate3", 17086, false)
Mock.FireEvent("UNIT_SPELLCAST_START", "nameplate3")
Mock.SetCast("nameplate3", nil)
Mock.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate3")
equal(Nameplate:GetFrame("nameplate3"):IsShown(), false, "incantation interrompue : masqué")

Mock.AddNamePlate("nameplate4", "Player-0-0099", { friendly = true })
Mock.SetCast("nameplate4", 17086, false)
Mock.FireEvent("UNIT_SPELLCAST_START", "nameplate4")
equal(Nameplate:GetFrame("nameplate4"):IsShown(), false, "unité amicale : jamais affiché")

Mock.SetCast("nameplate3", 17086, false)
Mock.FireEvent("UNIT_SPELLCAST_START", "nameplate3")
Mock.RemoveNamePlate("nameplate3")
equal(Nameplate:GetFrame("nameplate3"):IsShown(), false, "nameplate retirée : masqué")

local framesBefore = #Mock.frames
Mock.AddNamePlate("nameplate3", "Creature-0-1-2-3-40001-000002")
Mock.SetCast("nameplate3", 17086, false)
Mock.FireEvent("UNIT_SPELLCAST_START", "nameplate3")
ok(Nameplate:GetFrame("nameplate3"):IsShown(), "nameplate réapparue (autre GUID) : réaffiché")
-- +1 seul : le nouveau frame nameplate mocké, l'indicateur est réutilisé depuis le pool.
equal(#Mock.frames, framesBefore + 1, "l'indicateur est réutilisé, pas recréé")
equal(Nameplate:GetFrame("nameplate3").parent, Mock.namePlates.nameplate3,
    "indicateur ré-ancré sur la nouvelle nameplate")
Mock.SetCast("nameplate3", nil)
Mock.FireEvent("UNIT_SPELLCAST_STOP", "nameplate3")

ns.db.nameplate.enabled = false
Mock.SetCast("nameplate3", 17086, false)
Mock.FireEvent("UNIT_SPELLCAST_START", "nameplate3")
equal(Nameplate:GetFrame("nameplate3"):IsShown(), false, "module désactivé : jamais affiché")
ns.db.nameplate.enabled = true
Nameplate:RefreshAll()
ok(Nameplate:GetFrame("nameplate3"):IsShown(), "module réactivé : réapparaît sans attendre le prochain event de cast")
Mock.SetCast("nameplate3", nil)
Mock.FireEvent("UNIT_SPELLCAST_STOP", "nameplate3")

ns.db.nameplate.text.label = "GO"
ns.db.nameplate.text.size = 20
Mock.SetCast("nameplate3", 17086, false)
Mock.FireEvent("UNIT_SPELLCAST_START", "nameplate3")
equal(Nameplate:GetFrame("nameplate3").label:GetText(), "GO", "mot affiché configurable")
equal(select(2, Nameplate:GetFrame("nameplate3").label:GetFont()), 20, "taille configurable")
Mock.SetCast("nameplate3", nil)
Mock.FireEvent("UNIT_SPELLCAST_STOP", "nameplate3")
ns.db.nameplate.text.label = "KICK"
ns.db.nameplate.text.size = 14

--------------------------------------------------------------------------------

say(("\n%d ok, %d échec(s)"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
