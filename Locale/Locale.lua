-- Locale/Locale.lua : résolution de la langue. Chargé après les fichiers de
-- traduction et avant le reste de l'addon.
--
-- NS.L est une table remplie sur place, jamais remplacée : Core.lua et Config.lua
-- en gardent une référence locale dès le chargement, et changer de langue ne doit
-- pas les laisser pointer sur l'ancienne table.
local _, NS = ...

NS.locales = NS.locales or {}
NS.L = NS.L or {}

-- Ordre d'affichage dans les options. Le nom est écrit dans sa propre langue :
-- quelqu'un qui cherche sa langue ne lit pas forcément celle affichée.
NS.LOCALE_ORDER = {
    { code = "enUS", name = "English" },
    { code = "frFR", name = "Français" },
    { code = "deDE", name = "Deutsch" },
    { code = "esES", name = "Español (EU)" },
    { code = "esMX", name = "Español (AL)" },
    { code = "itIT", name = "Italiano" },
    { code = "ptBR", name = "Português" },
    { code = "ruRU", name = "Русский" },
    { code = "koKR", name = "한국어" },
    { code = "zhCN", name = "简体中文" },
    { code = "zhTW", name = "繁體中文" },
}

--- Nom lisible d'un code de langue, ou le code brut s'il est inconnu.
function NS.LocaleName(code)
    for _, entry in ipairs(NS.LOCALE_ORDER) do
        if entry.code == code then return entry.name end
    end
    return code
end

--- Langue du client, repliée sur enUS si KickAlert ne la traduit pas.
function NS.ClientLocale()
    local code = GetLocale and GetLocale() or "enUS"
    return NS.locales[code] and code or "enUS"
end

--- Applique une langue à NS.L. `code` vaut "auto" (ou nil) pour suivre le client.
-- enUS sert de base : une clé non traduite reste lisible au lieu d'afficher nil.
function NS.SetLocale(code)
    if not code or code == "auto" then code = NS.ClientLocale() end
    if not NS.locales[code] then code = "enUS" end

    for key in pairs(NS.L) do NS.L[key] = nil end
    for key, value in pairs(NS.locales.enUS) do NS.L[key] = value end
    if code ~= "enUS" then
        for key, value in pairs(NS.locales[code]) do NS.L[key] = value end
    end

    NS.activeLocale = code
    return code
end

-- Langue du client au chargement : les réglages sauvegardés ne sont pas encore
-- lus à ce stade, Core.lua réapplique le choix de l'utilisateur au DB_READY.
NS.SetLocale("auto")
